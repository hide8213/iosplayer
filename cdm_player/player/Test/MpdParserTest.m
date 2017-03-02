#import "MpdParser.h"
#import "Streaming.h"
#import "Logging.h"

static NSString *kMultiAudioMpdURL =
    @"https://shaka-player-demo.appspot.com/assets/angel_one.mpd";

static NSString *kClearContentMpdURL =
    @"http://yt-dash-mse-test.commondatastorage.googleapis.com/media/"
    @"oops-20120802-manifest.mpd";

static NSString *kEncContentMpdURL =
    @"http://storage.googleapis.com/wvmedia/cenc/tears.mpd";

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
        @"<AdaptationSet mimeType=\"video/junk\">"
          @"<Representation id=\"142\" codecs=\"avc1.4d4015\" width=\"426\" height=\"240\" "
              @"bandwidth=\"254027\" mimeType=\"video/mp4\">"
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
          @"<ContentProtection value=\"Widevine\" "
            @"schemeIdUri=\"urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed\">"
            @"<cenc:pssh>AAAANHBzc2gAAAAA7e+LqXnWSs6jyCfc1R0h7QAAABQIARIQnrQFDeRLSAKTLifXUIPiZg=="
                                                                                     @"</cenc:pssh>"
          @"</ContentProtection>"
          @"<ContentComponent contentType=\"video\" id=\"1\" />"
            @"<Representation bandwidth=\"4190760\" codecs=\"avc1\" height=\"1080\" "
                @"id=\"1\" mimeType=\"video/mp4\" width=\"1920\">"
              @"<BaseURL>oops-20120802-89.mp4</BaseURL>"
                @"<SegmentBase indexRange=\"1555-1766\">"
                @"<Initialization range=\"0-1554\"/>"
              @"</SegmentBase>"
            @"</Representation>"
            @"<Representation bandwidth=\"4190760\" codecs=\"avc1\" height=\"1080\" "
                @"id=\"2\" mimeType=\"application/mp4\" width=\"1920\">"
              @"<BaseURL>oops-20120802-89.mp4</BaseURL>"
                @"<SegmentBase indexRange=\"0-1554\">"
                @"<Initialization range=\"1555-1766\"/>"
              @"</SegmentBase>"
            @"</Representation>"
            @"<Representation bandwidth=\"4190760\" codecs=\"hev1.2.4.L63.90\" height=\"1080\" "
                @"id=\"3\" mimeType=\"video/mp4\" width=\"1920\">"
              @"<BaseURL>oops-20120802-89.mp4</BaseURL>"
                @"<SegmentBase indexRange=\"1555-1766\">"
                @"<Initialization range=\"0-1554\"/>"
              @"</SegmentBase>"
            @"</Representation>"
          @"</AdaptationSet>"
          @"<AdaptationSet>"
            @"<ContentProtection value=\"Widevine\" "
                @"schemeIdUri=\"urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed\">"
              @"<cenc:pssh>AAAANHBzc2gAAAAA7e+LqXnWSs6j"
              @"\n"
              @"AAAANHBzc2gAAAAA7e+LqXnWSs6j</cenc:pssh>"
            @"</ContentProtection>"
            @"<ContentComponent contentType=\"audio\" id=\"4\" />"
            @"<Representation bandwidth=\"127236\" codecs=\"mp4a.40.02\" id=\"6\" "
                @"mimeType=\"audio/mp4\" numChannels=\"2\" sampleRate=\"44100\">"
              @"<BaseURL>oops-20120802-8c.mp4</BaseURL>"
              @"<SegmentBase indexRange=\"592-923\">"
              @"</SegmentBase>"
            @"</Representation>"
            @"<Representation bandwidth=\"127236\" codecs=\"mp4a\" id=\"5\" "
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
  DDTTYLogger *_logger;
  Streaming *_streaming;
}
@end

@implementation MpdParserTest

- (void)setUp {
  _logger = [DDTTYLogger sharedInstance];
  [DDLog addLogger:_logger];
  _streaming = [[Streaming alloc] initWithAirplay:NO licenseServerURL:nil];
}

- (void)tearDown {
  [DDLog removeLogger:_logger];
}

// Validate Parents attributes in Adaptation set are propogated down.
- (void)testDownwardPropagation {
  _streaming.streams =
      [self parseStaticMPD:kSplitBaseMpdData URLString:kEncContentMpdURL];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqualObjects(stream.mimeType, @"video/mp4");
    }
  }
}

// Validate lower attributes take precendence over higher ones.
- (void)testOverwritingAttributes {
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData
                                  URLString:kEncContentMpdURL];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqualObjects(stream.mimeType, @"video/mp4");
    }
  }
}


// Validate Index Range is being parsed and set correctly.
- (void)testIndexRange {
  _streaming.streams =
      [self parseStaticMPD:kSplitBaseMpdData URLString:kEncContentMpdURL];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqual(stream.initialRange.length, 1767);
    }
  }
}

// Validate Failure when InitRange is missing or invalid.
- (void)testInvalidIndexRange {
  _streaming.streams =
      [self parseStaticMPD:kInvalidParamsMpdData URLString:kClearContentMpdURL];
  XCTAssertEqual(_streaming.streams.count, 3);
  for (Stream *stream in _streaming.streams) {
    if (stream.streamIndex == 0) {
      XCTAssertEqual(stream.initialRange.location, 0);
    }
    if (stream.streamIndex == 1) {
      XCTAssertEqual(stream.initialRange.length, 924);
    }
    if (stream.streamIndex == 2) {
      XCTAssertEqual(stream.initialRange.location, 674);
    }
  }
}

// Validate Failure with Missing or Invalid MimeType and Codecs
- (void)testInvalidCodeMimeType {
  _streaming.streams =
      [self parseStaticMPD:kInvalidParamsMpdData URLString:kClearContentMpdURL];
  // Verify only 1 streams out of 5 were loaded. (Skip HEVC and missing MimeType)
  XCTAssertEqual(_streaming.streams.count, 3);
  for (Stream *stream in _streaming.streams) {
    XCTAssertNotEqual(stream.codecs, @"hev1.2.4.L63.90");
    XCTAssertNotEqual(stream.mimeType, @"application/mp4");
  }
}

// Validate Failure with bad PSSH
- (void)testInvalidPSSH {
  _streaming.streams =
      [self parseStaticMPD:kInvalidParamsMpdData URLString:kClearContentMpdURL];
  // Verify only 3 streams out of 5 were loaded. (Skip HEVC and missing MimeType)
  XCTAssertEqual(_streaming.streams.count, 3);
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertGreaterThan(stream.pssh.length, 0);
    } else {
      XCTAssertEqual(stream.pssh.length, 0);
    }
  }
}


// Validate having a Base URL that is different than the MPD source.
- (void)testSplitURL {
  _streaming.streams =
      [self parseStaticMPD:kSplitBaseMpdData URLString:kEncContentMpdURL];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqualObjects([stream.sourceURL absoluteString],
                            @"http://google.com/test/video.mp4");
    } else {
      XCTAssertEqualObjects([stream.sourceURL absoluteString],
                            @"http://google.com/test/audio.mp4");
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
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData
                                  URLString:kClearContentMpdURL];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      XCTAssertEqual(stream.streamIndex, 1);
    }
  }
  XCTAssertEqual(_streaming.streams.count, 2);
}


// Validate changing scheme from HTTP to HTTPS based on MPD URL.
- (void)testURLScheme {
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData
                                  URLString:kMultiAudioMpdURL];
  for (Stream *stream in _streaming.streams) {
    CDMLogInfo(@"Stream %@", stream);
    if (stream.isVideo) {
      // Representation Scheme should stay HTTP.
      XCTAssertEqualObjects(stream.sourceURL.scheme, @"http");
    } else {
      // No scheme present will default to MPD Scheme.
      XCTAssertEqualObjects(stream.sourceURL.scheme, @"https");
    }
  }

}

// Validate Parents attributes for BaseURL are propogated down correctly.
- (void)testRepresentationBaseURL {
  _streaming.streams = [self parseStaticMPD:kSubParamOverrideMpdData
                                  URLString:kEncContentMpdURL];
  for (Stream *stream in _streaming.streams) {
    if (stream.isVideo) {
      // Validate this URL is same as Representation BaseURL.
      XCTAssertEqualObjects([stream.sourceURL absoluteString],
                            @"http://google.com/new/video/path/video.mp4");
    } else {
      // Validate this URL uses Global BaseURL.
      XCTAssertEqualObjects([stream.sourceURL absoluteString],
                            @"http://google.com/test/audio.mp4");
    }
  }
}

# pragma mark - Private Methods

- (NSArray<Stream *> *)parseStaticMPD:(NSString *)mpd
                         URLString:(NSString *)URLString {
  NSURL *mpdURL = [[NSURL alloc] initWithString:URLString];
  NSData *mockData = [mpd dataUsingEncoding:NSUTF8StringEncoding];
  return [MpdParser parseMpdWithStreaming:_streaming
                                  mpdData:mockData
                                  baseURL:mpdURL
                             storeOffline:NO];
}

- (NSArray<Stream *> *)parseMPDURL:(NSString *)mpdURL {
  NSURL *URL = [[NSURL alloc] initWithString:mpdURL];
  NSError *error = nil;
  NSData *data = [NSData dataWithContentsOfURL:URL
                                       options:NSDataReadingUncached
                                         error:&error];
  if (error) {
    CDMLogNSError(error, @"reading %@", mpdURL);
    return nil;
  } else {
    return [MpdParser parseMpdWithStreaming:_streaming
                                    mpdData:data
                                    baseURL:URL
                               storeOffline:NO];
  }
}

@end
