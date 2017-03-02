#import "Downloader.h"
#import "Stream.h"
#import "Streaming.h"
#import "Logging.h"

static NSString *const kManifestURL_eDash = @"tears_cenc_small";
static NSString *const kManifestURL_Clear = @"tears_clear_small";
static NSInteger const kExpectedStreams = 2;

extern float kPartialDownloadTimeout;

@interface StreamingTest : XCTestCase {
  DDTTYLogger *_logger;
  Streaming *_streaming;
}
@end

@implementation StreamingTest

- (void)setUp {
  _logger = [DDTTYLogger sharedInstance];
  [DDLog addLogger:_logger];
  _streaming = [[Streaming alloc] initWithAirplay:NO licenseServerURL:nil];
}

- (void)tearDown {
  [DDLog removeLogger:_logger];
}

- (void)testManifestURL_Clear {
  [self convertMPDtoHLS:kManifestURL_Clear expectedStreams:kExpectedStreams];
}

- (void)testManifestURL_eDash {
  [self convertMPDtoHLS:kManifestURL_eDash expectedStreams:kExpectedStreams];
}

#pragma mark private methods

// Creates an output of an HLS Playlist from a MPD.
- (void)convertMPDtoHLS:(NSString *)mpdURL expectedStreams:(int)expectedStreams {
  __weak XCTestExpectation *streamExpectation =
      [self expectationWithDescription:@"Stream completion called"];

  // use the custom callback version of processMpd, so that the downloader doesn't get involved
  _streaming.mpdURL = [[NSBundle mainBundle] URLForResource:mpdURL withExtension:@"mpd"];
  [_streaming processMpd:_streaming.mpdURL withCompletion:^(NSError *error) {
    [streamExpectation fulfill];
    XCTAssertNil(error, @"MPD failed to load with error %@", error);
  }];

  // wait for the MPD to finish loading
  [self waitForExpectationsWithTimeout:0.5 handler:nil];  // hopefully 0.5s is long enough

  // because expectations are blocking, I can just put the rest down here
  if (_streaming.streams) {
    NSArray *streams = _streaming.streams;
    XCTAssertEqual(streams.count, expectedStreams);
    if (streams.count == expectedStreams) {
      [self downloadStreams:streams];
    }
  }
}

// downloads the streams, and test to see if the contents are as expected
- (void)downloadStreams:(NSArray<Stream *> *)streams {
  for (Stream *stream in streams) {
    CDMLogInfo(@"Stream %@", stream);

    NSData *data = [NSData dataWithContentsOfURL:stream.sourceURL];

    XCTAssertNotNil(data);

    if (data) {
      BOOL initialized = [stream initialize:data];
      XCTAssertTrue(initialized);

      if (initialized) {
        NSString *m3u8 = [[NSString alloc] initWithData:[_streaming buildChildPlaylist:stream]
                                               encoding:NSUTF8StringEncoding];
        NSString *endList = [m3u8 substringFromIndex:[m3u8 length] - 14];
        // Verify the End of the list is present and completed.
        XCTAssertEqualObjects(endList, @"#EXT-X-ENDLIST", @"Bad HLS Playlist");
      }
    }
  }
}

@end
