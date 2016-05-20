#import "Downloader.h"
#import "LicenseManager.h"
#import "MpdParser.h"
#import "Stream.h"
#import "Streaming.h"

static NSString *const kMpdUrlString = @"http://www.google.com/path/to.mpd";
static NSString *const kEndList = @"#EXT-X-ENDLIST";

static NSString *const kVideoMpd =
    @"<MPD type=\"static\">"
      @"<Period>"
        @"<AdaptationSet id=\"0\" contentType=\"video\" width=\"854\" height=\"480\" "
            @"frameRate=\"90000/3003\" subsegmentAlignment=\"true\" par=\"16:9\">"
          @"<Representation id=\"0\" bandwidth=\"2243787\" codecs=\"avc1.42c01f\" "
              @"mimeType=\"video/mp4\" sar=\"1:1\">"
            @"<BaseURL>video.mp4</BaseURL>"
            @"<SegmentBase indexRange=\"804-847\" timescale=\"90000\">"
            @"<Initialization range=\"0-803\"/>"
            @"</SegmentBase>"
          @"</Representation>"
        @"</AdaptationSet>"
      @"</Period>"
    @"</MPD>";

@interface StreamTest : XCTestCase
@end

@implementation StreamTest {
  Streaming *_streaming;
}

- (void) setUp {
  _streaming = [[Streaming alloc] initWithAirplay:NO];
}

- (void)testStreamInit {
  Stream *stream = [[Stream alloc] initWithStreaming:_streaming];
  NSString *thePath = [[NSBundle mainBundle] pathForResource:@"video" ofType:@"mp4"];
  NSData *initData = [[NSData alloc] initWithContentsOfFile:thePath];
  XCTAssertTrue([stream initialize:initData]);
}

- (void)testStreamInitWithNilStreaming {
  _streaming = nil;
  Stream *stream = [[Stream alloc] initWithStreaming:_streaming];
  NSString *thePath = [[NSBundle mainBundle] pathForResource:@"video" ofType:@"mp4"];
  NSData *initData = [[NSData alloc] initWithContentsOfFile:thePath];
  XCTAssertTrue([stream initialize:initData]);
}

- (void)testStreamDescription {
  Stream *stream = [[Stream alloc] initWithStreaming:_streaming];
  stream.sourceUrl = [[NSURL alloc] initWithString:kMpdUrlString];
  NSArray *streamString = [stream.description componentsSeparatedByString: @"="];
  NSString *streamUrl = [streamString objectAtIndex:4];
  XCTAssertEqualObjects(streamUrl, kMpdUrlString);
}

- (void)testStreamProperties {
  NSURL *mpdUrl = [NSURL URLWithString:kMpdUrlString];
  NSString *thePath = [[NSBundle mainBundle] pathForResource:@"video" ofType:@"mp4"];
  NSData *initData = [[NSData alloc] initWithContentsOfFile:thePath];

  NSData *mpdData = [kVideoMpd dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableArray *streams = [MpdParser parseMpdWithStreaming:_streaming
                                                     mpdData:mpdData
                                                     baseUrl:mpdUrl];
  NSUInteger *preloadCount = streams.count;
  NSString *variantPlaylist = [_streaming buildVariantPlaylist:streams];
  [streams enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    Stream *stream = obj;
    XCTAssertNotNil(stream);
    XCTAssertTrue([stream initialize:initData]);
    XCTAssertNotNil([NSNumber numberWithUnsignedInteger:stream.dashIndex->index_count]);
    stream.m3u8 = [_streaming buildChildPlaylist:stream];
    NSString *m3u8 = [[NSString alloc] initWithData:stream.m3u8 encoding:NSUTF8StringEncoding];
    NSString *lastLine = [m3u8 substringFromIndex:[m3u8 length] - [kEndList length]];
    XCTAssertEqualObjects(lastLine, kEndList);
  }];
}

@end

