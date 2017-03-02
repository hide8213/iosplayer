// Copyright 2016 Google Inc. All rights reserved.

#import <Foundation/Foundation.h>

extern NSString * const CdmPlayeriOSErrorDomain;
typedef NS_ENUM(NSInteger, CDMPlayerErrorCode) {
  CdmPlayeriOSErrorCode_URLIsNil = 0,
  CdmPlayeriOSErrorCode_AssetCannotBePlayed = 1,
  CdmPlayeriOSErrorCode_NoConnection = 2,
  CdmPlayeriOSErrorCode_EmptyMPD = 3,
  CdmPlayeriOSErrorCode_AlreadyDownloading = 4,
};

@interface NSError (CDMPlayerErrors)
+ (instancetype)cdmErrorWithCode:(CDMPlayerErrorCode)code userInfo:(NSDictionary *)userInfo;
@end
