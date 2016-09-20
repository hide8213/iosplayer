// Copyright 2015 Google Inc. All rights reserved.

#import "LocalWebConnection.h"

#import "LocalWebServer.h"

// Handles incoming HTTP request to the |LocalWebServer|.
@implementation LocalWebConnection {
  Streaming *_streaming;
}

- (id)initWithAsyncSocket:(GCDAsyncSocket *)newSocket configuration:(HTTPConfig *)aConfig {
  self = [super initWithAsyncSocket:newSocket configuration:aConfig];
  if (self) {
    if ([aConfig.server class] == [LocalWebServer class]) {
      _streaming = ((LocalWebServer *)config.server).streaming;
    }
  }
  return self;
}

- (NSObject<HTTPResponse> *)httpResponseForMethod:(NSString *)method URI:(NSString *)path {
  return [_streaming responseForMethod:method path:path connection:self];
}
@end
