#include "CdmHost.h"

#include "CdmHandler.h"
#include "CdmWrapper.h"

NSString *const kiOSCdmError = @"kiOSCdmError";
static NSUInteger kWidevineSystemIdOffset = 12;

@interface iOSCdm ()<iOSCdmHandler>
@end

@implementation iOSCdm {
  NSMutableDictionary *_sessionIdsToBlocks;
  NSMutableDictionary *_psshKeysToIds;
  NSMutableDictionary *_offlineSessions;
  uint32_t _currentSessionId;
  __weak id<iOSCdmDelegate> _delegate;
}

- (id)init {
  self = [super init];
  if (self) {
    iOSCdmHost::GetHost()->Initialize();
    iOSCdmHost::GetHost()->SetiOSCdmHandler(self);
  }
  return self;
}

- (void)dealloc {
  iOSCdmHost::GetHost()->SetiOSCdmHandler(nil);
  iOSCdmHost::GetHost()->Deinitialize();
}

#pragma mark -
#pragma mark public methods

+ (iOSCdm *)sharedInstance {
  static dispatch_once_t token;
  static iOSCdm *s_host = nil;
  dispatch_once(&token, ^{
    s_host = [[iOSCdm alloc] init];
  });
  return s_host;
}

- (void)setupCdmWithDelegate:(id<iOSCdmDelegate>)delegate {
  _delegate = delegate;
  _sessionIdsToBlocks = [[NSMutableDictionary alloc] init];
  _psshKeysToIds = [[NSMutableDictionary alloc] init];
  _offlineSessions = [[NSMutableDictionary alloc] init];
}

- (void)shutdownCdm {
  NSArray *sessionIds = _psshKeysToIds.allValues;
  _sessionIdsToBlocks = nil;
  _psshKeysToIds = nil;
  _offlineSessions = nil;

  iOSCdmHost::GetHost()->CloseSessions(sessionIds);
  _delegate = nil;
}

- (void)processPsshKey:(NSData *)psshKey
              mimeType:(NSString *)mimeType
          isOfflineVod:(BOOL)isOfflineVod
       completionBlock:(void(^)(NSError *))completionBlock {
  static const uint8_t kWidevineSystemId[] = {
    0xED, 0xEF, 0x8B, 0xA9, 0x79, 0xD6, 0x4A, 0xCE,
    0xA3, 0xC8, 0x27, 0xDC, 0xD5, 0x1D, 0x21, 0xED,
  };
  if ([psshKey length] < kWidevineSystemIdOffset + sizeof(kWidevineSystemId) ||
      memcmp(reinterpret_cast<const uint8_t *>([psshKey bytes]) + kWidevineSystemIdOffset,
             kWidevineSystemId, sizeof(kWidevineSystemId))) {
    return;
  }

  dispatch_queue_t queue = [_delegate iOSCdmDispatchQueue:self];

  NSNumber *sessionIdForKey = _psshKeysToIds[psshKey];
  if (!sessionIdForKey) {
    uint32_t sessionId = _currentSessionId;
    _psshKeysToIds[psshKey] = @(sessionId);
    [[self blocksForSessionId:sessionId] addObject:[completionBlock copy]];
    _currentSessionId++;

    NSString *webSessionId = nil;
    if (isOfflineVod && [_delegate respondsToSelector:@selector(webSessionForPssh:)]) {
      webSessionId = [_delegate webSessionForPssh:psshKey];
    }
    if (webSessionId) {
      _offlineSessions[@(sessionId)] = @YES;
      iOSCdmHost::GetHost()->LoadSession(sessionId, webSessionId);
    } else {
      iOSCdmHost::GetHost()->CreateSession(sessionId,
                                           mimeType,
                                           psshKey,
                                           isOfflineVod ? cdm::kPersistent : cdm::kTemporary);
    }
  } else {
    NSMutableArray *blocks = _sessionIdsToBlocks[sessionIdForKey];
    if (blocks) {
      [blocks addObject:[completionBlock copy]];
    } else if (queue) {
      dispatch_async(queue, ^{
          completionBlock(nil);
      });
    }
  }
}

- (void)removeOfflineLicenseForPsshKey:(NSData *)psshKey
                       completionBlock:(void(^)(NSError *))completionBlock {
  NSString *webSessionId = nil;
  if ([_delegate respondsToSelector:@selector(webSessionForPssh:)]) {
    webSessionId = [_delegate webSessionForPssh:psshKey];
  }
  if (webSessionId) {
    NSNumber *sessionIdForKey = _psshKeysToIds[psshKey];
    if (!sessionIdForKey) {
      uint32_t sessionId = _currentSessionId++;
      sessionIdForKey = @(sessionId);
      _psshKeysToIds[psshKey] = sessionIdForKey;
      [[self blocksForSessionId:sessionId] addObject:[completionBlock copy]];
    }

    iOSCdmHost::GetHost()->RemoveSession([sessionIdForKey intValue], webSessionId);
    [_offlineSessions removeObjectForKey:sessionIdForKey];
    [_psshKeysToIds removeObjectForKey:sessionIdForKey];
  }
}

- (NSData *)decrypt:(NSData *)encrypted keyId:(NSData *)keyId IV:(NSData *)iv {
  return iOSCdmHost::GetHost()->Decrypt(encrypted, keyId, iv);
}

#pragma mark -
#pragma mark iOSCdmHandler methods

- (void)onSessionMessage:(uint32_t)sessionId
         requestWithData:(NSData *)data
                   toURL:(NSString *)destinationUrl
         completionBlock:(void(^)(NSData *, NSError *))completionBlock {
  if ([_delegate respondsToSelector:
          @selector(iOSCdm:sendData:offline:toURL:completionBlock:)]) {

    BOOL isOffline = [_offlineSessions[@(sessionId)] isEqual:@YES];
    [_delegate iOSCdm:self
               sendData:data
                offline:isOffline
                  toURL:destinationUrl
        completionBlock:completionBlock];
  } else {
    [_delegate iOSCdm:self fetchLicenseWithData:data completionBlock:completionBlock];
  }
}

- (void)onSessionCreated:(uint32_t)sessionId webId:(NSString *)webId {
  NSArray *keys = [_psshKeysToIds allKeysForObject:@(sessionId)];
  for (NSData *key in keys) {
    if ([_delegate respondsToSelector:@selector(onSessionCreatedWithPssh:webId:)]) {
      [_delegate onSessionCreatedWithPssh:key webId:webId];
    }
  }
  if ([_offlineSessions[@(sessionId)] isEqual:@YES]) {
    [self callBlockWithError:nil forSessionId:sessionId];
    [_sessionIdsToBlocks removeObjectForKey:@(sessionId)];
    [_offlineSessions removeObjectForKey:@(sessionId)];
  }
}

- (void)onSessionUpdated:(uint32_t)sessionId {
  [self callBlockWithError:nil forSessionId:sessionId];
  [_sessionIdsToBlocks removeObjectForKey:@(sessionId)];
}

- (void)onSessionClosed:(uint32_t)sessionId {
  // NOOP.
}

- (void)onSessionFailed:(uint32_t)sessionId error:(NSError *)error {
  if (_sessionIdsToBlocks[@(sessionId)]) {
    [self callBlockWithError:error forSessionId:sessionId];
    [_sessionIdsToBlocks removeObjectForKey:@(sessionId)];
    NSArray *keys = [_psshKeysToIds allKeysForObject:@(sessionId)];
    [_psshKeysToIds removeObjectsForKeys:keys];
    iOSCdmHost::GetHost()->CloseSessions(@[ @(sessionId) ]);
  }
}

#pragma mark -
#pragma mark private methods

- (NSMutableArray *)blocksForSessionId:(uint32_t)sessionId {
  NSMutableArray *blocks = _sessionIdsToBlocks[@(sessionId)];
  if (!blocks) {
    blocks = [NSMutableArray array];
    _sessionIdsToBlocks[@(sessionId)] = blocks;
  }
  return blocks;
}

- (void)callBlockWithError:(NSError *)error forSessionId:(uint32_t)sessionId {
  NSArray *blocks = _sessionIdsToBlocks[@(sessionId)];
  for (void (^block)(NSError *error) in blocks) {
    block(error);
  }
}

- (NSData *)readFile:(NSString *)fileName {
  if ([_delegate respondsToSelector:@selector(readFile:)]) {
    return [_delegate readFile:fileName];
  } else {
    return nil;
  }
}

- (void)writeData:(NSData *)data file:(NSString *)fileName {
  if ([_delegate respondsToSelector:@selector(writeData:file:)]) {
    [_delegate writeData:data file:fileName];
  }
}

@end
