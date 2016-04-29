#import "Downloader.h"
#import "Stream.h"
#import "Streaming.h"

static NSString *const kManifestURL_eDash = @"http://storage.googleapis.com/wvmedia/cenc/tears.mpd";
static NSString *const kManifestURL_Clear =
    @"http://yt-dash-mse-test.commondatastorage.googleapis.com/media/oops-20120802-manifest.mpd";

static NSString *const kBasicVODMPD =
    @"<MPD type=\"static\">"
      @"<Period>"
        @"<AdaptationSet mimeType=\"audio/mp4\">"
          @"<Representation id=\"148\" codecs=\"mp4a.40.2\" audioSamplingRate=\"22050\" "
              @"bandwidth=\"49993\">"
            @"<BaseURL>https://localhost</BaseURL>"
            @"<SegmentBase indexRange=\"1555-1766\">"
              @"<Initialization range=\"0-1554\"/>"
            @"</SegmentBase>"
          @"</Representation>"
        @"</AdaptationSet>"
        @"<AdaptationSet mimeType=\"video/mp4\">"
          @"<Representation id=\"142\" codecs=\"avc1.4d4015\" width=\"426\" height=\"240\" "
              @"bandwidth=\"254027\">"
            @"<BaseURL>https://localhost</BaseURL>"
            @"<SegmentBase indexRange=\"1555-1766\">"
              @"<Initialization range=\"0-1554\"/>"
            @"</SegmentBase>"
          @"</Representation>"
        @"</AdaptationSet>"
      @"</Period>"
    @"</MPD>";

@interface StreamingTest : XCTestCase {
  Streaming *_streaming;
}
@end

@implementation StreamingTest

- (void)setUp {
  _streaming = [[Streaming alloc] initWithAirplay:NO];
}

- (void)testManifestUrl_Clear {
  [self convertMPDtoHLS:kManifestURL_Clear];
}

- (void)testManifestUrl_eDash {
  [self convertMPDtoHLS:kManifestURL_eDash];
}

# pragma mark private methods

// Creates an output of an HLS Playlist from a MPD.
- (void)convertMPDtoHLS:(NSString *)mpdURL {
  _streaming.mpdURL = [[NSURL alloc] initWithString:mpdURL];
  [_streaming processMpd:_streaming.mpdURL];
  Stream *stream = nil;
  for (stream in _streaming.streams) {
    [Downloader downloadPartialData:stream.sourceUrl
                       initialRange:stream.initialRange
                         completion:^(NSData *data,
                                      NSURLResponse *response,
                                      NSError *connectionError) {
                           XCTAssertFalse(data);
                           XCTAssertTrue([stream initialize:data]);
                           NSString *m3u8 =
                               [[NSString alloc] initWithData:[_streaming buildChildPlaylist:stream]
                                                     encoding:NSUTF8StringEncoding];
                           NSString *endList = [m3u8 substringFromIndex:[m3u8 length] - 14];
                           // Verify the End of the list is present and completed.
                           XCTAssertEqualObjects(endList, @"#EXT-X-ENDLIST", @"Bad HLS Playlist");
                         }];
  }
}

@end

