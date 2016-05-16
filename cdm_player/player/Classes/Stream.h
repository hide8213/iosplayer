// Copyright 2015 Google Inc. All rights reserved.

#import "CdmWrapper.h"
#import "LiveStream.h"
#import "UDTApi.h"

struct DashToHlsIndex;
struct DashToHlsSession;
@class Streaming;

// Object that contains an individual stream within an HLS playlist before
// being transmuxed to DASH content via the UDT.
// Initialized via the Streaming object.
@interface Stream : NSObject

typedef NS_ENUM(NSUInteger, DashMediaType) {
  SEGMENT_BASE = 0,
  SEGMENT_LIST_DURATION = 1,
  SEGMENT_LIST_TIMELINE,
  SEGMENT_TEMPLATE_DURATION,
  SEGMENT_TEMPLATE_TIMELINE,
};

// Init method with corresponding Streaming object.
- (id)initWithStreaming:(Streaming *)streaming;
// Method that initiates the Transmuxing of content by passing DASH data.
// Data can be locally stored or retrived remotely.
- (BOOL)initialize:(NSData *)initializationData;
// Actual duration of the segment, will not be populated until after the segment has been
// transmuxed. This value is in PTS clock (90khz)
@property(nonatomic) NSUInteger actualDurationInPts;
// Contains the bandwidth of the given stream.
@property NSUInteger bandwidth;
// Contains the codec of the given stream.
@property(strong) NSString *codecs;
// Stores the type of Dash template used.
@property DashMediaType dashMediaType;
// Stores the complete status of the stream.
@property BOOL done;
// Maintains the index (or count) of dash segments that will be used to
// determine how many TS segments will need to be created.
@property struct DashToHlsIndex *dashIndex;
// Video height.
@property NSUInteger height;
// Contains the byte range to be used for transmuxing.
@property(strong) NSDictionary *initialRange;
// Determines what path to take when Transmuxing.
@property BOOL isVideo;
// Indicates whether stream is live or on-demand.
@property BOOL isLive;
// Streaming object that contains the Stream object.
@property LiveStream *liveStream;
// Assigned name to be used when creating the output M3U8.
@property(strong) NSData *m3u8;
// Full duration of the clip (optional, may not be present in manifest).
@property(nonatomic) NSUInteger mediaPresentationDuration;
// MimeType of the stream (typically, but not limited to: video/mp4 or audio/mp4).
@property(strong) NSString *mimeType;
// Value of PSSH to be passed into UDT (Dash Transmuxer).
@property(strong) NSData *pssh;
// PTS of the segment, will not be populated until after the segment has been transmuxed.
// This value is in PTS clock (90khz)
@property(nonatomic) NSUInteger pts;
// Session to be used when Transmuxing with UDT (Dash Transmuxer).
@property struct DashToHlsSession *session;
// URL of the physical media file.
@property(strong) NSURL *sourceUrl;
// Streaming object that contains the Stream object.
@property(weak) Streaming *streaming;
// Index of the single stream in relation to all stream.
@property(nonatomic) NSUInteger streamIndex;
// Video Width.
@property NSUInteger width;

@end
