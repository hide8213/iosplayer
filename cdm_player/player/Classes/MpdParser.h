// Copyright 2015 Google Inc. All rights reserved.

#import "AppDelegate.h"
#import "Stream.h"

@interface MpdParser : NSObject <NSXMLParserDelegate>
@property(nonatomic, strong) NSMutableArray *streams;

+ (void)deleteFilesInMpd:(NSURL *)mpdUrl;
+ (NSMutableArray *)parseMpdWithStreaming:(Streaming *)streaming
                                  mpdData:(NSData *)mpdData
                                  baseUrl:(NSURL *)baseUrl;

+ (NSMutableArray *)parseMpdForOffline:(NSData *)mpdData
                               baseUrl:(NSURL *)baseUrl;
@end


