// Copyright 2016 Google Inc. All rights reserved.

#import <Foundation/Foundation.h>

#import "CocoaLumberjack.h"

#if DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif
extern NSString * const kEmptyErrorFormat;
OBJC_EXTERN NSString *CdmErrorFmt(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);

// logs an NSError to CocoaLumberjack, using a standardized error logging style
// err is an NSError
// fmt is a format string describing the context of the error (eg "failed to create foobar")
#define CDMLogNSError(err, fmt, ...)                                         \
  do {                                                                       \
    if (err) {                                                               \
      DDLogError(CdmErrorFmt(fmt, ##__VA_ARGS__), err.localizedDescription); \
    }                                                                        \
  } while (0)

// logs the current contents of errno to CocoaLumberjack, using a standardized error logging style
// fmt is a format string describing the context of the error (eg "failed to create foobar")
#define CDMLogErrno(fmt, ...) DDLogError(CdmErrorFmt(fmt,                                          \
                                                     ##__VA_ARGS__),                               \
                                                     [NSString stringWithFormat:@"Error #%i (%s)", \
                                                                                errno,             \
                                                                                strerror(errno)])

// logs an arbitrary message to CocoaLumberjack, using a standardized error logging style
// fmt is a format string describing the error (eg "foobar is nil")
#define CDMLogError(fmt, ...) DDLogError(kEmptyErrorFormat, \
                                         [NSString stringWithFormat:fmt, ##__VA_ARGS__])

// wrapper for DDLogWarn
#define CDMLogWarn(fmt, ...) DDLogWarn(fmt, ##__VA_ARGS__)

// wrapper for DDLogInfo
#define CDMLogInfo(fmt, ...) DDLogInfo(fmt, ##__VA_ARGS__)
