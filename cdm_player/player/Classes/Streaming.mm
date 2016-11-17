// Copyright 2015 Google Inc. All rights reserved.

#import "Streaming.h"

#import <arpa/inet.h>
#import <ifaddrs.h>
#import <string.h>

#import <Responses/HTTPDataResponse.h>

#import "DashToHlsApiAVFramework.h"
#import "Downloader.h"
#import "LocalWebServer.h"
#import "MpdParser.h"

NSString *kStreamingReadyNotification = @"StreamingReadyNotificaiton";

@implementation Streaming {
  LocalWebServer *_localWebServer;
  NSUInteger _currentAudioSegment;
  NSUInteger _currentVideoSegment;
}

static int sHttpPort = 8000;
static NSString *const kLocalPlaylist = @"dash2hls.m3u8";
static NSString *const kLocalHost = @"localhost";
static NSString *const kNumberPlaceholder = @"$Number";
// Regex to look for $Number$ or $Number<number padding>$
static NSString *const kNumberRegexPattern = @"\\$Number(%[^$]+)?\\$";
static NSString *const kNumberFormat = @"%d";

static NSString *kAudioPlaylistFormat =
    @"#EXT-X-MEDIA:URI=\"%d.m3u8\",TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"audio%"
    @"d\","
    @"DEFAULT=%@,AUTOSELECT=YES\n";
static NSString *kAudioSegmentFormat = @"#EXTINF:%0.06f,\n%d-%d.ts\n";

static NSString *const kDynamicPlaylistHeader = @"#EXTM3U\n"
                                                @"#EXT-X-VERSION:3\n"
                                                @"#EXT-X-MEDIA-SEQUENCE:%d\n"
                                                @"#EXT-X-TARGETDURATION:%d\n";

static NSString *const kPlaylistVOD = @"#EXTM3U\n"
                                      @"#EXT-X-VERSION:3\n"
                                      @"#EXT-X-MEDIA-SEQUENCE:%d\n"
                                      @"#EXT-X-TARGETDURATION:%llu\n";

static NSString *const kDiscontinuity = @"#EXT-X-DISCONTINUITY\n";
static NSString *const kPlaylistVODEnd = @"#EXT-X-ENDLIST";

static NSString *kVariantPlaylist = @"#EXTM3U\n#EXT-X-VERSION:3\n";

static NSString *kVideoPlaylistFormat =
    @"#EXT-X-STREAM-INF:BANDWIDTH=%lu,CODECS=\"%@\",RESOLUTION=%.0lux%.0lu,"
    @"AUDIO=\"audio\""
    @"\n%d.m3u8\n";

static NSString *kVideoSegmentFormat = @"#EXTINF:%0.06f,\n%d-%d.ts\n";

static NSString *kLiveBandwidth = @"$Bandwidth$";
static NSString *kLiveNumber = @"$Number$";
static NSString *kLiveRepresentationID = @"$RepresentationID$";

// Create streaming object with local IP address if Airplay is off or network IP if on.
- (id)initWithAirplay:(BOOL)isAirplayActive {
  self = [super init];
  if (self) {
    _address = kLocalHost;
    if (isAirplayActive) {
      _address = [self getIPAddress];
    }
    _localWebServer = [[LocalWebServer alloc] initWithStreaming:self];
    NSError *error = nil;
    // Random HTTP Port generator.
    // Avoids issues when multiple streams are selected quickly.
    _httpPort = sHttpPort++;
    [_localWebServer start:&error];
    _streamingQ = dispatch_queue_create("com.google.widevine.cdm-ref-player.Streaming", NULL);
    _streams = [NSMutableArray array];
  }
  return self;
}

// Recreates the streaming object with a different IP address.
- (void)restart:(BOOL)isAirplayActive {
  if (isAirplayActive) {
    _address = [self getIPAddress];
  } else {
    _address = kLocalHost;
  }
  NSError *error = nil;
  [_localWebServer stop];
  [_localWebServer start:&error];
}

// Stops the local web server.
- (void)stop {
  [_localWebServer stop];
  _streams = nil;
  _streamingQ = nil;
}

// Finds external facing IP address to use for Airplay streaming.
- (NSString *)getIPAddress {
  NSString *address;
  struct ifaddrs *interfaces = NULL;
  struct ifaddrs *temp_addr = NULL;

  // retrieve the current interfaces - returns 0 on success
  int retValue = getifaddrs(&interfaces);
  if (retValue == 0) {
    // Loop through linked list of interfaces
    temp_addr = interfaces;
    while (temp_addr != NULL) {
      if (temp_addr->ifa_addr->sa_family == AF_INET) {
        // Check if interface is en0 which is the wifi connection on the iPhone
        if (strcmp(temp_addr->ifa_name, "en0") == 0) {
          // Get NSString from C String
          char *utf8 = inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr);
          address = @(utf8);
          break;
        }
      }
      temp_addr = temp_addr->ifa_next;
    }
  }
  freeifaddrs(interfaces);
  return address;
}

// Downloads MPD and creates HLS Playlists.
- (void)processMpd:(NSURL *)mpdURL
    withCompletion:(void (^)(NSArray<Stream *> *streams, NSError *error))completion {
  // TODO(seawardt): Implement Logging macro
  NSParameterAssert(mpdURL);
  NSLog(@"\n::INFO::Processing: %@", mpdURL);
  dispatch_async(_streamingQ, ^{
    NSError *error = nil;
    NSData *mpdData =
        [NSData dataWithContentsOfURL:mpdURL options:NSDataReadingUncached error:&error];
    if (error) {
      completion(nil, error);
    } else {
      _streams =
          [MpdParser parseMpdWithStreaming:self mpdData:mpdData baseURL:mpdURL storeOffline:NO];
      _preloadCount = _streams.count;
      _variantPlaylist = [self buildVariantPlaylist:_streams];
      completion(_streams, nil);
    }
  });
}

- (void)processMpd:(NSURL *)mpdURL {
  [self processMpd:mpdURL
      withCompletion:^(NSArray<Stream *> *streams, NSError *error) {
        if (error) {
          NSLog(@"Error reading %@ %@", mpdURL, error);
        } else {
          for (Stream *stream in _streams) {
            [self loadStream:stream];
          }
        }
      }];
}

// Sends global notification that the streams are ready to start playback.
- (void)startVideoPlayer {
  [[NSNotificationCenter defaultCenter] postNotificationName:kStreamingReadyNotification
                                                      object:self];
}

// Create Variant playlist that contains all video and audio streams.
- (NSString *)buildVariantPlaylist:(NSArray *)parsedMpd {
  Stream *stream = nil;
  NSString *playlist = kVariantPlaylist;
  NSString *defaultAudioString = @"NO";
  for (stream in parsedMpd) {
    if (stream.isVideo) {
      playlist = [playlist stringByAppendingString:[NSString stringWithFormat:kVideoPlaylistFormat,
                                                                              stream.bandwidth,
                                                                              stream.codecs,
                                                                              stream.width,
                                                                              stream.height,
                                                                              stream.streamIndex]];
    } else {
      NSString *langAbbreviation = [[[NSLocale preferredLanguages] firstObject] substringToIndex:2];
      NSString *langString = [langAbbreviation stringByAppendingString:@"_"];
      if ([[stream.sourceURL absoluteString] containsString:langString]) {
        defaultAudioString = @"YES";
      }
      playlist = [playlist stringByAppendingString:[NSString stringWithFormat:kAudioPlaylistFormat,
                                                                              stream.streamIndex,
                                                                              stream.streamIndex,
                                                                              defaultAudioString]];
      defaultAudioString = @"NO";
    }
  }
  return playlist;
}

// Build playlist based on SegmentBase input. [On-Demand stream]
- (NSString *)buildSegmentBasePlaylist:(Stream *)stream {
  DashToHlsIndex *dashIndex = stream.dashIndex;
  uint64_t maxDuration = 0;
  uint64_t timescale = (dashIndex->index_count > 0) ? dashIndex->segments[0].timescale : 90000;
  for (uint64_t count = 0; count < dashIndex->index_count; ++count) {
    if (dashIndex->segments[count].duration > maxDuration) {
      maxDuration = dashIndex->segments[count].duration;
    }
  }
  NSMutableString *playlist = [NSMutableString
      stringWithFormat:kPlaylistVOD, 0, (maxDuration / timescale) + 1];
  [playlist appendString:GetKeyUrl(stream.session)];

  for (uint64_t count = 0; count < dashIndex->index_count; ++count) {
    [playlist appendFormat:stream.isVideo ? kVideoSegmentFormat : kAudioSegmentFormat,
                           ((float)dashIndex->segments[count].duration / (float)timescale),
                           stream.streamIndex,
                           count,
                           NULL];
  }
  [playlist appendString:kPlaylistVODEnd];
  return playlist;
}

// Build playlist based on SegmentBase input. [On-Demand or Live stream]
- (NSString *)buildSegmentTemplatePlaylist:(Stream *)stream {
  NSUInteger currentSegment = 0;
  NSUInteger endSegment = 0;
  NSUInteger segmentBuffer = 3;
  LiveStream *liveStream = stream.liveStream;
  float currentTime = [_streamingDelegate getCurrentTime];

  if (stream.isVideo) {
    currentSegment = _currentVideoSegment;
  } else {
    currentSegment = _currentAudioSegment;
  }
  // Ensure first segment isnt higher than current segment.
  if (currentSegment < liveStream.startNumber) {
    currentSegment = liveStream.startNumber;
  }

  // Set End Segment based on how often the playlist needs to be refreshed.
  if (!liveStream.minimumUpdatePeriod) {
    // Set the amount of segments to retain (default to 3 segments ahead).
    liveStream.minimumUpdatePeriod = liveStream.segmentDuration * segmentBuffer;
  }

  endSegment = (currentTime / liveStream.segmentDuration) + currentSegment +
               segmentBuffer;

  // Check if using duration is known to determine how many segments to create.
  if (stream.mediaPresentationDuration) {
    endSegment =
        (stream.mediaPresentationDuration / liveStream.segmentDuration) +
        liveStream.startNumber;
  }

  // Length to keep segments in HLS Playlist.
  if (liveStream.timeShiftBufferDepth) {
    NSUInteger segmentDiff =
        liveStream.timeShiftBufferDepth / liveStream.segmentDuration;
    if ((endSegment - liveStream.startNumber) > segmentDiff) {
      currentSegment = endSegment - segmentDiff;
    }
  }
  // Determine start segement based on the available time of stream and current
  // time.
  if (liveStream.availabilityStartTime) {
    NSDate *now = [NSDate date];
    NSTimeInterval timeDiff =
        [now timeIntervalSinceDate:liveStream.availabilityStartTime];
    endSegment = timeDiff / liveStream.segmentDuration + liveStream.startNumber;
    currentSegment = endSegment - currentSegment;
    if (liveStream.timeShiftBufferDepth) {
      int segmentShift =
          (liveStream.timeShiftBufferDepth / liveStream.segmentDuration);
      currentSegment = currentSegment - segmentShift;
    }
  }

  // Create Playlist by looping through segment list.
  NSMutableString *playlist = nil;
  playlist = [NSMutableString
      stringWithFormat:kDynamicPlaylistHeader, (int)currentSegment,
                       (int)liveStream.segmentDuration + 1];
  [playlist appendString:GetKeyUrl(stream.session)];
  for (uint64_t count = currentSegment; count < endSegment; ++count) {
    [playlist
        appendFormat:stream.isVideo ? kVideoSegmentFormat : kAudioSegmentFormat,
                     (float)liveStream.segmentDuration, stream.streamIndex,
                     count, NULL];
  }
  // Known length of stream is known. End Playlist.
  if (stream.mediaPresentationDuration) {
    [playlist appendString:kPlaylistVODEnd];
  } else {
    [playlist appendString:kDiscontinuity];
    stream.isLive = YES;
  }
  return playlist;
}

// Creates the TS playlist with segments and durations.
- (NSData *)buildChildPlaylist:(Stream *)stream {
  if (stream.dashMediaType == SEGMENT_BASE) {
    return [[self buildSegmentBasePlaylist:stream] dataUsingEncoding:NSUTF8StringEncoding];
  }
  if (stream.dashMediaType == SEGMENT_TEMPLATE_DURATION) {
    return [[self buildSegmentTemplatePlaylist:stream] dataUsingEncoding:NSUTF8StringEncoding];
  }
  return nil;
}

// Downloads requested byte range for the stream.
// Called on _streamingQ.
- (void)loadStream:(Stream *)stream {
  // Check if Stream is Segment Base and does not have a duration, then Live
  // stream.
  if (stream.dashMediaType != SEGMENT_BASE && !stream.mediaPresentationDuration) {
    stream.isLive = YES;
  }
  NSURL *requestURL = stream.sourceURL;
  // Check if Dash Type is something other than Segment Base.
  if (stream.dashMediaType != SEGMENT_BASE) {
    // Determine if stream has Init segment that contains stream data.
    NSURL *initURL = stream.liveStream.initializationURL;
    if (initURL) {
      requestURL = initURL;
    } else {
      NSString *URLString = [stream.sourceURL absoluteString];
      NSString *number = [NSString stringWithFormat:@"%tu", stream.liveStream.startNumber];
      URLString =
          [URLString stringByReplacingOccurrencesOfString:kLiveRepresentationID
                                               withString:stream.liveStream.representationId];
      URLString = [URLString stringByReplacingOccurrencesOfString:kLiveNumber withString:number];
      requestURL = [[NSURL alloc] initWithString:URLString];
    }
    NSData *data =
        [Downloader downloadPartialData:requestURL initialRange:stream.initialRange completion:nil];
    if (data == nil) {
      NSLog(@"\n::ERROR::Failed to load data: %@", requestURL);
      return;
    }
    if (![stream initialize:data]) {
      NSLog(@"\n::ERROR::Failed to initialize stream: %@", requestURL);
      return;
    }
    stream.m3u8 = [self buildChildPlaylist:stream];
  } else {
    [Downloader
        downloadPartialData:requestURL
               initialRange:stream.initialRange
                 completion:^(NSData *data, NSURLResponse *response, NSError *connectionError) {
                   dispatch_async(_streamingQ, ^{
                     if (!data) {
                       NSLog(@"\n::ERROR::Did not download %@", connectionError);
                     }
                     if (![stream initialize:data]) {
                       return;
                     }
                     stream.m3u8 = [self buildChildPlaylist:stream];
                   });
                 }];
  }
}

// Validates that all streams are complete and playback is ready.
- (void)streamReady:(Stream *)stream {
  stream.done = YES;
  --_preloadCount;
  if (_preloadCount == 0 && _streamingQ) {
    // streamReady is called in the middle of processing a stream.
    // Ensure all streams have been processed before sending to video player.
    dispatch_async(_streamingQ, ^() {
      dispatch_async(dispatch_get_main_queue(), ^() {
        [self startVideoPlayer];
      });
    });
  }
}

// Creates TS segments based on downloading a specific byte range.
- (NSData *)tsDataForIndex:(int)index segment:(int)segment {
  if ((int)_streams.count <= index) {
    return nil;
  }
  Stream *stream = _streams[index];

  NSURL *requestURL = nil;
  NSData *data = nil;
  if (stream.dashMediaType != SEGMENT_BASE) {
    NSString *urlString = [stream.sourceURL absoluteString];

    // Swap Placeholder $RepresentationID$ with variable stored in stream.
    urlString = [urlString stringByReplacingOccurrencesOfString:kLiveRepresentationID
                                                     withString:stream.liveStream.representationId];
    // Check if there is numbered padding to $Number variable.
    if ([urlString containsString:kNumberPlaceholder]) {
      NSRegularExpression *numberRegex =
          [[NSRegularExpression alloc] initWithPattern:kNumberRegexPattern options:0 error:nil];
      urlString = [urlString
                   stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
      NSTextCheckingResult *numberMatch =
          [numberRegex firstMatchInString:urlString
                                  options:0
                                    range:NSMakeRange(0, urlString.length)];
      if (numberMatch) {
        NSRange formatRange = [numberMatch rangeAtIndex:1];

        NSString *segmentFormat = formatRange.location != NSNotFound
                                      ? [urlString substringWithRange:formatRange]
                                      : kNumberFormat;
        NSString *segmentString = [NSString stringWithFormat:segmentFormat, segment];
        urlString = [urlString stringByReplacingCharactersInRange:numberMatch.range
                                                       withString:segmentString];
      }
    }
    requestURL = [[NSURL alloc] initWithString:urlString];
    data =
        [Downloader downloadPartialData:requestURL initialRange:stream.initialRange completion:nil];
  } else {
    requestURL = stream.sourceURL;
    if (!stream.dashIndex) {
      NSLog(@"\n::ERROR::DashIndex is Empty");
      return nil;
    }
    if ((int)stream.dashIndex->index_count <= segment) {
      NSLog(@"\n::ERROR::Segment out of range %@/%@", @(segment), @(stream.dashIndex->index_count));
      return nil;
    }
    const auto &segments = stream.dashIndex->segments[segment];
    NSDictionary *initialRange = @{
      @"startRange" : @(segments.location),
      @"length" : @(segments.length)
    };
    data = [Downloader downloadPartialData:requestURL
                              initialRange:initialRange
                                completion:nil];
  }
  if ([data length] == 0) {
    NSLog(@"Could not initialize session url=\n%@", requestURL);
    return nil;
  }
  NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if ([responseString containsString:@"NoSuchKey"]) {
    NSLog(@"File Not Found on Google Storage: %@", requestURL);
    return nil;
  }

  const uint8_t *hlsSegment;
  size_t hlsSize;
  DashToHlsStatus status = Udt_ConvertDash(
      stream.session, segment, (const uint8_t *)[data bytes], [data length], &hlsSegment, &hlsSize);
  if (kDashToHlsStatus_OK == status) {
    NSData *response_data = [NSData dataWithBytes:hlsSegment length:hlsSize];
    Udt_ReleaseHlsSegment(stream.session, segment);
    if (stream.isVideo) {
      _currentVideoSegment = segment;
    } else {
      _currentAudioSegment = segment;
    }
    return response_data;
  }
  return nil;
}

// Intercept HTTP response for M3U8 and TS files and respond with created data.
- (NSObject<HTTPResponse> *)responseForMethod:(NSString *)method
                                         path:(NSString *)path
                                   connection:(HTTPConnection *)connection {
  NSData *response_data = nil;
  // Check for incoming filename and return appropriate data.
  if ([path.lastPathComponent isEqualToString:kLocalPlaylist]) {
    NSLog(@"\n::INFO::Requesting: %@", path);
    // kDashPlaylist is pre-assigned name in ViewController to ensure variant
    // playlist creation.
    response_data = [_variantPlaylist dataUsingEncoding:NSUTF8StringEncoding];
  } else if ([path.pathExtension isEqualToString:@"m3u8"]) {
    NSLog(@"\n::INFO::Requesting: %@", path);
    // Catches children playlist requests and provides the appropriate data in
    // place of m3u8.
    NSScanner *scanner = [NSScanner scannerWithString:path];
    int index = 0;
    if ([scanner scanString:@"/" intoString:NULL] && [scanner scanInt:&index]) {
      Stream *stream = _streams[index];
      if (!stream.m3u8) {
        NSLog(@"ERROR");
        return nil;
      }
      if (stream.isLive) {
        // Loop through all streams to ensure all playlists are updated in the event of rate change.
        for (Stream *stream in _streams) {
          stream.m3u8 = [self buildChildPlaylist:stream];
        }
      }
      response_data = stream.m3u8;
    }
  } else if ([path.pathExtension isEqualToString:@"ts"]) {
    NSLog(@"\n::INFO::Requesting: %@", path);
    // Handles individual TS segment requests by transmuxing the source MP4.
    NSScanner *scanner = [NSScanner scannerWithString:path];
    int index = 0;
    int segment = 0;
    if ([scanner scanString:@"/" intoString:NULL] && [scanner scanInt:&index] &&
        [scanner scanString:@"-" intoString:NULL] && [scanner scanInt:&segment] &&
        [scanner scanString:@".ts" intoString:NULL]) {
      response_data = [self tsDataForIndex:index segment:segment];
    }
  }
  if (response_data) {
    return [[HTTPDataResponse alloc] initWithData:response_data];
  }
  return nil;
}

@end
