// Copyright 2015 Google Inc. All rights reserved.

#import "Streaming.h"

#import <Responses/HTTPDataResponse.h>

#import "AppDelegate.h"
#import "DetailViewController.h"
#import "Downloader.h"
#import "HTTPResponse.h"
#import "LicenseManager.h"
#import "LocalWebServer.h"
#import "Mpd.h"
#import "OemcryptoIncludes.h"
#import "Stream.h"
#import "TBXML.h"

NSString *kStreamingReadyNotification = @"StreamingReadyNotificaiton";

@implementation Streaming {
  LocalWebServer *_localWebServer;
  NSUInteger _preloadCount;  // _streams is the mutex.
  NSMutableArray *_streams;
  NSString *_variantPlaylist;
}

@synthesize manifestURL = _manifestURL;

static float k90KRatio = 90000.0;
static NSString *kLocalPlaylist = @"dash2hls.m3u8";

static NSString *kAudioPlaylistFormat =
    @"#EXT-X-MEDIA:URI=\"%d.m3u8\",TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"audio%d\","
    @"DEFAULT=%@,AUTOSELECT=YES\n";

static NSString *kAudioSegmentFormat = @"#EXTINF:%0.06f,\nhttp://localhost:"
    @"50699/%d-%d.ts\n";

static NSString *kPlaylist = @"#EXTM3U\n#EXT-X-VERSION:3\n%@"
    @"#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-TARGETDURATION:%lld\n%@#EXT-X-ENDLIST";

static NSString *kVideoPlaylistFormat =
    @"#EXT-X-STREAM-INF:BANDWIDTH=%lu,CODECS=\"%@\",RESOLUTION=%.0lux%.0lu,AUDIO=\"audio\""
    @"\n%d.m3u8\n";

static NSString *kVideoSegmentFormat = @"#EXTINF:%0.06f,\nhttp://localhost:"
    @"50699/%d-%d.ts\n";


- (id)init {
  self = [super init];
  if (self) {
    _localWebServer = [[LocalWebServer alloc] initWithStreaming:self];
    NSError *error = nil;
    [_localWebServer start:&error];
    _streamingQ = dispatch_queue_create("Streaming", NULL);
    _streams = [NSMutableArray array];
    _variantPlaylist = @"#EXTM3U\n#EXT-X-VERSION:3\n";
  }
  return self;
}

- (void)stop {
  [_localWebServer stop];
}

- (NSURL*)manifestURL {
  return _manifestURL;
}

- (void)setManifestURL:(NSURL *)url {
  _manifestURL = url;
  dispatch_async(_streamingQ, ^{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:_manifestURL
                                         options:NSDataReadingUncached
                                           error:&error];
    if (error) {
      NSLog(@"Error reading %@ %@", _manifestURL, error);
    } else {
      [self parseManifest:data];
    }
  });
}

- (void)startVideoPlayer {
  [[NSNotificationCenter defaultCenter] postNotificationName:kStreamingReadyNotification
                                                      object:self];
}

- (void)buildVariantPlaylist {
  Stream *stream = nil;
  NSString *defaultAudioString = @"YES";
  for (stream in _streams) {
    if (stream.isVideo) {
      _variantPlaylist = [_variantPlaylist
                          stringByAppendingString:[NSString stringWithFormat:kVideoPlaylistFormat,
                                                   stream.bandwidth, stream.codec,
                                                   stream.width, stream.height, stream.index]];
    } else {
      _variantPlaylist = [_variantPlaylist
                          stringByAppendingString:[NSString stringWithFormat:kAudioPlaylistFormat,
                                                   stream.index, stream.index, defaultAudioString]];
      defaultAudioString = @"NO";
    }
  }
}

- (void)buildChildPlaylist:(Stream *)stream {
  NSMutableString *segments = [NSMutableString string];
  DashToHlsIndex *index = stream.dashIndex;
  uint64_t max_duration = 0;
  uint64_t timescale = (index->index_count > 0) ? index->segments[0].timescale:90000;
  for (uint64_t count = 0; count < index->index_count; ++count) {
    if (index->segments[count].duration > max_duration) {
      max_duration = index->segments[count].duration;
    }
    [segments appendFormat:stream.isVideo ? kVideoSegmentFormat:kAudioSegmentFormat,
      ((float)index->segments[count].duration / (float)timescale),
     stream.index, count, NULL];
  }
  stream.m3u8 = [[NSString stringWithFormat:kPlaylist, GetKeyUrl(stream.session),
                  (max_duration/timescale) + 1, segments]
                     dataUsingEncoding:NSUTF8StringEncoding];
}


// Called on _streamingQ.
- (void)loadStream:(Stream *)stream {
  [Downloader downloadPartialData:stream.url
                            range:stream.initializationRange
                       completion:^(NSData *data, NSError *connectionError) {
               dispatch_async(_streamingQ, ^() {
                 if (!data) {
                   NSLog(@"Did not download %@", connectionError);
                 }
                 if (![stream initialize:data]) {
                   return;
                 }
                 [self buildChildPlaylist:stream];
               });
             }];
}

- (void)streamReady:(Stream*)stream {
  stream.done = YES;
  --_preloadCount;
  if (_preloadCount == 0) {
    // streamReady is called in the middle of processing a stream.
    // Ensure all streams have been processed before sending to video player.
    dispatch_async(_streamingQ, ^() {
      dispatch_async(dispatch_get_main_queue(), ^(){
        [self startVideoPlayer];
      });
    });
  }
}

- (void)parseManifest:(NSData *)manifest {
  NSError *error;
  int stream_count = 0;
  NSString *rootUrl = nil;
  NSString *url_prefix = [[_manifestURL URLByDeletingLastPathComponent] absoluteString];

  TBXML *manifest_xml = [TBXML newTBXMLWithXMLData:manifest error:&error];
  if (error) {
    NSLog(@"Error: %@\n", error);
    EXIT_FAILURE;
  }

  // Create TBXML Elements and walk the DOM to find the necessary values
  TBXMLElement *mpdXML = manifest_xml.rootXMLElement;
  TBXMLElement *periodXML = [TBXML childElementNamed:kDashPeriod
                                       parentElement:mpdXML
                                               error:&error];
  TBXMLElement *rootUrlXML = [TBXML childElementNamed:kDashRepresentationBaseUrl
                                        parentElement:periodXML
                                                error:&error];
  // Handles segments being stored on separate server than MPD
  if (rootUrlXML) {
    rootUrl = [TBXML textForElement:rootUrlXML error:&error];
    // The root URL can start with // as opposed to a scheme, appends http(s)
    if ([rootUrl rangeOfString:@"http"].location == NSNotFound) {
      rootUrl = [_manifestURL.scheme stringByAppendingFormat:@":%@", rootUrl];
    }
  }

  TBXMLElement *adaptationXML = [TBXML childElementNamed:kDashAdaptationSet
                                           parentElement:periodXML
                                                   error:&error];
  do {
    // Extract Segment specific details: URL, Bandwidth, byte ranges, etc...
    TBXMLElement *representationXML = [TBXML childElementNamed:kDashRepresentation
                                                 parentElement:adaptationXML
                                                         error:&error];
    do {
      Stream *stream = [[Stream alloc] initWithStreaming:self];
      stream.isVideo = NO;
      stream_count++;
      stream.bandwidth = [[TBXML valueOfAttributeNamed:kDashRepresentationBW
                                            forElement:representationXML
                                                 error:&error]
                          integerValue];
      stream.codec = [TBXML valueOfAttributeNamed:kDashRepresentationCodec
                                       forElement:representationXML
                                            error:&error];
      stream.mimeType = [TBXML valueOfAttributeNamed:kDashRepresentationMime
                                          forElement:representationXML
                                               error:&error];
      TBXMLElement *baseUrlXML = [TBXML childElementNamed:kDashRepresentationBaseUrl
                                            parentElement:representationXML
                                                    error:&error];
      NSString *baseUrl = [TBXML textForElement:baseUrlXML error:&error];
      TBXMLElement *segmentBaseXML = [TBXML childElementNamed:kDashSegmentBase
                                                parentElement:representationXML
                                                        error:&error];
      NSString *url_string = [baseUrl stringByReplacingOccurrencesOfString:@"&amp;"
                                                                withString:@"&"];
      // Handle relative file name paths by appending Manifest URL
      if (rootUrl) {
        url_string = [rootUrl stringByAppendingString:url_string];
      } else if (![url_string hasPrefix:@"http://"] && ![url_string hasPrefix:@"https://"]) {
        url_string = [url_prefix stringByAppendingString:url_string];
      }
      stream.url = [NSURL URLWithString:url_string];
      if (_offline) {
        stream.url = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
                      urlInDocumentDirectoryForFile:stream.url.lastPathComponent];
      }
      // Set values into stream object to prep for m3u8 creation
      if ([stream.mimeType rangeOfString:@"video"].location != NSNotFound) {
        stream.isVideo = YES;
        stream.height = [[TBXML valueOfAttributeNamed:kDashRepresentationHeight
                                           forElement:representationXML
                                                error:&error]
                         integerValue];
        stream.width = [[TBXML valueOfAttributeNamed:kDashRepresentationWidth
                                          forElement:representationXML
                                               error:&error]
                        integerValue];
      }
      stream.done = NO;
      stream.initializationRange = [Mpd getInitRangeFromElement:segmentBaseXML];
      stream.index = _streams.count;
      [_streams addObject:stream];
      // END Representation Loop
    } while ((representationXML = representationXML->nextSibling));
    // END AdaptionSet Loop
  } while ((adaptationXML = adaptationXML->nextSibling));
  _preloadCount = stream_count;
  [self buildVariantPlaylist];
  [_streams enumerateObjectsUsingBlock:^(id obj,
                                         NSUInteger idx,
                                         BOOL *stop) {
    [self loadStream:obj];
  }];
}

- (NSData *)tsDataForIndex:(int)index segment:(int)segment {
  Stream *stream = _streams[index];
  NSURL *url = stream.url;
  NSMutableURLRequest *request =
      [NSMutableURLRequest requestWithURL:url
                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                          timeoutInterval:5];

  NSRange range = NSMakeRange(stream.dashIndex->segments[segment].location,
                              stream.dashIndex->segments[segment].length);
  NSData *response_data = [Downloader downloadPartialData:stream.url range:range completion:nil];

  if (!response_data) {
    NSLog(@"Could not initialize session url=%@", stream.url);
    return nil;
  }
  const uint8_t *hlsSegment;
  size_t hlsSize;
  DashToHlsStatus status = DashToHls_ConvertDashSegmentData(stream.session, segment,
                                                            (const uint8_t *)[response_data bytes],
                                                            [response_data length],
                                                            &hlsSegment, &hlsSize);
  if (kDashToHlsStatus_OK == status) {
    NSData  *response_data = [NSData dataWithBytes:hlsSegment length:hlsSize];
    DashToHls_ReleaseHlsSegment(stream.session, segment);
    return response_data;
  }
  return nil;
}

- (NSObject<HTTPResponse> *)responseForMethod:(NSString *)method
                                         path:(NSString *)path
                                   connection:(HTTPConnection *)connection {
  NSLog(@"response %@", path);
  NSData *response_data = nil;
  // Check for incoming filename and return appropriate data.
  if ([path.lastPathComponent isEqualToString:kLocalPlaylist]) {
    // kDashPlaylist is pre-assigned name in ViewController to ensure variant playlist creation.
    response_data = [_variantPlaylist dataUsingEncoding:NSUTF8StringEncoding];
  } else if ([path.pathExtension isEqualToString:@"m3u8"]) {
    // Catches children playlist requests and provides the appropriate data in place of m3u8.
    NSScanner *scanner = [NSScanner scannerWithString:path];
    int index = 0;
    if ([scanner scanString:@"/hls/" intoString:NULL] &&
      [scanner scanInt:&index]) {
      Stream *stream = _streams[index];
      response_data = stream.m3u8;
    }
  } else if ([path.pathExtension isEqualToString:@"ts"]){
    // Handles individual TS segment requests by transmuxing the source MP4.
    NSScanner *scanner = [NSScanner scannerWithString:path];
    int index = 0;
    int segment = 0;
    if ([scanner scanString:@"/" intoString:NULL] &&
        [scanner scanInt:&index] &&
        [scanner scanString:@"-" intoString:NULL] &&
        [scanner scanInt:&segment] &&
        [scanner scanString:@".ts" intoString:NULL]) {
      response_data = [self tsDataForIndex:index segment:segment];
    }
  }
  NSLog(@"responding %lu", (unsigned long)response_data.length);
  if (response_data) {
    return [[HTTPDataResponse alloc] initWithData:response_data];
  }
  return nil;
}

@end

