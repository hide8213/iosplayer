// Copyright 2015 Google Inc. All rights reserved.

#import "AppDelegate.h"
#import "Stream.h"

@interface MpdParser : NSObject <NSXMLParserDelegate>
@property(nonatomic, strong) NSMutableArray *streams;

- (id)initWithStreaming:(Streaming *)streaming
                mpdData:(NSData *)mpdData
                baseUrl:(NSURL *)baseUrl;

+ (void)deleteFilesInMpd:(NSURL *)mpdUrl;
+ (NSArray *)parseMpdWithStreaming:(Streaming *)streaming
                           mpdData:(NSData *)mpdData
                           baseUrl:(NSURL *)baseUrl;
@end


