#import "MpdParser.h"
#import "Stream.h"
#import "Streaming.h"

static NSString *kMultiAudioMpdUrl = @"https://shaka-player-demo.appspot.com/assets/angel_one.mpd";

static NSString *kClearContentMpdUrl =
    @"http://yt-dash-mse-test.commondatastorage.googleapis.com/media/oops-20120802-manifest.mpd";

static NSString *kEncContentMpdUrl = @"http://storage.googleapis.com/wvmedia/cenc/tears.mpd";

static NSString *const kSplitBaseMpdData =
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

static NSString *const kSubParamOverrideMpdData =
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
              @"bandwidth=\"254027\" mimeType=\"video/m4a\">"
            @"<BaseURL>http://google.com/new/video/path/video.mp4</BaseURL>"
            @"<SegmentBase indexRange=\"1555-1766\">"
              @"<Initialization range=\"0-1554\"/>"
            @"</SegmentBase>"
          @"</Representation>"
        @"</AdaptationSet>"
      @"</Period>"
    @"</MPD>";

static NSString *const kInvalidParamsMpdData =
    @"<MPD xmlns=\"urn:mpeg:DASH:schema:MPD:2011\" mediaPresentationDuration=\"PT0H4M2.93S\" "
        @"minBufferTime=\"PT1.5S\" profiles=\"urn:mpeg:dash:profile:isoff-on-demand:2011\"  "
        @"type=\"static\">"
      @"<Period duration=\"PT0H4M2.93S\" start=\"PT0S\">"
          @"<AdaptationSet>"
            @"<ContentComponent contentType=\"video\" id=\"1\" />"
            @"<Representation bandwidth=\"4190760\" codecs=\"  \" height=\"1080\" "
                @"id=\"1\" mimeType=\"video/mp4\" width=\"1920\">"
              @"<BaseURL>oops-20120802-89.mp4</BaseURL>"
              @"<SegmentBase indexRange=\"0-673\">"
                @"<Initialization range=\"674-1293\" />"
              @"</SegmentBase>"
            @"</Representation>"
          @"</AdaptationSet>"
          @"<AdaptationSet>"
            @"<ContentComponent contentType=\"audio\" id=\"2\" />"
            @"<Representation bandwidth=\"127236\" codecs=\"mp4a.40.02\" id=\"6\" "
                @"mimeType=\"audio/mp4\" numChannels=\"2\" sampleRate=\"44100\">"
              @"<BaseURL>oops-20120802-8c.mp4</BaseURL>"
              @"<SegmentBase indexRange=\"592-923\">"
              @"</SegmentBase>"
            @"</Representation>"
            @"<Representation bandwidth=\"127236\" codecs=\"mp3\" id=\"7\" "
              @"mimeType=\"audio/mp4\" numChannels=\"2\" sampleRate=\"44100\">"
              @"<BaseURL>oops-20120802-8c.mp4</BaseURL>"
              @"<SegmentBase>"
                @"<Initialization range=\"674-1293\" />"
              @"</SegmentBase>"
            @"</Representation>"

          @"</AdaptationSet>"
      @"</Period>"
    @"</MPD>";


@interface MpdParserTest : XCTestCase {
  Streaming *_streaming;
}
@end

@implementation MpdParserTest

- (void)setUp {
  _streaming = [[Streaming alloc] initWithAirplay:NO];
}

// Validate Parents attributes in Adaptation set are propogated down.
- (void)testDownwardPropagation {
  _streaming.streams = [self parseStaticMPD:kSplitBaseMpdData urlString:kEncContentMpdUrl];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqualObjects(stream.mimeType, @"video/mp4");
    }
  }
}

// Validate lower attributes take precendence over higher ones.
- (void)testOverwritingAttributes {
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData urlString:kEncContentMpdUrl];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqualObjects(stream.mimeType, @"video/m4a");
    }
  }
}


// Validate Index Range is being parsed and set correctly.
- (void)testIndexRange {
  _streaming.streams = [self parseStaticMPD:kSplitBaseMpdData urlString:kEncContentMpdUrl];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqual([[stream.initialRange valueForKey:@"length"] intValue], 1767);
    }
  }
}

// Validate Failure when InitRange is missing or invalid.
- (void)testInvalidIndexRange {
  _streaming.streams = [self parseStaticMPD:kInvalidParamsMpdData urlString:kClearContentMpdUrl];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      // Initalization Range is incorrect. Start range is equal/higher to end.
      XCTAssertNil(stream.initialRange);
      // Codec is missing from the Representation for the stream.
      XCTAssertNil(stream.codecs);
    } else {
      if ([stream.codecs isEqualToString:@"mp3"]) {
        // Index Range is missing from SegmentBase.
        XCTAssertNil(stream.initialRange);
      } else {
        // Initalization Range is missing.
        XCTAssertNil(stream.initialRange);
      }
    }
  }
}

// Validate having a Base URL that is different than the MPD source.
- (void)testSplitUrl {
  _streaming.streams = [self parseStaticMPD:kSplitBaseMpdData urlString:kEncContentMpdUrl];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqualObjects([stream.sourceUrl absoluteString],
                            @"http://google.com/test/content/video.mp4");
    } else {
      XCTAssertEqualObjects([stream.sourceUrl absoluteString],
                            @"http://google.com/test/content/audio.mp4");
    }
  }
}

// Validate parsing of Manifest Duration
- (void)testMediaDuration {
  MpdParser *parser = [[MpdParser alloc] init];
  XCTAssertLessThan([parser convertDurationToSeconds:@"P1M1DT1H2M3.00S"],
                    ((60 * 60 * 24 * 30) + 90123 + 1));
  XCTAssertGreaterThan([parser convertDurationToSeconds:@"P1M1DT1H2M3.00S"],
                       ((60 * 60 * 24 * 28) + 90123 - 1));
  XCTAssertEqual([parser convertDurationToSeconds:@"P1DT0H10M0.00S"],
                 (24 * 60 *60) + (10 * 60));
  XCTAssertEqual([parser convertDurationToSeconds:@"PT0H10M0.00S"], (10 * 60));
  XCTAssertEqual([parser convertDurationToSeconds:@"PT0H10M"], (10 * 60));
  XCTAssertEqual([parser convertDurationToSeconds:@"PT1S"], 1);
  XCTAssertEqual([parser convertDurationToSeconds:@"PT1.1S"], 1);
  XCTAssertEqual([parser convertDurationToSeconds:@"PT0.1S"], 0);
  XCTAssertEqual([parser convertDurationToSeconds:@"PT.1S"], 0);
}

// Validate total streams are accounted for and the indexValue increments correctly
- (void)testStreamCount {
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData urlString:kClearContentMpdUrl];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqual(stream.streamIndex, 1);
    }
  }
  XCTAssertEqual(_streaming.streams.count, 2);
}


// Validate changing scheme from HTTP to HTTPS based on MPD URL.
- (void)testUrlScheme {
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData urlString:kMultiAudioMpdUrl];
  for (Stream *stream in _streaming.streams) {
    NSLog(@"%@", stream);
    if (stream.isVideo) {
      // Representation Scheme should stay HTTP.
      XCTAssertEqualObjects(stream.sourceUrl.scheme, @"http");
    } else {
      // No scheme present will default to MPD Scheme.
      XCTAssertEqualObjects(stream.sourceUrl.scheme, @"https");
    }
  }

}

// Validate Parents attributes for BaseURL are propogated down correctly.
- (void)testRepresentationBaseUrl {
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData urlString:kEncContentMpdUrl];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      // Validate this URL is same as Representation BaseURL.
      XCTAssertEqualObjects([stream.sourceUrl absoluteString],
                            @"http://google.com/new/video/path/video.mp4");
    } else {
      // Validate this URL uses Global BaseURL.
      XCTAssertEqualObjects([stream.sourceUrl absoluteString],
                            @"http://google.com/test/content/audio.mp4");
    }
  }
}

# pragma mark - Private Methods

- (NSMutableArray *)parseStaticMPD:(NSString *)mpd urlString:(NSString *)urlString {
  NSURL *mpdUrl = [[NSURL alloc] initWithString:urlString];
  NSData *mockData = [mpd dataUsingEncoding:NSUTF8StringEncoding];
  return [MpdParser parseMpdWithStreaming:_streaming mpdData:mockData baseUrl:mpdUrl];
}

- (NSMutableArray *)parseMPDUrl:(NSString *)mpdUrl {
  NSURL *url = [[NSURL alloc] initWithString:mpdUrl];
  NSError *error = nil;
  NSData *data = [NSData dataWithContentsOfURL:url
                                       options:NSDataReadingUncached
                                         error:&error];
  if (error) {
    NSLog(@"Error reading %@ %@", mpdUrl, error);
    return nil;
  } else {
    return [MpdParser parseMpdWithStreaming:_streaming mpdData:data baseUrl:url];
  }
}

@end
