// Copyright 2015 Google Inc. All rights reserved.

#import <Foundation/Foundation.h>

#import "HTTPConnection.h"
#import "HTTPResponse.h"
#import "HTTPServer.h"

@class HTTPConnection;
@class HTTPServer;
@class LocalWebServer;
@class Stream;
@protocol HTTPResponse;

extern NSString* kStreamingReadyNotification;

// Contains a collection of Streams that provides the HLS playlist and TS segments that is
// used by AVPlayer to playback the video.
@interface Streaming : NSObject
@property(strong) NSString* address;
@property int httpPort;
@property(strong) NSURL* manifestURL;
@property BOOL offline;
@property dispatch_queue_t streamingQ;
- (id)initWithAirplay:(BOOL)isAirplayActive;
- (NSURL *)manifestURL;
- (void)parseManifest:(NSData *)manifest;
- (void)setManifestURL:(NSURL *)url;
- (void)stop;
- (void)restart:(BOOL)isAirplayActive;
- (void)streamReady:(Stream*)stream;

// Returns a HTTPResponse for the webserver to return data for the |method| and |path|. |connection|
// will be notified when that data is available.
- (NSObject<HTTPResponse> *)responseForMethod:(NSString *)method
                                         path:(NSString *)path
                                   connection:(HTTPConnection *)connection;
@end

@interface DashSegment : NSObject
@property(strong) id identifier;
@property float duration;
@property NSUInteger segmentIndex;
@property(strong) NSURLRequest *urlRequest;
@property(strong) NSString *mimeType;
@end
