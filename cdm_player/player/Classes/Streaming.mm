// Copyright 2015 Google Inc. All rights reserved.

#import "Streaming.h"

#import <arpa/inet.h>
#import <ifaddrs.h>
#import <string.h>

#import <Responses/HTTPDataResponse.h>

#import "AppDelegate.h"
#import "DashToHlsApiAVFramework.h"
#import "DetailViewController.h"
#import "Downloader.h"
#import "HTTPResponse.h"
#import "LicenseManager.h"
#import "LocalWebServer.h"
#import "MpdParser.h"
#import "Stream.h"
#import "UDTApi.h"

NSString *kStreamingReadyNotification = @"StreamingReadyNotificaiton";

@implementation Streaming {
  LocalWebServer *_localWebServer;
  NSUInteger _currentAudioSegment;
  NSUInteger _currentVideoSegment;
}

static int kHttpPort = 8080;
static NSString *const kLocalPlaylist = @"dash2hls.m3u8";
static NSString *const kLocalHost = @"localhost";

static NSString *kAudioPlaylistFormat =
    @"#EXT-X-MEDIA:URI=\"%d.m3u8\",TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"audio%d\","
    @"DEFAULT=%@,AUTOSELECT=YES\n";
static NSString *kAudioSegmentFormat = @"#EXTINF:%0.06f,\n%d-%d.ts\n";

static NSString *const kDynamicPlaylistHeader =
    @"#EXTM3U\n"
    @"#EXT-X-VERSION:3\n"
    @"#EXT-X-MEDIA-SEQUENCE:%d\n"
    @"#EXT-X-TARGETDURATION:%d\n";

static NSString *const kPlaylistVOD =
@"#EXTM3U\n"
@"#EXT-X-VERSION:3\n"
@"#EXT-X-MEDIA-SEQUENCE:%d\n"
@"#EXT-X-TARGETDURATION:%llu\n";

static NSString *const kDiscontinuity = @"#EXT-X-DISCONTINUITY\n";
static NSString *const kPlaylistVODEnd = @"#EXT-X-ENDLIST";

static NSString *kVariantPlaylist = @"#EXTM3U\n#EXT-X-VERSION:3\n";

static NSString *kVideoPlaylistFormat =
@"#EXT-X-STREAM-INF:BANDWIDTH=%lu,CODECS=\"%@\",RESOLUTION=%.0lux%.0lu,AUDIO=\"audio\""
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
    _httpPort = kHttpPort;
    [_localWebServer start:&error];
    _streamingQ = dispatch_queue_create("Streaming", NULL);
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
          address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)
                                                              temp_addr->ifa_addr)->sin_addr)];
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
- (void)processMpd:(NSURL *)mpdUrl {
  NSLog(@"\n::INFO::Processing: %@", mpdUrl);
  dispatch_async(_streamingQ, ^{
    NSError *error = nil;
    NSData *mpdData = [NSData dataWithContentsOfURL:mpdUrl
                                            options:NSDataReadingUncached
                                              error:&error];
    if (error) {
      NSLog(@"Error reading %@ %@", mpdUrl, error);
    } else {
      _streams = [MpdParser parseMpdWithStreaming:self
                                          mpdData:mpdData
                                          baseUrl:mpdUrl];
      _preloadCount = _streams.count;
      _variantPlaylist = [self buildVariantPlaylist:_streams];
      [_streams enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [self loadStream:obj];
      }];
    }
  });
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
                                                    stream.bandwidth, stream.codecs, stream.width,
                                                    stream.height, stream.streamIndex]];
    } else {
      NSString *langAbbreviation = [[[NSLocale preferredLanguages] firstObject]
                                    substringToIndex:2];
      NSString *langString = [langAbbreviation stringByAppendingString:@"_"];
      if ([[stream.sourceUrl absoluteString] containsString:langString]) {
        defaultAudioString = @"YES";
      }
      playlist = [playlist stringByAppendingString:[NSString stringWithFormat:kAudioPlaylistFormat,
                                                    stream.streamIndex, stream.streamIndex,
                                                    defaultAudioString]];
      defaultAudioString = @"NO";
    }
  }
  return playlist;
}

// Creates the TS playlist with segments and durations.
- (NSData *)buildChildPlaylist:(Stream *)stream {
  NSMutableString *playlist = [[NSMutableString alloc] initWithData:stream.m3u8
                                                           encoding:NSUTF8StringEncoding];
  if (stream.dashMediaType == SEGMENT_BASE) {
    // On Demand Stream
    DashToHlsIndex *dashIndex = stream.dashIndex;
    uint64_t maxDuration = 0;
    uint64_t timescale = (dashIndex->index_count > 0) ? dashIndex->segments[0].timescale:90000;
    for (uint64_t count = 0; count < dashIndex->index_count; ++count) {
      if (dashIndex->segments[count].duration > maxDuration) {
        maxDuration = dashIndex->segments[count].duration;
      }
    }
    playlist = [NSMutableString stringWithFormat:kPlaylistVOD,
                0, (maxDuration/timescale) + 1];
    [playlist appendString:GetKeyUrl(stream.session)];

    for (uint64_t count = 0; count < dashIndex->index_count; ++count) {
      [playlist appendFormat:stream.isVideo ? kVideoSegmentFormat:kAudioSegmentFormat,
       ((float)dashIndex->segments[count].duration / (float)timescale),
       stream.streamIndex, count, NULL];
    }
    [playlist appendString:kPlaylistVODEnd];
  } else { // Non-SegmentBase Template
    NSUInteger currentSegment = 0;
    NSUInteger endSegment = 0;
    NSUInteger segmentBuffer = 3;
    NSUInteger startSegment = stream.liveStream.startNumber;
    float currentTime = [_streamingDelegate getCurrentTime];

    if (stream.isVideo) {
      currentSegment = _currentVideoSegment;
    } else {
      currentSegment = _currentAudioSegment;
    }
    // Ensure first segment isnt higher than current segment.
    if (currentSegment < stream.liveStream.startNumber) {
      currentSegment = stream.liveStream.startNumber;
    }


    // Set End Segment based on how often the playlist needs to be refreshed.
    if (!stream.liveStream.minimumUpdatePeriod) {
      // Set the amount of segments to retain (default to 3 segments ahead).
      stream.liveStream.minimumUpdatePeriod = stream.liveStream.segmentDuration * segmentBuffer;
    }

    endSegment = (currentTime / stream.liveStream.segmentDuration) +
                  stream.liveStream.startNumber + segmentBuffer;

    // Check if using duration is known to determine how many segments to create.
    if (stream.mediaPresentationDuration) {
      endSegment = (stream.mediaPresentationDuration / stream.liveStream.segmentDuration) +
                   stream.liveStream.startNumber;
    }

    // Length to keep segments in HLS Playlist.
    if (stream.liveStream.timeShiftBufferDepth) {
      NSUInteger segmentDiff =
          stream.liveStream.timeShiftBufferDepth / stream.liveStream.segmentDuration;
      if ((endSegment - stream.liveStream.startNumber) > segmentDiff) {
        startSegment = endSegment - segmentDiff;
      }
    }

    playlist = nil;
    playlist = [NSMutableString stringWithFormat:kDynamicPlaylistHeader,
                  (int)startSegment, (int)stream.liveStream.segmentDuration + 1];
    [playlist appendString:GetKeyUrl(stream.session)];
    for (uint64_t count = startSegment; count < endSegment; ++count) {
      [playlist appendFormat:stream.isVideo ? kVideoSegmentFormat:kAudioSegmentFormat,
       (float)stream.liveStream.segmentDuration, stream.streamIndex, count, NULL];
    }
    // Known length of stream is known. End Playlist.
    if (stream.mediaPresentationDuration) {
      [playlist appendString:kPlaylistVODEnd];
    } else {
      [playlist appendString:kDiscontinuity];
      stream.isLive = YES;
    }
  }
  return [playlist dataUsingEncoding:NSUTF8StringEncoding];
}

// Downloads requested byte range for the stream.
// Called on _streamingQ.
- (void)loadStream:(Stream *)stream {
  // Check if Stream is Segment Base and does not have a duration, then Live stream.
  if (stream.dashMediaType != SEGMENT_BASE && !stream.mediaPresentationDuration) {
    stream.isLive = YES;
  }
  NSURL *requestUrl = stream.sourceUrl;
  // Check if Dash Type is something other than Segment Base.
  if (stream.dashMediaType != SEGMENT_BASE) {
    // Determine if stream has Init segment that contains stream data.
    NSURL *initUrl = stream.liveStream.initializationUrl;
    if (initUrl) {
      requestUrl = initUrl;
    } else {
      NSString *urlString = [stream.sourceUrl absoluteString];
      NSString *number = [NSString stringWithFormat:@"%@", @(stream.liveStream.startNumber)];
      urlString =
          [urlString stringByReplacingOccurrencesOfString:kLiveRepresentationID
                                               withString:stream.liveStream.representationId];
      urlString = [urlString stringByReplacingOccurrencesOfString:kLiveNumber
                                                       withString:number];
      requestUrl = [[NSURL alloc] initWithString:urlString];
    }
    NSData *data = [Downloader downloadPartialData:requestUrl
                                            initialRange:stream.initialRange
                                              completion:nil];
    if (![stream initialize:data]) {
      NSLog(@"Failed to initialize stream: %@", requestUrl);
      return;
    }
    stream.m3u8 = [self buildChildPlaylist:stream];
  } else {
    [Downloader downloadPartialData:requestUrl
                       initialRange:stream.initialRange
                         completion:^(NSData *data,
                                      NSURLResponse *response,
                                      NSError *connectionError) {
                           dispatch_async(_streamingQ, ^() {
                             if (!data) {
                               NSLog(@"Did not download %@", connectionError);
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

// Creates TS segments based on downloading a specific byte range.
- (NSData *)tsDataForIndex:(int)index segment:(int)segment {
  Stream *stream = _streams[index];
  NSURL *requestUrl = stream.sourceUrl;
  NSData *data = nil;
  if (stream.dashMediaType != SEGMENT_BASE) {
    NSString *urlString = [stream.sourceUrl absoluteString];
    NSString *segmentString = [NSString stringWithFormat:@"%d", segment];
    urlString = [urlString stringByReplacingOccurrencesOfString:kLiveRepresentationID
                                                     withString:stream.liveStream.representationId];
    urlString = [urlString stringByReplacingOccurrencesOfString:kLiveNumber
                                                     withString:segmentString];


    requestUrl = [[NSURL alloc] initWithString:urlString];
    data = [Downloader downloadPartialData:requestUrl
                                      initialRange:stream.initialRange
                                        completion:nil];

  } else {
    NSNumber *startRange =
        [NSNumber numberWithUnsignedLongLong:stream.dashIndex->segments[segment].location];
    NSNumber *length =
        [NSNumber numberWithUnsignedLongLong:stream.dashIndex->segments[segment].length];
    NSDictionary *initialRange = [[NSDictionary alloc] initWithObjectsAndKeys:startRange,
                                  @"startRange", length, @"length", nil];
    data = [Downloader downloadPartialData:requestUrl
                              initialRange:initialRange
                                completion:nil];

  }
  if (!data) {
    NSLog(@"Could not initialize session url=%@", requestUrl);
    return nil;
  }
  NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if ([responseString containsString:@"NoSuchKey"]) {
    NSLog(@"File Not Found on Google Storage: %@", requestUrl);
    return nil;
  }

  const uint8_t *hlsSegment;
  size_t hlsSize;
  DashToHlsStatus status = Udt_ConvertDash(stream.session,
                                           segment,
                                           (const uint8_t *)[data bytes],
                                           [data length],
                                           &hlsSegment,
                                           &hlsSize);
  if (kDashToHlsStatus_OK == status) {
    NSData  *response_data = [NSData dataWithBytes:hlsSegment length:hlsSize];
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
    // kDashPlaylist is pre-assigned name in ViewController to ensure variant playlist creation.
    response_data = [_variantPlaylist dataUsingEncoding:NSUTF8StringEncoding];
  } else if ([path.pathExtension isEqualToString:@"m3u8"]) {
    NSLog(@"\n::INFO::Requesting: %@", path);
    // Catches children playlist requests and provides the appropriate data in place of m3u8.
    NSScanner *scanner = [NSScanner scannerWithString:path];
    int index = 0;
    if ([scanner scanString:@"/" intoString:NULL] &&
      [scanner scanInt:&index]) {
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
  } else if ([path.pathExtension isEqualToString:@"ts"]){
    NSLog(@"\n::INFO::Requesting: %@", path);
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
  if (response_data) {
    return [[HTTPDataResponse alloc] initWithData:response_data];
  }
  return nil;
}

@end
