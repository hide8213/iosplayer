#include "CdmHost.h"

#include "CdmHandler.h"
#include "CdmWrapper.h"

NSString *const kiOSCdmError = @"kiOSCdmError";

@interface iOSCdm ()<iOSCdmHandler>
@end

@implementation iOSCdm {
  NSMutableDictionary *_sessionIdsToBlocks;
  NSMutableDictionary *_psshKeysToIds;
  NSMutableDictionary *_offlineSessions;
  uint32_t _currentSessionId;
  __weak id<iOSCdmDelegate> _delegate;
}

extern "C" {
extern const char *OEMCryptoTfit_Version();
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
    clientInfo.build_info = OEMCryptoTfit_Version();
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
          isOfflineVod:(BOOL)isOfflineVod
       completionBlock:(void(^)(NSError *))completionBlock {
  dispatch_queue_t queue = [_delegate iOSCdmDispatchQueue:self];
  NSString *sessionId = _psshKeysToIds[psshKey];
  NSError *error = nil;

  // No Session has been loaded.
  if (isOfflineVod && !sessionId) {
    // Check if license was previously stored.
    if ([_delegate respondsToSelector:@selector(sessionIdFromPssh:)]) {
      sessionId = [_delegate sessionIdFromPssh:psshKey];
    }
    // License exists, attempt to Load Session.
    if (sessionId) {
      error = iOSCdmHost::GetHost()->LoadSession(sessionId);
      if (error) {
        // Do NOT error out if session is already loaded.
        if (!error.code) {
          dispatch_async(queue, ^{
            completionBlock(error);
          });
          return;
        }
      }
      _psshKeysToIds[psshKey] = sessionId;
      _offlineSessions[sessionId] = @YES;
    }
  }
  if (!sessionId) {
    // Setup new Streaming Session.
    error = iOSCdmHost::GetHost()->CreateSession(
        isOfflineVod ? widevine::Cdm::kPersistent : widevine::Cdm::kTemporary,
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
      // The completionBlock is not called if GenerateRequest fails.
      // Call it here and clean up the session.
      dispatch_async(queue, ^{
        completionBlock(error);
      });
      iOSCdmHost::GetHost()->CloseSessions(@[ sessionId ]);
      return;
    }
    _psshKeysToIds[psshKey] = sessionId;
    [self onSessionCreated:sessionId];
  }
  NSMutableArray *blocks = _sessionIdsToBlocks[sessionId];
  if (blocks) {
    [blocks addObject:[completionBlock copy]];
  } else if (queue) {
    dispatch_async(queue, ^{
        completionBlock(nil);
    });
  }
}

- (void)getLicenseInfo:(NSData *)psshKey
       completionBlock:
           (void (^)(int64_t *expiration, NSError *))completionBlock {
  NSError *error = nil;
  NSString *sessionId = _psshKeysToIds[psshKey];

  dispatch_queue_t queue = [_delegate iOSCdmDispatchQueue:self];
  auto callCompletionBlock = ^(NSError *error) {
    if (queue && completionBlock) {
      dispatch_async(queue, ^{
        completionBlock(nil, error);
      });
    }
  };
  // No Session has been loaded.
  if (!sessionId) {
    // Check if license was previously stored.
    if ([_delegate respondsToSelector:@selector(sessionIdFromPssh:)]) {
      sessionId = [_delegate sessionIdFromPssh:psshKey];
    }
    // License exists, attempt to Load Session.
    if (sessionId) {
      error = iOSCdmHost::GetHost()->LoadSession(sessionId);
      if (error) {
        // Do NOT error out if session is already loaded.
        if (!error.code) {
          dispatch_async(queue, ^{
            completionBlock(nil, error);
          });
          return;
        }
      }
    }
    _psshKeysToIds[psshKey] = sessionId;
  }
  if (sessionId) {
    int64_t expiration;
    error = iOSCdmHost::GetHost()->GetLicenseInfo(sessionId, &expiration);
    if (error) {
      NSLog(@"::ERROR::Unable to get Expiration");
      callCompletionBlock(error);
      return;
    }
    if (expiration > 0) {
      NSTimeInterval timeInterval = double(expiration);
      NSDate *timeStamp = [NSDate dateWithTimeIntervalSince1970:timeInterval];
      NSLog(@"Expiration: %@", timeStamp);
    }
  }
  callCompletionBlock(error);
}

- (void)removeOfflineLicenseForPsshKey:(NSData *)psshKey
                       completionBlock:(void(^)(NSError *))completionBlock {
  dispatch_queue_t queue = [_delegate iOSCdmDispatchQueue:self];
  auto callCompletionBlock = ^(NSError *error) {
    if (queue && completionBlock) {
      dispatch_async(queue, ^{
        completionBlock(error);
      });
    }
  };
  NSString *sessionIdForKey = [_delegate sessionIdFromPssh:psshKey];
  if (sessionIdForKey) {
    NSError *error = nil;
    error = iOSCdmHost::GetHost()->RemoveSession(sessionIdForKey);
    if (error) {
      NSLog(@"::ERROR::Removing Session");
      callCompletionBlock(error);
      return;
    }
    if (![_delegate removePssh:psshKey]) {
      error = [NSError errorWithDomain:@"RemovePssh" code:errno userInfo:nil];
      NSLog(@"::ERROR::Removing PSSH: %@", error);
      callCompletionBlock(error);
      return;
    }
    [_offlineSessions removeObjectForKey:sessionIdForKey];
    [_psshKeysToIds removeObjectForKey:psshKey];
    callCompletionBlock(error);
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
  [_delegate iOSCdm:self
      fetchLicenseWithData:data
           completionBlock:completionBlock];
}

- (void)onSessionCreated:(NSString *)sessionId {
  NSArray *keys = [_psshKeysToIds allKeysForObject:sessionId];
  for (NSData *key in keys) {
    if ([_delegate respondsToSelector:@selector(onSessionCreatedWithPssh:sessionId:)]) {
      [_delegate onSessionCreatedWithPssh:key sessionId:sessionId];
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
  }
  if (_psshKeysToIds[sessionId]) {
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

- (int64_t)fileSize:(NSString *)fileName {
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
