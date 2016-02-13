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

// TODO: Forward all errors given from the CdmHost.
- (id)init {
  self = [super init];
  if (self) {
    // TODO(justsomeguy): Add ability to change client info and cdm settings.
    widevine::Cdm::ClientInfo clientInfo;
    NSString *displayName = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    std::string product =
        displayName ? std::string(displayName.UTF8String) : "cdm_test";

    clientInfo.product_name = product;
    clientInfo.company_name = "WV";
    clientInfo.device_name = "iPhone";
    clientInfo.model_name = "6+";
    clientInfo.arch_name = "arm64";
    clientInfo.build_info = "0.1";
    iOSCdmHost::GetHost()->Initialize(clientInfo, widevine::Cdm::kWarnings);
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
  dispatch_queue_t queue = [_delegate iOSCdmDispatchQueue:self];

  NSString *sessionIdForKey = _psshKeysToIds[psshKey];
  if (!sessionIdForKey) {
    NSString *sessionId;
    NSError *error;
    if (isOfflineVod &&
        [_delegate respondsToSelector:@selector(webSessionForPssh:)]) {
      sessionId = [_delegate webSessionForPssh:psshKey];
    }

    if (sessionId) {
      error = iOSCdmHost::GetHost()->LoadSession(sessionId);
      if (error) {
        dispatch_async(queue, ^{
          completionBlock(error);
        });
        return;
      }
      _psshKeysToIds[psshKey] = sessionId;
      _offlineSessions[sessionId] = @YES;
      NSMutableArray *blocks = _sessionIdsToBlocks[sessionIdForKey];
      if (blocks) {
        [blocks addObject:[completionBlock copy]];
      } else if (queue) {
        dispatch_async(queue, ^{
          completionBlock(nil);
        });
      }
    } else {
      error  = iOSCdmHost::GetHost()->CreateSession(
          isOfflineVod ? widevine::Cdm::kPersistent :
                         widevine::Cdm::kTemporary,
          &sessionId);
      if (error) {
        dispatch_async(queue, ^{
          completionBlock(error);
        });
        return;
      }

      // Add the completionBlock to the array to ensure the blocks are called
      // once the GenerateRequest completes.
      [[self blocksForSessionId:sessionId] addObject:[completionBlock copy]];

      error = iOSCdmHost::GetHost()->GenerateRequest(sessionId, psshKey);
      if (error) {
        // The completionBlock is not called if GenerateRequest fails, call it
        // here and clean up the session.
        dispatch_async(queue, ^{
          completionBlock(error);
        });
        [_sessionIdsToBlocks removeObjectForKey:sessionId];
        iOSCdmHost::GetHost()->CloseSessions(@[sessionId]);
        return;
      }
      _psshKeysToIds[psshKey] = sessionId;
      [self onSessionCreated:sessionId];
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
  NSString *sessionIdForKey = nil;
  if ([_delegate respondsToSelector:@selector(webSessionForPssh:)]) {
    sessionIdForKey = [_delegate webSessionForPssh:psshKey];
  }
  if (!sessionIdForKey) {
    sessionIdForKey = _psshKeysToIds[psshKey];
  }
  if (sessionIdForKey) {
    iOSCdmHost::GetHost()->RemoveSession(sessionIdForKey);
    [_offlineSessions removeObjectForKey:sessionIdForKey];
    [_psshKeysToIds removeObjectForKey:sessionIdForKey];
  }
}

- (NSData *)decrypt:(NSData *)encrypted keyId:(NSData *)keyId IV:(NSData *)iv {
  return iOSCdmHost::GetHost()->Decrypt(encrypted, keyId, iv);
}

#pragma mark -
#pragma mark iOSCdmHandler methods

- (void)onSessionMessage:(NSData *)data
               sessionId:(NSString *)sessionId
         completionBlock:(void(^)(NSData *, NSError *))completionBlock {
  if ([_delegate respondsToSelector:
          @selector(iOSCdm:sendData:offline:toURL:completionBlock:)]) {

    BOOL isOffline = [_offlineSessions[sessionId] isEqual:@YES];
    // TODO: Update delegate API.
    [_delegate iOSCdm:self
             sendData:data
              offline:isOffline
                toURL:nil
      completionBlock:completionBlock];
  } else {
    [_delegate iOSCdm:self
        fetchLicenseWithData:data
             completionBlock:completionBlock];
  }
}

- (void)onSessionCreated:(NSString *)sessionId {
  NSArray *keys = [_psshKeysToIds allKeysForObject:sessionId];
  for (NSData *key in keys) {
    if ([_delegate
            respondsToSelector:@selector(onSessionCreatedWithPssh:webId:)]) {
      [_delegate onSessionCreatedWithPssh:key webId:sessionId];
    }
  }
  if ([_offlineSessions[sessionId] isEqual:@YES]) {
    [self callBlockWithError:nil forSessionId:sessionId];
    [_sessionIdsToBlocks removeObjectForKey:sessionId];
    [_offlineSessions removeObjectForKey:sessionId];
  }
}

- (void)onSessionUpdated:(NSString *)sessionId {
  [self callBlockWithError:nil forSessionId:sessionId];
  [_sessionIdsToBlocks removeObjectForKey:sessionId];
}

- (void)onSessionFailed:(NSString *)sessionId error:(NSError *)error {
  if (_sessionIdsToBlocks[sessionId]) {
    [self callBlockWithError:error forSessionId:sessionId];
    [_sessionIdsToBlocks removeObjectForKey:sessionId];
    NSArray *keys = [_psshKeysToIds allKeysForObject:sessionId];
    [_psshKeysToIds removeObjectsForKeys:keys];
    iOSCdmHost::GetHost()->CloseSessions(@[ sessionId ]);
  }
}

#pragma mark -
#pragma mark private methods

- (NSMutableArray *)blocksForSessionId:(NSString *)sessionId {
  NSMutableArray *blocks = _sessionIdsToBlocks[sessionId];
  if (!blocks) {
    blocks = [NSMutableArray array];
    _sessionIdsToBlocks[sessionId] = blocks;
  }
  return blocks;
}

- (void)callBlockWithError:(NSError *)error forSessionId:(NSString *)sessionId {
  NSArray *blocks = _sessionIdsToBlocks[sessionId];
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

- (BOOL)writeFile:(NSData *)data file:(NSString *)fileName {
  if ([_delegate respondsToSelector:@selector(writeData:file:)]) {
    // TODO: Update delegate API.
    [_delegate writeData:data file:fileName];
    return YES;
  }
  return NO;
}

- (BOOL)fileExists:(NSString *)fileName {
  if ([_delegate respondsToSelector:@selector(fileExists:)]) {
    return [_delegate fileExists:fileName];
  } else {
    return NO;
  }
}

- (int32_t)fileSize:(NSString *)fileName {
  if ([_delegate respondsToSelector:@selector(fileSize:)]) {
    return [_delegate fileSize:fileName];
  } else {
    return -1;
  }
}

- (BOOL)removeFile:(NSString *)fileName {
  if ([_delegate respondsToSelector:@selector(removeFile:)]) {
    return [_delegate removeFile:fileName];
  } else {
    return NO;
  }
}

@end
