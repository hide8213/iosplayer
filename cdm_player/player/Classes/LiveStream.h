// Copyright 2015 Google Inc. All rights reserved.
// Object contained within a Stream object to store details for non-SegmentBase.
@interface LiveStream : NSObject

// All properties are optional and only stored if found within the manifest.
// Duration of Stream
@property NSUInteger duration;
// URL for the Init file, if present
@property NSURL *initializationUrl;
// Media File name property. May contain wildcards (i.e $Number$)
// See https://gpac.wp.mines-telecom.fr/mp4box/dash
@property NSString *mediaFileName;
// Determines how many segments to include beyond current playing segment.
@property NSUInteger minBufferTime;
// Minumum amount of time allowed before making another playlist request.
@property NSUInteger minimumUpdatePeriod;
// ID of the specific stream.
@property NSString *representationId;
// Retrieved or calculated duration of each segment within the stream.
@property float segmentDuration;
// Number of first segment to be used/created.
@property NSUInteger startNumber;
// Value pulled from the manifest to determine the length of the segments.
@property NSUInteger timescale;
// Determines how long to keep previously played segments in the playlist.
@property NSUInteger timeShiftBufferDepth;

@end

