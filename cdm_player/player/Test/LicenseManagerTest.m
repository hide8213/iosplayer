#import "LicenseManager.h"

NSString *kMockLicenseFile = @"mockLicenseFile.lic";
NSString *kMockWebSessionId = @"webSessionId12345";
const char kMockBytes[2] = { 0, 1 };

@interface LicenseManagerTest : XCTestCase {
  LicenseManager *_licMgr;
  NSData *_mockData;
}
@end

@implementation LicenseManagerTest

- (void)setUp {
  _licMgr = [self getSharedLicMgr];
  _mockData = [NSData dataWithBytes:kMockBytes length:sizeof(kMockBytes)];
}

- (void)testLicenseManager {
  // Verify License Manager was created.
  XCTAssertNotNil([self getSharedLicMgr]);
}

- (void)testLicensePssh {
  // Validate setting KeyMapData and extracting.
  XCTAssertNoThrow([_licMgr onSessionCreatedWithPssh:_mockData webId:kMockWebSessionId]);
  XCTAssertEqualObjects([_licMgr webSessionForPssh:_mockData], kMockWebSessionId);
}

- (void)testLicensePsshFail {
  // Validate mismatch data -- Negative Test.
  NSString *newMockWebSessionId = @"12345WebSessionId";
  // Create KeyMapData using expected WebSessionID.
  XCTAssertNoThrow([_licMgr onSessionCreatedWithPssh:_mockData webId:kMockWebSessionId]);
  // Check for different WebSessionID than what was created.
  XCTAssertNotEqualObjects([_licMgr webSessionForPssh:_mockData], newMockWebSessionId);
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

# pragma mark private methods

- (LicenseManager *)getSharedLicMgr {
  return [LicenseManager sharedInstance];
}

@end
