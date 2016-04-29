// Copyright 2015 Google Inc. All rights reserved.

#import "AppDelegate.h"
#import "Stream.h"

@interface MpdParser : NSObject <NSXMLParserDelegate>

// Array of streams found in the XML manifest.
@property(nonatomic, strong) NSMutableArray *streams;

// Remove media files listed in Manifest.
+ (void)deleteFilesInMpd:(NSURL *)mpdUrl;
// Being parsing of Manifest by passing URL of streaming content.
+ (NSMutableArray *)parseMpdWithStreaming:(Streaming *)streaming
                                  mpdData:(NSData *)mpdData
                                  baseUrl:(NSURL *)baseUrl;

// Being parsing of Manifest by passing URL for offline content.
+ (NSMutableArray *)parseMpdForOffline:(NSData *)mpdData
                               baseUrl:(NSURL *)baseUrl;

// Convert MPEG Dash formatted duration into seconds.
- (NSUInteger)convertDurationToSeconds:(NSString *)string;
@end


