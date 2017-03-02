#import "LicenseManager.h"
#import "Logging.h"

NSString *kMockLicenseFile = @"mockLicenseFile.lic";
NSString *kMockWebSessionId = @"webSessionId12345";
NSString *kNewWebSessionId = @"12345WebSessionId";
NSString *kMockLicenseServerURL = @"http://license.server.com";
const char kMockBytes[2] = { 0, 1 };

@interface LicenseManagerTest : XCTestCase {
  LicenseManager *_licMgr;
  NSData *_mockData;
  DDTTYLogger *_logger;
}
@end

@implementation LicenseManagerTest

- (void)setUp {
  _licMgr = [LicenseManager sharedInstance];
  _logger = [DDTTYLogger sharedInstance];
  [DDLog addLogger:_logger];
  _mockData = [NSData dataWithBytes:kMockBytes length:sizeof(kMockBytes)];
}

- (void)tearDown {
  [DDLog removeLogger:_logger];
}

- (void)testLicenseManager {
  // Verify License Manager was created.
  XCTAssertNotNil(_licMgr);
  // Verify no license server URL exists.
  XCTAssertNil(_licMgr.licenseServerURL);
  _licMgr.licenseServerURL = [NSURL URLWithString:kMockLicenseServerURL];
  // Verify license server URL is set.
  XCTAssertEqual([_licMgr.licenseServerURL absoluteString],
                 kMockLicenseServerURL);
  XCTAssertNotNil(_licMgr);
  _licMgr.licenseServerURL = nil;

  // Verify license server URL has been cleared out.
  XCTAssertNil(_licMgr.licenseServerURL);
  _licMgr.licenseServerURL = [NSURL URLWithString:kMockLicenseServerURL];
  // Verify license server URL is set again.
  XCTAssertEqual([_licMgr.licenseServerURL absoluteString],
                 kMockLicenseServerURL);
}

- (void)testLicensePssh {
  // Validate setting KeyMapData and extracting.
  XCTAssertNoThrow([_licMgr onSessionCreatedWithPssh:_mockData sessionId:kMockWebSessionId]);
  XCTAssertEqualObjects([_licMgr sessionIdFromPssh:_mockData],
                        kMockWebSessionId);
}

- (void)testLicensePsshFail {
  // Validate mismatch data -- Negative Test.
  NSString *newMockWebSessionId = kNewWebSessionId;
  // Create KeyMapData using expected WebSessionID.
  XCTAssertNoThrow([_licMgr onSessionCreatedWithPssh:_mockData sessionId:kMockWebSessionId]);
  // Check for different WebSessionID than what was created.
  XCTAssertNotEqualObjects([_licMgr sessionIdFromPssh:_mockData],
                           newMockWebSessionId);
}

- (void)testRemoveFile {
  // Create File and Write to Disk.
  [self testWriteFile];
  // Confirm File was created correctly before removing.
  XCTAssertTrue([_licMgr fileExists:kMockLicenseFile]);
  XCTAssertTrue([_licMgr removeFile:kMockLicenseFile]);
  // Verify File was removed successfully.
  XCTAssertFalse([_licMgr fileExists:kMockLicenseFile]);
}

- (void)testWriteFile {
  // Populate License File with Mock Data.
  [_licMgr writeData:_mockData file:kMockLicenseFile];
  XCTAssertTrue([_licMgr fileExists:kMockLicenseFile]);
  XCTAssertEqual([_licMgr fileSize:kMockLicenseFile], 2);
}

- (void)testWriteFileFail {
  // Validate Bad File Name cannot be written -- Negative Test.
  NSString *badFileName = @"http://file";
  [_licMgr writeData:_mockData file:badFileName];
  XCTAssertFalse([_licMgr fileExists:badFileName]);
}

@end
