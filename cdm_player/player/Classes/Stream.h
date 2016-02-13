// Copyright 2015 Google Inc. All rights reserved.

#import "CdmWrapper.h"
#import "DashToHlsApi.h"

struct DashToHlsIndex;
struct DashToHlsSession;
@class Streaming;

// Object that contains an individual stream within an HLS playlist before
// being transmuxed to DASH content via the UDT. 
// Initialized via the Streaming object.
@interface Stream : NSObject
// Init method with corresponding Streaming object.
- (id)initWithStreaming:(Streaming *)streaming;
// Method that initiates the Transmuxing of content by passing DASH data.
// Data can be locally stored or retrived remotely.
- (BOOL)initialize:(NSData *)initializationData;
// Contains the bandwidth of the given stream.
@property NSUInteger bandwidth;
// Contains the codec of the given stream.
@property(strong) NSString *codecs;
// Stores the complete status of the stream.
@property BOOL done;
// Maintains the index (or count) of dash segments that will be used to
// determine how many TS segments will need to be created.
@property struct DashToHlsIndex *dashIndex;
// Tracks the amount of Streams by assigning an Index integer.
@property NSUInteger indexValue;
// Contains the byte range to be used for transmuxing.
@property(strong) NSDictionary *initialRange;
// Determines what path to take when Transmuxing.
@property BOOL isVideo;
// Video height.
@property NSUInteger height;
// Assigned name to be used when creating the output M3U8.
@property(strong) NSData *m3u8;
// MimeType of the stream (typically, but not limited to: video/mp4 or audio/mp4).
@property(strong) NSString *mimeType;
// Session to be used when Transmuxing with UDT (Dash Transmuxer).
@property struct DashToHlsSession *session;
// Streaming object that contains the Stream object.
@property(weak) Streaming *streaming;
// Video Width.
@property NSUInteger width;
// URL of the physical media file.
@property(strong) NSURL *url;

@end

