// Copyright 2015 Google Inc. All rights reserved.

#import "LocalWebServer.h"

#import "LocalWebConnection.h"

NSString *kHttpPrefix = @"http://%@";
NSString *kHost = @"%@:%d";

@implementation LocalWebServer

- (id)initWithStreaming:(Streaming *)streaming {
  self = [super init];
  if (self) {
    _streaming = streaming;
  }
  return self;
}

- (BOOL)start:(NSError *__autoreleasing *)errPtr {
  if (self.isRunning) {
    return YES;
  }
  [self setPort:_streaming.httpPort];
  [self setType:@"_http._tcp."];
  [self setInterface:_streaming.address];
  [self setConnectionClass:[LocalWebConnection class]];
  BOOL success = [super start:errPtr];
  if (success) {
    _rootURL = [NSURL URLWithString:[NSString stringWithFormat:kHttpPrefix, [self hostname]]];
  }
  return success;
}

- (NSString *)hostname {
  return [NSString stringWithFormat:kHost, _streaming.address, _streaming.httpPort];
}

- (dispatch_queue_t)connectionQueue {
  return connectionQueue;
}

@end
