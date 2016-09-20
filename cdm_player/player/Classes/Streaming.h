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
// Delegate to access DetailViewController to pull player time.
@protocol StreamingDelegate
- (float)getCurrentTime;
@end

extern NSString *kStreamingReadyNotification;
// Contains a collection of Stream Objects.
// The individual streams are used to create an HLS Playlist, then the data is passed to the UDT
// (Dash Transmuxer) to be converted to DASH.
@interface Streaming : NSObject
@property(nonatomic, weak) id<StreamingDelegate> streamingDelegate;
// Internal IP address to be used for streaming locally.
// Typically localhost or 127.0.0.1, unless using Airplay which will then be the IP Address of the
// device.
@property(strong) NSString *address;
// HTTP Port to be used for the local web server that delivers the HLS content.
// Stored here to create the HLS Playlist correctly.
@property int httpPort;
// URL of the incoming DASH Manifest (MPD) file.
@property(strong) NSURL *mpdURL;
// Holds value if license has been stored offline.
// Determines where to fetch the license.
@property BOOL offline;
// Value used to determine when all streams have been processed.
// _streams is the mutex.
@property NSUInteger preloadCount;
// Dispatch queue to handle processing of all streams.
@property(strong) dispatch_queue_t streamingQ;
// Array containing all the child streams within the DASH Manifest (MPD).
@property NSArray *streams;
// Master HLS Playlist that is created to contain high level info about the child streams
// (bandwidth, codec, URL of stream, etc.)
@property NSString *variantPlaylist;
// Init method. isAirplayActive determines what local address to be used when setting up the local
// web server.

- (id)initWithAirplay:(BOOL)isAirplayActive;
// Creates the Master/Variant Playlist
- (NSString *)buildVariantPlaylist:(NSArray *)parsedMpd;
// Creates an HLS playlist that lists all of the TS segments within the stream.
// Requires an input stream to be used.
- (NSData *)buildChildPlaylist:(Stream *)stream;
// Obtains the actual data for the given stream.
- (void)loadStream:(Stream *)stream;
// XML Parsing of the DASH Manifest that populates the Stream object values.
- (void)processMpd:(NSURL *)mpdURL;
// XML Parsing of the DASH Manifest that populates the Stream object values, and then calls a custom
// block to handle the resulting Streams.
- (void)processMpd:(NSURL *)mpdURL
    withCompletion:(void (^)(NSArray<Stream *> *streams, NSError *error))completion;
// Re-creates the Streaming object.
// Used primarily when switching between AirPlay and non-Airplay usage.
- (void)restart:(BOOL)isAirplayActive;
// Destroys the Streaming object.
- (void)stop;
// Verifies all Streams have been processed and initiates a Notification to begin playack of the
// transmuxed HLS content.
- (void)streamReady:(Stream *)stream;

// Returns a HTTPResponse for the webserver to return data for the |method| and |path|.
// |connection| will be notified when that data is available.
- (NSObject<HTTPResponse> *)responseForMethod:(NSString *)method
                                         path:(NSString *)path
                                   connection:(HTTPConnection *)connection;
@end
