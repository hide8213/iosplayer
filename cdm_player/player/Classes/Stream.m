// Copyright 2015 Google Inc. All rights reserved.

#import "Stream.h"

#import "Streaming.h"

NSString *kAudioMimeType = @"audio/mp4";
NSString *kVideoMimeType = @"video/mp4";

// Handler used to hold pass the PSSH (License Key) to the DASH Transmuxer
// as part of DashToHls_SetCenc_PsshHandler.
static DashToHlsStatus dashPsshHandler(void *context, const uint8_t *pssh, size_t pssh_length) {
  Stream *stream = (__bridge Stream *)(context);
  [[iOSCdm sharedInstance] processPsshKey:[NSData dataWithBytes:pssh length:pssh_length]
                             isOfflineVod:[stream.url isFileURL]
                          completionBlock:^(NSError *error) {
                            [stream.streaming streamReady:stream];
                          }];

  return kDashToHlsStatus_OK;
}

// Handler to be used with DashToHls_SetCenc_DecryptSample from the DASH Transmuxer.
static DashToHlsStatus dashDecryptionHandler(void *context, const uint8_t *encrypted,
                                             uint8_t *clear, size_t length, uint8_t *iv,
                                             size_t iv_length, const uint8_t *key_id,
                                             struct SampleEntry *sampleEntry,
                                             size_t sampleEntrySize) {
  NSData *decrypted = [[iOSCdm sharedInstance]
                       decrypt:[NSData dataWithBytes:encrypted length:length]
                         keyId:[NSData dataWithBytes:key_id length:16]
                            IV:[NSData dataWithBytes:iv length:iv_length]];
  if (!decrypted) {
    return kDashToHlsStatus_BadDashContents;
  }
  memcpy(clear, [decrypted bytes], length);
  return kDashToHlsStatus_OK;
}

@implementation Stream

- (id)initWithStreaming:(Streaming *)streaming {
  self = [super init];
  if (self) {
    _streaming = streaming;

  }
  return self;
}


- (BOOL)initialize:(NSData*)initializationData {
  struct DashToHlsSession *session = NULL;
  DashToHlsStatus status = DashToHls_CreateSession(&session);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not initialize session url=%@", _url);
    return NO;
  }
  _session = session;
  status = [self setPsshHandler:dashPsshHandler];
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set PSSH Handler url=%@", _url);
    return NO;
  }
  status = [self setDecryptionHandler:dashDecryptionHandler];
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set Decrypt Handler url=%@", _url);
    return NO;
  }
  status = [self parseInitData:initializationData];
  if (status == kDashToHlsStatus_ClearContent) {
    [_streaming streamReady:self];
  } else if (status == kDashToHlsStatus_OK) {
  } else {
    NSLog(@"Could not parse dash url=%@", _url);
    DashToHls_PrettyPrint(_session);
    return NO;
  }
  return YES;
}

- (DashToHlsStatus)setPsshHandler:(DashToHlsContext)handler {
  return DashToHls_SetCenc_PsshHandler(_session,
                                       (__bridge DashToHlsContext)(self),
                                       handler);
}

- (DashToHlsStatus)setDecryptionHandler:(DashToHlsContext)handler {
  return DashToHls_SetCenc_DecryptSample(_session,
                                         (__bridge DashToHlsContext)(self),
                                         handler,
                                         false);
}

- (DashToHlsStatus)parseInitData:(NSData*)initializationData {
  return DashToHls_ParseDash(_session,
                             (const uint8_t *)[initializationData bytes],
                             [initializationData length], &_dashIndex);
}


// Debug logging formatting.
- (NSString *)description {
  return [NSString stringWithFormat:@"Stream%lu: isVideo=%s codec=%@ bandwidth=%lu \n url=%@",
              (unsigned long)_indexValue, _isVideo ? "YES":"NO", _codecs, (unsigned long)_bandwidth,
              _url];
}

@end

