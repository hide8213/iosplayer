// Copyright 2015 Google Inc. All rights reserved.

#import "AppDelegate.h"
#import "Stream.h"

@interface MpdParser : NSObject <NSXMLParserDelegate>

// Array of streams found in the XML manifest.
@property(nonatomic, strong) NSMutableArray<Stream *> *streams;

- (instancetype)initWithMpdData:(NSData *)mpdData;

// Remove media files listed in Manifest.
+ (void)deleteFilesInMpd:(NSURL *)mpdURL;
// Being parsing of Manifest by passing URL of streaming content.
+ (NSArray<Stream *> *)parseMpdWithStreaming:(Streaming *)streaming
                                     mpdData:(NSData *)mpdData
                                     baseURL:(NSURL *)baseURL
                                storeOffline:(BOOL)storeOffline;

// Convert MPEG Dash formatted duration into seconds.
- (NSUInteger)convertDurationToSeconds:(NSString *)string;
@end
