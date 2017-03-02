#import <OCMock/OCMock.h>

#import "CdmPlayerErrors.h"
#import "Downloader.h"
#import "Logging.h"
#import "MediaResource.h"
#import "Stream.h"

NSInteger const kPartialDownloadLength = 1453;
NSInteger const kPartialDownloadStartTime = 600;
float const kWaitForAsyncCallbackTimeout = 1.0;
static NSString *const kPartialDownloadName = @"tears_h264_baseline_240p_800";
static NSString *const kDownloadName = @"tears_cenc_small";
static NSString *const kDownloadNameWithExtension = @"tears_cenc_small.mpd";
static NSString *const kDownloadFirstContents = @"tears_audio_eng.mp4";
static NSString *const kDownloadSecondsContents = @"tears_h264_baseline_240p_800.mp4";
static NSString *const kInvalidDownloadName = @"fakefile";
extern NSTimeInterval kDownloadTimeout;
extern NSString *const kRangeHeaderString;

@interface DownloaderDelegateMock : NSObject <DownloadDelegate>

@property int startDownloadingCalled;
@property int updateDownloadingCalled;
@property int failedDownloadingCalled;
@property int finishedDownloadingCalled;
@property NSMutableArray *filePaths;
@property NSError *lastError;
@property(nonatomic, copy) void (^startBlock)(int);
@property(nonatomic, copy) void (^finalBlock)(int);

@end

@implementation DownloaderDelegateMock

- (void)downloader:(Downloader *)downloader
    didStartDownloadingToURL:(NSURL *)sourceURL
                   toFileURL:(NSURL *)fileURL {
  self.startDownloadingCalled += 1;
  if (!self.filePaths) {
    self.filePaths = [[NSMutableArray alloc] init];
  }
  [self.filePaths addObject:fileURL.lastPathComponent];
  if (self.startBlock) {
    self.startBlock(self.startDownloadingCalled);
  }
}

- (void)downloader:(Downloader *)downloader
    didUpdateDownloadProgress:(float)progress
                   forFileURL:(NSURL *)fileURL {
  self.updateDownloadingCalled += 1;
}

- (void)downloader:(Downloader *)downloader
    downloadFailedForURL:(NSURL *)sourceURL
               withError:(NSError *)error {
  self.lastError = error;
  self.failedDownloadingCalled += 1;
  if (self.finalBlock) {
    self.finalBlock(self.failedDownloadingCalled + self.finishedDownloadingCalled);
  }
}

- (void)downloader:(Downloader *)downloader
    didFinishDownloadingToURL:(NSURL *)sourceURL
                    toFileURL:(NSURL *)fileURL {
  self.finishedDownloadingCalled += 1;
  if (self.finalBlock) {
    self.finalBlock(self.failedDownloadingCalled + self.finishedDownloadingCalled);
  }
}

@end

@interface DownloaderTest : XCTestCase {
  DownloaderDelegateMock *_delegate;
  DDTTYLogger *_logger;
}
@end

@implementation DownloaderTest

- (void)setUp {
  _logger = [DDTTYLogger sharedInstance];
  [DDLog addLogger:_logger];
  _delegate = [[DownloaderDelegateMock alloc] init];
}

- (void)tearDown {
  [DDLog removeLogger:_logger];
}

- (void)testDownloadMPDInvalid {
  [self downloadTestInnerFailure];
  XCTAssertEqual(_delegate.finishedDownloadingCalled, 0);
  XCTAssertEqual(_delegate.failedDownloadingCalled, 1);
  XCTAssertEqual(_delegate.startDownloadingCalled, 1);
  XCTAssertEqual(_delegate.updateDownloadingCalled, 0);
}

// TODO (theodab): test downloading a manifest with a SegmentTemplate field
// like mp4-live-mpd-AV-BS.mpd, but a smaller one
// to make sure that it can do it successfully, and loads the right contents and such

- (void)testDownloadMPD {
  NSString *path = [[NSBundle mainBundle] pathForResource:kDownloadName ofType:@"mpd"];
  NSData *fileData = [NSData dataWithContentsOfFile:path];

  // it should start downloading the two content files right after signalling the end of the first
  [self downloadTestInnerWithFileURL:[NSURL URLWithString:kDownloadNameWithExtension]
                         andFileData:fileData];

  // were the delegate methods being called the right number of times?
  XCTAssertEqual(_delegate.finishedDownloadingCalled, 3);
  XCTAssertEqual(_delegate.failedDownloadingCalled, 0);
  XCTAssertEqual(_delegate.startDownloadingCalled, 3);
  XCTAssertEqual(_delegate.updateDownloadingCalled, 3); // the mock calls this once each

  // check to see the correct files have been loaded
  XCTAssertEqual(_delegate.filePaths.count, 3);
  XCTAssertEqualObjects(kDownloadNameWithExtension, _delegate.filePaths[0]);
  XCTAssertTrue([kDownloadFirstContents isEqualToString:_delegate.filePaths[1]] ||
                [kDownloadFirstContents isEqualToString:_delegate.filePaths[2]]);
  XCTAssertTrue([kDownloadSecondsContents isEqualToString:_delegate.filePaths[1]] ||
                [kDownloadSecondsContents isEqualToString:_delegate.filePaths[2]]);
}

- (void)testAlreadyDownloadingError {
  Downloader *shared = [Downloader sharedInstance];
  NSURL *url = self.randomURL;
  NSURL *fileURL = self.randomURL;
  NSURLRequest *request = [NSURLRequest requestWithURL:self.randomURL];

  // set up a download task mock that simply does nothing
  NSURLSessionDownloadTask *template = [shared.downloadSession downloadTaskWithRequest:request];
  id mockTask = [OCMockObject partialMockForObject:template];
  [[mockTask stub] resume];

  // set up a mock for connection that returns the safe template
  id mockConnection = [OCMockObject partialMockForObject:shared.downloadSession];
  [[[mockConnection stub] andReturn:mockTask] downloadTaskWithURL:[OCMArg any]];

  // download the first time; this should start as expected
  __weak XCTestExpectation *expectationA = [self expectationWithDescription:@"Start called"];
  _delegate.startBlock = ^void(int startCount) {
    if (startCount == 1) {
      [expectationA fulfill];
    }
  };
  [shared downloadURL:url toFileURL:fileURL delegate:_delegate];
  // this involves an asynchronous callback, so there's a (very short) gap of time
  [self waitForExpectationsWithTimeout:kWaitForAsyncCallbackTimeout handler:nil];
  XCTAssertEqual(_delegate.startDownloadingCalled, 1);

  // download the second time, this should fail to start at all
  __weak XCTestExpectation *expectationB = [self expectationWithDescription:@"Fail called"];
  _delegate.finalBlock = ^void(int finishCount) {
    if (finishCount == 1) {
      [expectationB fulfill];
    }
  };
  [shared downloadURL:url toFileURL:fileURL delegate:_delegate];
  [self waitForExpectationsWithTimeout:kWaitForAsyncCallbackTimeout handler:nil];
  XCTAssertEqual(_delegate.startDownloadingCalled, 1);
  XCTAssertEqual(_delegate.failedDownloadingCalled, 1);
  XCTAssertEqual(_delegate.lastError.code, CdmPlayeriOSErrorCode_AlreadyDownloading);

  // now fail the first request so it's no longer in progress
  NSError *fakeError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
  [shared URLSession:shared.downloadSession
                             task:mockTask
             didCompleteWithError:fakeError];

  // and run a third request. As the first one is no longer running, this should succeed
  __weak XCTestExpectation *expectationC = [self expectationWithDescription:@"Start called"];
  _delegate.startBlock = ^void(int startCount) {
    if (startCount == 2) {
      [expectationC fulfill];
    }
  };
  [shared downloadURL:url toFileURL:fileURL delegate:_delegate];
  [self waitForExpectationsWithTimeout:kWaitForAsyncCallbackTimeout handler:nil];
  XCTAssertEqual(_delegate.startDownloadingCalled, 2);
}

- (void)testPartialDownload {
  __weak XCTestExpectation *mockExpectation = [self expectationWithDescription:
                                               @"Patial download mock called"];
  __weak XCTestExpectation *callExpectation = [self expectationWithDescription:
                                               @"Patial download completion called"];
  NSURL *url = self.randomURL;
  NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:1 userInfo:nil];
  NSURLResponse *response = [[NSURLResponse alloc] initWithURL:url
                                                      MIMEType:@"whatever"
                                         expectedContentLength:42
                                              textEncodingName:@"whatever"];
  NSData *data = [NSData data];
  NSRange range = NSMakeRange(0, kPartialDownloadLength);

  void (^block)(NSInvocation *) = ^(NSInvocation *invocation) {
    __unsafe_unretained NSMutableURLRequest *request;
    __unsafe_unretained void (^callback)(NSData *data, NSURLResponse *response, NSError *error);
    [invocation getArgument:&request atIndex:2];
    [invocation getArgument:&callback atIndex:3];
    XCTAssertEqualObjects(request.URL, url);
    callback(data, response, error);
    [mockExpectation fulfill];
  };
  id mock = [self mockDownloadSessionWithCallResult:block];

  Downloader *down = [Downloader sharedInstance];
  [down downloadPartialData:url
                      range:range
                 completion:^(NSData *rData, NSError *rError) {
                   XCTAssertEqualObjects(rData, data);
                   XCTAssertEqualObjects(rError, error);
                   [callExpectation fulfill];
                 }];
  [self waitForExpectationsWithTimeout:kDownloadTimeout handler:nil];
}

- (void)testPartialDownloadBlocking {
  NSURL *url = self.randomURL;
  NSData *data = [NSData data];
  NSRange range = NSMakeRange(0, kPartialDownloadLength);

  void (^block)(NSInvocation *) = ^(NSInvocation *invocation) {
    __unsafe_unretained NSMutableURLRequest *request;
    __unsafe_unretained void (^callback)(NSData *data, NSURLResponse *response, NSError *error);
    [invocation getArgument:&request atIndex:2];
    [invocation getArgument:&callback atIndex:3];
    XCTAssertEqual(request.URL, url);
    callback(data, nil, nil);
  };
  id mock = [self mockDownloadSessionWithCallResult:block];

  NSData *rData = [[Downloader sharedInstance] downloadPartialDataSync:url range:range];
  XCTAssertEqualObjects(rData, data);
}

- (void)testPartialDownloadWithStartTime {
  NSRange range = NSMakeRange(kPartialDownloadStartTime, kPartialDownloadLength);

  void (^block)(NSInvocation *) = ^(NSInvocation *invocation) {
    __unsafe_unretained NSMutableURLRequest *request;
    __unsafe_unretained void (^callback)(NSData *data, NSError *error);
    [invocation getArgument:&request atIndex:2];
    [invocation getArgument:&callback atIndex:3];
    XCTAssertEqual(request.allHTTPHeaderFields.count, 1);
    if (request.allHTTPHeaderFields.count == 1) {
      XCTAssertEqualObjects(request.allHTTPHeaderFields.allKeys[0], kRangeHeaderString);
      int start = kPartialDownloadStartTime;
      int end = kPartialDownloadStartTime + kPartialDownloadLength;
      NSString *range = [NSString stringWithFormat:@"bytes=%i-%i", start, end];
      XCTAssertEqualObjects(request.allHTTPHeaderFields.allValues[0], range);
    }
    callback(nil, nil);
  };
  id mock = [self mockDownloadSessionWithCallResult:block];
  [[Downloader sharedInstance] downloadPartialDataSync:self.randomURL range:range];
}

#pragma mark private methods

- (void)downloadTestInnerFailure {
  Downloader *shared = [Downloader sharedInstance];
  NSURLRequest *request = [NSURLRequest requestWithURL:self.randomURL];

  // set up a mock download task
  NSURLSessionDownloadTask *template = [shared.downloadSession downloadTaskWithRequest:request];
  id mockTask = [OCMockObject partialMockForObject:template];
  void (^resumeBlock)(NSInvocation *) = ^(NSInvocation *invocation) {
    id<NSURLSessionDownloadDelegate> del =
    (id<NSURLSessionDownloadDelegate>)shared.downloadSession.delegate;
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:nil];
    [del URLSession:shared.downloadSession task:template didCompleteWithError:error];
  };
  [[[mockTask stub] andDo:resumeBlock] resume];

  // set up the expectation, to wait for the file and it's sub-files to download
  __weak XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
  _delegate.finalBlock = ^void(int finishCount) {
    if (finishCount == 1) {
      [expectation fulfill];
    }
  };

  [shared downloadURL:self.randomURL
                         toFileURL:self.randomURL
                          delegate:_delegate];

  // wait for the expectation
  [self waitForExpectationsWithTimeout:kDownloadTimeout handler:nil];
}

- (id)mockDownloadSessionWithCallResult:(void (^)(NSInvocation *))callResult {
  Downloader *shared = [Downloader sharedInstance];
  id mockDS = [OCMockObject partialMockForObject:shared.downloadSession];

  [[[mockDS stub] andDo:callResult] dataTaskWithRequest:[OCMArg any]
                                      completionHandler:[OCMArg any]];

  return mockDS;
}

- (void)downloadTestInnerWithFileURL:(NSURL *)fileURL andFileData:(NSData *)fileData {
  Downloader *shared = [Downloader sharedInstance];

  __block NSURL *savedURL;

  // set up a mock file manager
  void (^moveBlock)(NSInvocation *) = ^(NSInvocation *invocation) {
    __unsafe_unretained NSURL *from;
    __unsafe_unretained NSURL *to;
    [invocation getArgument:&from atIndex:2];
    [invocation getArgument:&to atIndex:3];
    XCTAssertEqualObjects(from, savedURL);
    savedURL = to;
  };
  id mockFM = [OCMockObject partialMockForObject:[NSFileManager defaultManager]];
  [[[mockFM stub] andReturn:mockFM] defaultManager];
  [[[mockFM stub] andDo:moveBlock] moveItemAtURL:[OCMArg any]
                                           toURL:[OCMArg any]
                                           error:[OCMArg setTo:nil]];

  // set up a mock for data
  id mockData = [OCMockObject mockForClass:[NSData class]];
  [[[mockData stub] andReturn:fileData] dataWithContentsOfURL:[OCMArg any]];

  // set up three mocks, one for each download task
  NSMutableArray *templates = [[NSMutableArray alloc] init];
  NSMutableArray *mockTasks = [[NSMutableArray alloc] init];
  for (int i = 0; i < 3; i++) {
    NSURLRequest *request = [NSURLRequest requestWithURL:self.randomURL];
    NSURLSessionDownloadTask *template = [shared.downloadSession downloadTaskWithRequest:request];
    id mock = [OCMockObject partialMockForObject:template];
    void (^resumeBlock)(NSInvocation *) = ^(NSInvocation *invocation) {
      savedURL = self.randomURL;
      id<NSURLSessionDownloadDelegate> del =
      (id<NSURLSessionDownloadDelegate>)shared.downloadSession.delegate;
      NSURLSession *ses = shared.downloadSession;
      [del URLSession:ses
                 downloadTask:mock
                 didWriteData:0
            totalBytesWritten:0
    totalBytesExpectedToWrite:1];
      [del URLSession:ses downloadTask:mock didFinishDownloadingToURL:savedURL];
    };
    [[[mock stub] andDo:resumeBlock] resume];

    // store the important bits so they don't go out of scope
    [templates addObject:template];
    [mockTasks addObject:mock];
  }

  // set up a mock for connection
  id mockConnection = [OCMockObject partialMockForObject:shared.downloadSession];
  for (int i = 0; i < 3; i++) {
    // each call to downloadTaskWithURL returns a different download task partial mock
    [[[mockConnection expect] andReturn:mockTasks[i]] downloadTaskWithURL:[OCMArg any]];
  }

  // set up the expectation, to wait for the file and it's sub-files to download
  __weak XCTestExpectation *expectation = [self expectationWithDescription:@"Completion called"];
  _delegate.finalBlock = ^void(int finishCount) {
    if (finishCount == 3) {
      [expectation fulfill];
    }
  };

  [shared downloadURL:self.randomURL
            toFileURL:fileURL
             delegate:_delegate];

  // wait for the expectation
  [self waitForExpectationsWithTimeout:kDownloadTimeout handler:nil];
  [mockConnection verify];
}

-(NSURL *)randomURL {
  // several places in these tests require arbitrary URLs
  // the only important thing is that no two are the same,
  // since the URLs are used internally in hashing
  int randNumber = arc4random_uniform(UINT32_MAX);
  NSString *string = [NSString stringWithFormat:@"FAKEURL#%i", randNumber];
  return [NSURL URLWithString:string];
}

@end
