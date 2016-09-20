// Copyright 2016 Google Inc. All rights reserved.

#import "CdmPlayerErrors.h"

NSString * const CdmPlayeriOSErrorDomain = @"CdmPlayeriOSErrorDomain";

@implementation NSError (CDMPlayerErrors)
+ (instancetype)cdmErrorWithCode:(CDMPlayerErrorCode)code userInfo:(NSDictionary *)userInfo {
  return [NSError errorWithDomain:CdmPlayeriOSErrorDomain code:code userInfo:userInfo];
}
@end