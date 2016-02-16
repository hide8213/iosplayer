#import "Downloader.h"
#import "LicenseManager.h"
#import "MpdParser.h"
#import "Stream.h"
#import "Streaming.h"

static NSString *const kMpdDataString =
    @"<MPD type=\"static\">"
      @"<BaseURL>//google.com/test/content/</BaseURL>"
      @"<Period>"
        @"<AdaptationSet mimeType=\"audio/mp4\">"
          @"<Representation id=\"148\" codecs=\"mp4a.40.2\" audioSamplingRate=\"22050\" "
              @"bandwidth=\"49993\">"
            @"<BaseURL>audio.mp4</BaseURL>"
            @"<SegmentBase indexRange=\"1555-1766\">"
              @"<Initialization range=\"0-1554\"/>"
            @"</SegmentBase>"
          @"</Representation>"
        @"</AdaptationSet>"
        @"<AdaptationSet mimeType=\"video/mp4\">"
          @"<Representation id=\"142\" codecs=\"avc1.4d4015\" width=\"426\" height=\"240\" "
              @"bandwidth=\"254027\">"
            @"<BaseURL>video.mp4</BaseURL>"
            @"<SegmentBase indexRange=\"1555-1766\">"
              @"<Initialization range=\"0-1554\"/>"
            @"</SegmentBase>"
          @"</Representation>"
        @"</AdaptationSet>"
      @"</Period>"
    @"</MPD>";

static NSString *const kMpdUrlString = @"http://www.google.com/path/to.mpd";
static NSString *const kEndList = @"#EXT-X-ENDLIST";


@interface StreamTest : XCTestCase
@end

@implementation StreamTest {
  NSData *_mpdData;
  NSData *_streamData;
  NSArray *_streams;
  Streaming *_streaming;
}

- (void)setUp {
  NSURL *mpdUrl = [NSURL URLWithString:kMpdUrlString];
  _streaming = [[Streaming alloc] initWithAirplay:NO];
  _streaming.mpdURL = [[NSURL alloc] initWithString:kMpdUrlString];
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  _mpdData = [kMpdDataString dataUsingEncoding:NSUTF8StringEncoding];
  _streamData = [[NSData alloc] initWithContentsOfFile:[bundle pathForResource:@"videoOnly"
                                                                        ofType:@"mp4"]];
  _streams = [[MpdParser alloc] initWithStreaming:_streaming
                                          mpdData:_mpdData
                                          baseUrl:mpdUrl].streams;
}

- (void)testStreamSession {
  XCTAssertGreaterThan(_streams.count, 0);
  [_streams enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    Stream *stream = obj;
    XCTAssertNotNil(stream);
    XCTAssertTrue([stream initialize:_streamData]);
    stream.m3u8 = [_streaming buildChildPlaylist:stream];
    NSString *m3u8 = [[NSString alloc] initWithData:stream.m3u8 encoding:NSUTF8StringEncoding];
    NSString *lastLine = [m3u8 substringFromIndex:[m3u8 length] - [kEndList length]];
    XCTAssertEqualObjects(lastLine, kEndList);
  }];
}

@end

