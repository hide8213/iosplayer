// Copyright 2015 Google Inc. All rights reserved.

#import "Stream.h"

#import "LiveStream.h"
#import "Streaming.h"

NSString *kAudioMimeType = @"audio/mp4";
NSString *kVideoMimeType = @"video/mp4";

// Handler used to hold pass the PSSH (License Key) to the DASH Transmuxer
// as part of Udt_SetPsshHandler.
static DashToHlsStatus dashPsshHandler(void *context, const uint8_t *pssh, size_t pssh_length) {
  Stream *stream = (__bridge Stream *)(context);
  [[iOSCdm sharedInstance] processPsshKey:[NSData dataWithBytes:pssh length:pssh_length]
                             isOfflineVod:[stream.sourceUrl isFileURL]
                          completionBlock:^(NSError *error) {
                            [stream.streaming streamReady:stream];
                          }];

  return kDashToHlsStatus_OK;
}

// Handler to be used with Udt_SetDecryptSample from the DASH Transmuxer.
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


@implementation LiveStream
@end

@implementation Stream

- (id)initWithStreaming:(Streaming *)streaming {
  self = [super init];
  if (self) {
    _liveStream = [[LiveStream alloc] init];
    _streaming = streaming;
  }
  return self;
}

- (BOOL)initialize:(NSData*)initializationData {
  struct DashToHlsSession *session = NULL;
  DashToHlsStatus status = Udt_CreateSession(&session);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not initialize session");
    return NO;
  }
  _session = session;
  status = [self setPsshHandler:dashPsshHandler];
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set PSSH Handler");
    return NO;
  }
  status = [self setDecryptionHandler:dashDecryptionHandler];
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set Decrypt Handler");
    return NO;
  }
  status = [self parseInitData:initializationData];
  if (status == kDashToHlsStatus_ClearContent) {
    [_streaming streamReady:self];
  } else if (status == kDashToHlsStatus_OK) {
  } else {
    NSLog(@"Could not parse dash");
    Udt_PrettyPrint(_session);
    return NO;
  }
  return YES;
}

- (void)hlsFromDashData:(NSData *)dashData {
  DashToHlsStatus status;
  const uint8_t* hlsSegment = NULL;
  size_t hlsSize = 0;
  NSData *data;
  NSError *error;
  bool is_video = self.isVideo;
  // Parse Data to setup UDT Session properties.
  status = [self parseInitData:dashData];
  if (status == kDashToHlsStatus_ClearContent) {
    [_streaming streamReady:self];
  } else if (kDashToHlsStatus_OK == status) {
    data = [NSData dataWithBytes:hlsSegment length:hlsSize];
    DashToHls_ReleaseHlsSegment(_session, (uint32_t)_streamIndex);
  } else {
    NSLog(@"Could not parse dash url=%@", _sourceUrl);
    Udt_PrettyPrint(_session);
    return;
  }
  return;
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

- (DashToHlsStatus)parseInitData:(NSData*)data {
  // If SegmentBase, use 0 to pass as Stream Index.
  return Udt_ParseDash(_session,
                       _dashMediaType == SEGMENT_BASE ? 0 : _streamIndex,
                       (uint8_t *)[data bytes],
                       [data length],
                       (uint8_t *)[_pssh bytes],
                       [_pssh length],
                       &_dashIndex);
}

// Debug logging formatting.
- (NSString *)description {
  return [NSString stringWithFormat:@"Stream%lu: isVideo=%s codec=%@ bandwidth=%lu \n url=%@",
              (unsigned long)_streamIndex, _isVideo ? "YES":"NO", _codecs,
              (unsigned long)_bandwidth, _sourceUrl];
}

@end

