#import "Downloader.h"
#import "MediaResource.h"

int const kPartialDownloadLength = 1453;
NSString *const kPartialDownloadName = @"tears_h264_baseline_240p_800";
NSString *const kDownloadName = @"tears_cenc_small";
NSString *const kInvalidDownloadName = @"fakefile";
NSString *const kInvalidUrl = @"file://fakefolder/alsofake/reallyfake/fakefile.mpd";
extern NSTimeInterval kPartialDownloadTimeout;

@interface DownloaderDelegateMock : NSObject <DownloadDelegate>

@property int startDownloadingCalled;
@property int updateDownloadingCalled;
@property int failedDownloadingCalled;
@property int finishedDownloadingCalled;
@property(nonatomic, copy) void (^finalBlock)(int);

@end

@implementation DownloaderDelegateMock

- (void)startDownloading:(Downloader *)downloader fileURL:(NSURL *)fileURL {
  self.startDownloadingCalled += 1;
}

- (void)updateDownloadProgress:(NSNumber *)progress fileURL:(NSURL *)fileURL {
  self.updateDownloadingCalled += 1;
}

- (void)failedDownloading:(Downloader *)downloader
                  fileURL:(NSURL *)fileURL
                    error:(NSError *)error {
  self.failedDownloadingCalled += 1;
  self.finalBlock(self.failedDownloadingCalled + self.finishedDownloadingCalled);
  NSLog(@"Downloader with file URL %@ experienced error %@", fileURL, error);
}

- (void)finishedDownloading:(Downloader *)downloader
                       file:(NSURL *)file
               initialRange:(NSDictionary *)initialRange {
  self.finishedDownloadingCalled += 1;
  self.finalBlock(self.failedDownloadingCalled + self.finishedDownloadingCalled);
}

@end

@interface DownloaderTest : XCTestCase {
  Downloader *_download;
  DownloaderDelegateMock *_delegate;
}
@end

@implementation DownloaderTest

- (void)setUp {
  _delegate = [[DownloaderDelegateMock alloc] init];
}

- (void)tearDown {
}

- (void)testDownloadMPDInvalid {
  [self innerDownloadWithFileName:kInvalidDownloadName];
  XCTAssertEqual(_delegate.finishedDownloadingCalled, 0);
  XCTAssertEqual(_delegate.failedDownloadingCalled, 1);
  XCTAssertEqual(_delegate.startDownloadingCalled, 1);
  XCTAssertEqual(_delegate.updateDownloadingCalled, 0);
}

- (void)testDownloadMPD {
  [self innerDownloadWithFileName:kDownloadName];
  XCTAssertEqual(_delegate.finishedDownloadingCalled, 1);
  XCTAssertEqual(_delegate.failedDownloadingCalled, 0);
  XCTAssertEqual(_delegate.startDownloadingCalled, 1);
  XCTAssertGreaterThan(_delegate.updateDownloadingCalled, 0);

  // TODO(theodab): use OCMock to simulate the NSFileSystem, and short-circuit learn what files to
  // download here

  //  // the MPD should then download the files the mpd listed
  // __weak XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
  // _delegate.finalBlock = ^void(int finishCount) {
  //   NSLog(@"Finish count is %i", finishCount);
  // };
  //
  // [self waitForExpectationsWithTimeout:kPartialDownloadTimeout handler:nil];
}

- (void)testPartialDownload {
  __weak XCTestExpectation *expectation =
      [self expectationWithDescription:@"Patial download completion called"];

  NSURL *url = [[NSBundle mainBundle] URLForResource:kPartialDownloadName withExtension:@"mp4"];

  NSDictionary *initialRange = @{ @"length": @(kPartialDownloadLength), @"startRange": @0 };
  [Downloader downloadPartialData:url
                     initialRange:initialRange
                       completion:^(NSData *data, NSURLResponse *response, NSError *error) {
                         [expectation fulfill];

                         XCTAssertNotNil(data);
                       }];

  [self waitForExpectationsWithTimeout:kPartialDownloadTimeout handler:nil];
}

- (void)testPartialDownloadBlocking {
  NSURL *url = [[NSBundle mainBundle] URLForResource:kPartialDownloadName withExtension:@"mp4"];

  NSDictionary *initialRange = @{ @"length": @(kPartialDownloadLength), @"startRange": @0 };
  NSData *data = [Downloader downloadPartialData:url initialRange:initialRange completion:nil];

  XCTAssertNotNil(data);
}

- (void)testPartialDownloadInvalid {
  NSURL *url = [NSURL URLWithString:kInvalidUrl];

  NSDictionary *initialRange = @{ @"length": @(kPartialDownloadLength), @"startRange": @0 };
  NSData *data = [Downloader downloadPartialData:url initialRange:initialRange completion:nil];

  XCTAssertNil(data);
}

#pragma mark private methods

- (void)innerDownloadWithFileName:(NSString *)fileName {
  NSURL *manifestURL = [[NSBundle mainBundle] URLForResource:fileName withExtension:@"mpd"];
  NSURL *fileURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@.mpd", fileName]];

  __weak XCTestExpectation *expectation =
      [self expectationWithDescription:@"Download completion called"];
  _delegate.finalBlock = ^void(int finishCount) {
    if (finishCount == 1) {
      [expectation fulfill];
    }
  };

  _download = [Downloader downloaderWithURL:manifestURL
                                    fileURL:fileURL
                               initialRange:nil
                                   delegate:_delegate];

  // Technically speaking, the downloader has a much longer timeout period than this.
  // If it can't load the test files in this time though, something's probably wrong.
  [self waitForExpectationsWithTimeout:kPartialDownloadTimeout handler:nil];
}

@end
