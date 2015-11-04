// Copyright 2015 Google Inc. All rights reserved.

#import "Stream.h"

#import "Streaming.h"

NSString *kAudioMimeType = @"audio/mp4";
NSString *kVideoMimeType = @"video/mp4";

static DashToHlsStatus dashPsshHandler(void *context, const uint8_t *pssh, size_t pssh_length) {
  Stream *stream = (__bridge Stream *)(context);
  [[iOSCdm sharedInstance] processPsshKey:[NSData dataWithBytes:pssh length:pssh_length]
                                 mimeType:stream.isVideo ? kVideoMimeType:kAudioMimeType
                             isOfflineVod:[stream.url isFileURL]
                          completionBlock:^(NSError *error) {
                            [stream.streaming streamReady:stream];
                          }];

  return kDashToHlsStatus_OK;
}

static DashToHlsStatus dashDecryptionHandler(void *context, const uint8_t *encrypted,
                                             uint8_t *clear, size_t length, uint8_t *iv,
                                             size_t iv_length, const uint8_t *key_id,
                                             struct SampleEntry *sampleEntry,
                                             size_t sampleEntrySize) {
  Stream *stream = (__bridge Stream *)(context);
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
    return;
  }
  _session = session;

  status = DashToHls_SetCenc_PsshHandler(_session,
                                         (__bridge DashToHlsContext)(self),
                                         dashPsshHandler);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set PSSH Handler url=%@", _url);
    return;
  }
  status = DashToHls_SetCenc_DecryptSample(_session,
                                           (__bridge DashToHlsContext)(self),
                                           dashDecryptionHandler,
                                           false);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set Decrypt Handler url=%@", _url);
    return NO;
  }

  struct DashToHlsIndex *index = NULL;
  status = DashToHls_ParseDash(_session,
                               (const uint8_t *)[initializationData bytes],
                               [initializationData length], &index);
  _dashIndex = index;
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

- (NSString *)description {
  return [NSString stringWithFormat:@"Stream:%@\n Video:%s codec:%@ index:%lu",
      _url, _isVideo ? "YES":"NO", _codec, (unsigned long)_index];
}

@end
