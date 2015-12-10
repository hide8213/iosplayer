#import "CdmWrapper.h"


@interface LicenseManager : NSObject <iOSCdmDelegate>
+ (void)startup;
+ (void)shutdown;
+ (LicenseManager *)sharedInstance;

@end
