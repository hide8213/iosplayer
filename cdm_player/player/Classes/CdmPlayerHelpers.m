// Copyright 2017 Google Inc. All rights reserved.

#import "CdmPlayerHelpers.h"

NSURL *CDMDocumentFileURLForFilename(NSString *filename) {
  NSURL *documentDirectoryUrl =
      [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                             inDomains:NSUserDomainMask][0];
  return [NSURL URLWithString:filename relativeToURL:documentDirectoryUrl];
}
