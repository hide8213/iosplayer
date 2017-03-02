// Copyright 2016 Google Inc. All rights reserved.

#import "Logging.h"

NSString * const kEmptyErrorFormat = @"Error:\n     %@";

NSString *CdmErrorFmt(NSString *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  NSString *formatted = [[NSString alloc] initWithFormat:fmt arguments:args];
  va_end(args);
  return [NSString stringWithFormat:@"Error %@:\n     %%@", formatted];
}
