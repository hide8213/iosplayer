// Copyright 2015 Google Inc. All rights reserved.

#import "HTTPServer.h"
#import "Streaming.h"

// Web server running locally in the app.
@interface LocalWebServer : HTTPServer
@property(nonatomic) NSURL *rootURL;
@property(nonatomic, readonly) NSString *hostname;
@property(nonatomic, readonly) dispatch_queue_t connectionQueue;
@property(nonatomic) Streaming *streaming;

- (id)initWithStreaming:(Streaming *)streaming;
@end
