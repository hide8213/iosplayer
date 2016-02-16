// Copyright 2015 Google Inc. All rights reserved.

#import "CdmWrapper.h"

@interface LicenseManager : NSObject <iOSCdmDelegate>
+ (void)startup;
+ (void)shutdown;
+ (LicenseManager *)sharedInstance;

@end
