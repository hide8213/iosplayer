// Copyright 2015 Google Inc. All rights reserved.

#import <Foundation/Foundation.h>

#import "CdmWrapper.h"
#import "OemcryptoIncludes.h"

struct DashToHlsIndex;
struct DashToHlsSession;
@class Streaming;

@interface Stream : NSObject
- (id)initWithStreaming:(Streaming *)streaming;
- (BOOL)initialize:(NSData *)initializationData;
@property NSUInteger bandwidth;
@property(strong) NSString *codec;
@property BOOL done;
@property struct DashToHlsIndex *dashIndex;
@property NSUInteger index;
@property NSRange initializationRange;
@property BOOL isVideo;
@property NSUInteger height;
@property(strong) NSData *m3u8;
@property(strong) NSString *mimeType;
@property struct DashToHlsSession *session;
@property(weak) Streaming *streaming;
@property NSUInteger width;
@property(strong) NSURL *url;
@end

