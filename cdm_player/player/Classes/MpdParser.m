// Copyright 2015 Google Inc. All rights reserved.

#import "MpdParser.h"

#import <objc/message.h>
#import <objc/runtime.h>

NSString *const kDashAdaptationSet = @"AdaptationSet";
NSString *const kDashContentComponent = @"ContentComponent";
NSString *const kDashPeriod = @"Period";
NSString *const kDashRepresentation = @"Representation";
NSString *const kDashRepresentationBaseUrl = @"BaseURL";
NSString *const kDashRepresentationBW = @"bandwidth";
NSString *const kDashRepresentationCodec = @"codecs";
NSString *const kDashRepresentationHeight = @"height";
NSString *const kDashRepresentationMime = @"mimeType";
NSString *const kDashRepresentationWidth = @"width";
NSString *const kDashSegmentBase = @"SegmentBase";
NSString *const kDashSegmentBaseIndexRange = @"indexRange";
NSString *const kDashSegmentBaseInitializationRange = @"range";
NSString *const kDashSegmentInitRange = @"Initialization";
NSString *const kDashSegmentList = @"SegmentList";
NSString *const kDashSegmentListURL = @"SegmentURL";
NSString *const kDashSegmentTemplate = @"SegmentTemplate";
NSString *const kDashSegmentTimeline = @"SegmentTimeline";

NSString *const kAttrAudioSampleRate = @"audioSamplingRate";
NSString *const kAttrBandwidth = @"bandwidth";
NSString *const kAttrCodecs = @"codecs";
NSString *const kAttrContentType = @"contentType";
NSString *const kAttrDuration = @"duration";
NSString *const kAttrHeight = @"height";
NSString *const kAttrId = @"id";
NSString *const kAttrIndexRange = @"indexRange";
NSString *const kAttrLang = @"lang";
NSString *const kAttrMimeType = @"mimeType";
NSString *const kAttrMimeTypeMp4 = @"/mp4";
NSString *const kAttrNumChannels = @"numChannels";
NSString *const kAttrPssh = @"pssh";
NSString *const kAttrPsshCenc = @"cenc:pssh";
NSString *const kAttrSampleRate = @"sampleRate";
NSString *const kAttrWidth = @"width";

NSString *const kBoolNo = @"NO";
NSString *const kBoolYes = @"YES";
NSString *const kDashMediaType = @"dashMediaType";
NSString *const kDashToHlsString = @"DashToHls";
NSString *const kDashSeparator = @"-";
NSString *const kHttpString = @"http";
NSString *const kIsVideoString = @"isVideo";
NSString *const kRootUrl = @"rootUrl";
NSString *const kRangeLength = @"length";
NSString *const kRangeStart = @"startRange";
NSString *const kSlashesString = @"//";
NSString *const kStreamingString = @"Streaming";
NSString *const kVideoString = @"video";


@implementation MpdParser {
  NSString *_currentElement;
  NSUInteger _maxAudioBandwidth;
  NSUInteger _maxVideoBandwidth;
  NSMutableDictionary *_mpdDict;
  NSURL *_mpdUrl;
  NSInteger _offlineAudioIndex;
  NSInteger _offlineVideoIndex;
  NSXMLParser *_parser;
  BOOL _playOffline;
  BOOL _storeOffline;
  NSInteger _streamCount;
  Streaming *_streaming;
}

// Init methods.
- (id)initWithStreaming:(Streaming *)streaming
           storeOffline:(BOOL)storeOffline
                mpdData:(NSData *)mpdData
                baseUrl:(NSURL *)baseUrl {
  self = [super init];
  if (self) {
    _mpdDict = [[NSMutableDictionary alloc] init];
    _parser = [[NSXMLParser alloc] initWithData:mpdData];
    _mpdUrl = baseUrl;
    _streams = [[NSMutableArray alloc] init];
    _streaming = streaming;
    _storeOffline = storeOffline;
    if ([_mpdUrl isFileURL]) {
      _playOffline = YES;
    }
  }
  if (_parser) {
    [_parser setDelegate:self];
    [_parser parse];
  }
  return self;
}

// External methods to be used to begin parsing.
+ (NSArray *)parseMpdWithStreaming:(Streaming *)streaming
                           mpdData:(NSData *)mpdData
                           baseUrl:(NSURL *)baseUrl {
  return [[MpdParser alloc] initWithStreaming:streaming
                                 storeOffline:NO
                                      mpdData:mpdData
                                      baseUrl:baseUrl].streams;
}

+ (NSArray *)parseMpdForOffline:(NSData *)mpdData
                        baseUrl:(NSURL *)baseUrl {
  return [[MpdParser alloc] initWithStreaming:nil
                                 storeOffline:YES
                                      mpdData:mpdData
                                      baseUrl:baseUrl].streams;
}

#pragma mark NSXMLParser methods -- start

// Set stream counter to track the amout of streams found in the manifest.
- (void)parserDidStartDocument:(NSXMLParser *)parser {
  _streamCount = 0;
}

// XML Element found, being parsing.
- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)elementName
       namespaceURI:(NSString *)namespaceURI
      qualifiedName:(NSString *)qName
         attributes:(NSDictionary *)attributeDict {
  _currentElement = elementName;
  for (NSString *key in attributeDict) {
    NSString *value = [[attributeDict valueForKey:key]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // Check that value isnt blank.
    if (([value length] != 0)) {
      [_mpdDict setValue:value forKey:key];
      if ([key isEqualToString:kDashRepresentationMime]) {
        if ([value containsString:kVideoString]) {
          [_mpdDict setValue:kBoolYes forKey:kIsVideoString];
        } else {
          [_mpdDict setValue:kBoolNo forKey:kIsVideoString];
        }
      }
      if ([elementName hasPrefix:@"Segment"]) {
        if (![self setDashMediaType:elementName]) {
          [parser abortParsing];
        }
      }
    }
  }
}

// Characters found within an element that do not contain a specific key.
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
  if (string) {
    if ([string hasPrefix:kSlashesString]) {
        [_mpdDict setValue:string forKey:kRootUrl];
    }
    // Stores PSSH to dictionary
    if ([_currentElement isEqualToString:kAttrPsshCenc]) {
      [_mpdDict setValue:string forKey:kAttrPssh];
    }
    // Ignores values that contain two lines. If needed, modify as necessary.
    if (![string containsString:@"\n "]) {
      [_mpdDict setValue:string forKey:_currentElement];
    }
  }
}

// Finished parsing Element.
- (void)parser:(NSXMLParser *)parser
    didEndElement:(NSString *)elementName
     namespaceURI:(NSString *)namespaceURI
    qualifiedName:(NSString *)qName {
  if ([elementName isEqualToString:kDashRepresentation]) {
    // Only setup stream object when mimeType is MP4. Ignores all others.
    if ([[_mpdDict objectForKey:kAttrMimeType] containsString:kAttrMimeTypeMp4]) {
      if (![self setStreamProperties:elementName]) {
        [parser abortParsing];
      }
    }
  }
}

// If parsing fails, this error will be returned.
- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
  NSLog(@"\n::ERROR::Parse Failed: %@", parseError);
}


- (void)parserDidEndDocument:(NSXMLParser *)parser {

}

#pragma mark NSXMLParser methods -- end

// Look up aviailable properties from Stream object and populate the required values.
- (BOOL)setStreamProperties:(NSString *)elementName {
  Stream *stream = [[Stream alloc] initWithStreaming:_streaming];
  unsigned int numberOfProperties = 0;
  unsigned int propertyIndex = 0;
  objc_property_t *properties = class_copyPropertyList([Stream class], &numberOfProperties);
  for (propertyIndex = 0; propertyIndex < numberOfProperties; propertyIndex++) {
    objc_property_t property = properties[propertyIndex];
    [self setProperty:stream property:property];
  }
  // Stream Complete
  if (_storeOffline) {
    [self storeOfflineStream:stream];
  } else {
    [_streams addObject:stream];
     _streamCount++;
  }
  if ([self validateStreamAttributes:stream]) {
    return YES;
  }
  return NO;
}

// Check Property type and determine attribute.
- (NSString *)getPropertyType:(objc_property_t)property {
  const char *attribute = property_getAttributes(property);
  if (!attribute) {
    NSLog(@"\n::ERROR::Empty Property Attribute | Name: %@\n", property);
    return nil;
  }
  NSString *attributeString = [NSString stringWithUTF8String:attribute];
  NSArray *attributeArray = [attributeString componentsSeparatedByString:@","];
  NSString *attributeStripped = [[[attributeArray objectAtIndex:0] substringFromIndex:1]
                                     stringByReplacingOccurrencesOfString:@"\"" withString:@""];

  // Verify attribute values are valid.
  if (!attributeStripped || [attributeStripped length] == 0) {
    NSLog(@"\n::ERROR::Empty Property Attribute Character | Name: %@\n", property);
    return nil;
  }

  switch(attribute[1]) {
    case '@' : // NSString
      attributeString = [attributeStripped substringFromIndex:1];
      break;
    case 'I' : // NSUinteger 32-bit
    case 'Q' : // NSUinteger 64-bit
      attributeString = @"NSUInteger";
      break;
    case 'c' : // BOOL 32-bit
    case 'B' : // BOOL 64-bit
      attributeString = @"BOOL";
      break;
    case '^' : // Special Class
      attributeString = [[[attributeStripped substringFromIndex:2]
                              componentsSeparatedByString:@"="] firstObject];
      break;
    default:
      NSLog(@"No Property Matched: %c", attribute[1]);
      attributeString = nil;
      break;
  }
  return attributeString;
}

// Uses available property in Stream object and value when property and key match.
- (void)setProperty:(Stream *)stream property:(objc_property_t)property {
  NSString *propertyName = [NSString stringWithUTF8String:property_getName(property)];
  const char *attribute = property_getAttributes(property);
  NSString *attributeString = [NSString stringWithUTF8String:attribute];
  NSArray *attributeArray = [attributeString componentsSeparatedByString:@","];
  NSString *attributeStripped = [[[attributeArray objectAtIndex:0] substringFromIndex:1]
                                 stringByReplacingOccurrencesOfString:@"\"" withString:@""];
  NSString *propertyType = [attributeStripped substringFromIndex:1];
  switch(attribute[1]) {
    case '@' : // Char
      if ([propertyType isEqualToString:@"NSURL"]) {
        NSURL *value = [self setStreamUrl:[_mpdDict objectForKey:kDashRepresentationBaseUrl]];
        [stream setValue:value forKey:propertyName];
      }
      if ([propertyType isEqualToString:@"NSDictionary"]) {
        NSDictionary *value = [self setInitRange];
        [stream setValue:value forKey:propertyName];
      }
      if ([propertyType isEqualToString:@"NSData"]) {
        NSData *value = [[NSData alloc] init];
        if ([propertyName isEqualToString:@"pssh"]) {
          NSString *psshString = [_mpdDict objectForKey:@"cenc:pssh"];
          if (psshString) {
            value = [[NSData alloc] initWithBase64EncodedString:psshString
                                                        options:0];
          }
        }
        [stream setValue:value forKey:propertyName];
      }
      if ([propertyType isEqualToString:@"NSString"]) {
        NSString *value = [_mpdDict objectForKey:propertyName];
        [stream setValue:value forKey:propertyName];
      }
      if ([propertyType isEqualToString:@"LiveStream"]) {
        [self setLiveProperties:(Stream *)stream];
      }
      if ([propertyType isEqualToString:@"NSDate"]) {
        [stream setValue:[NSDate dateWithTimeIntervalSince1970:0] forKey:propertyName];
      }
      break;
    case 'I' : // NSUinteger 32-bit
    case 'Q' : // NSUinteger 64-bit
      if ([propertyName isEqualToString:@"streamIndex"]) {
        [stream setValue:[NSNumber numberWithInteger:_streamCount] forKey:propertyName];
      } else if ([propertyName isEqualToString:@"mediaPresentationDuration"]) {
        NSUInteger value = [self convertDurationToSeconds:[_mpdDict objectForKey:propertyName]];
        [stream setValue:[NSNumber numberWithInteger:value] forKey:propertyName];
      } else {
        NSUInteger value = [[_mpdDict objectForKey:propertyName] integerValue];
        [stream setValue:[NSNumber numberWithInteger:value] forKey:propertyName];
      }
      break;
    case 'c' : // BOOL 32-bit
    case 'B' : // BOOL 64-bit
      if (propertyName) {
        BOOL value = [[_mpdDict objectForKey:propertyName] boolValue];
        [stream setValue:[NSNumber numberWithBool:value] forKey:propertyName];
      }
      break;
    case '^' : // Special Class
      break;
    default:
      NSLog(@"No Property Matched");
      attributeString = nil;
      break;
  }
}

// Check each stream and store highest rates for video/audio.
- (void)storeOfflineStream:(Stream *)stream {
  // Look up higest bitrate
  if (stream.isVideo) {
    if (stream.bandwidth > _maxVideoBandwidth) {
      if (_maxVideoBandwidth) {
        [_streams replaceObjectAtIndex:_offlineVideoIndex withObject:stream];
      } else {
        [_streams addObject:stream];
        _offlineVideoIndex = _streamCount;
      }
      _maxVideoBandwidth = stream.bandwidth;
    }
  } else {
    if (stream.bandwidth > _maxAudioBandwidth) {
      if (_maxAudioBandwidth) {
        [_streams replaceObjectAtIndex:_offlineAudioIndex withObject:stream];
      } else {
        [_streams addObject:stream];
        _offlineAudioIndex = _streamCount;
      }
      _maxAudioBandwidth = stream.bandwidth;
    }
  }
}

// Ensure all properties are populated from the MPD, otherwise return false.
- (BOOL)validateStreamAttributes:(Stream *)stream {
  BOOL attributeExists = YES;
  unsigned int numberOfProperties, i;
  objc_property_t *properties = class_copyPropertyList([Stream class], &numberOfProperties);
  for (i = 0; i < numberOfProperties; i++) {
    objc_property_t property = properties[i];
    const char *propName = property_getName(property);
    if (propName) {
      NSString *propertyName = [NSString stringWithUTF8String:propName];
      NSString *propertyType = [self getPropertyType:property];
      if (![propertyType containsString:kDashToHlsString]) {
        if (![propertyName isEqualToString:@"pssh"]) {
          if (![propertyType isEqualToString:kStreamingString]) {
            NSString *propertyValue = [stream valueForKey:propertyName];
            if (!propertyValue) {
              NSLog(@"\n::ERROR::Property Not Set for Stream\n"
                    @"  Name: %@ | Type: %@", propertyName, propertyType);
              attributeExists = NO;
            }
          }
        }
      }
    }
  }
  return attributeExists;
}

// Determine what type of Dash Template is being used.
- (BOOL)setDashMediaType:(NSString *)elementName {
  // SegmentBase
  if ([elementName isEqualToString:kDashSegmentBase]) {
    [_mpdDict setValue:@(SEGMENT_BASE)
                forKey:kDashMediaType];
  }
  // SegmentList w/Duration
  if ([elementName isEqualToString:kDashSegmentList]) {
    [_mpdDict setValue:@(SEGMENT_LIST_DURATION)
                forKey:kDashMediaType];
  }
  // SegmentTemplate w/Duration
  if ([elementName isEqualToString:kDashSegmentTemplate]) {
    [_mpdDict setValue:@(SEGMENT_TEMPLATE_DURATION)
                forKey:kDashMediaType];
  }
  // SegmentTimeline
  if ([elementName isEqualToString:kDashSegmentTimeline]) {
    // SegmentTimeline is sub-section to SegmentList
    if ([[_mpdDict valueForKey:kDashMediaType] isEqual:@(SEGMENT_LIST_DURATION)]) {
      [_mpdDict setValue:[NSNumber numberWithUnsignedInteger:SEGMENT_LIST_TIMELINE]
                  forKey:kDashMediaType];
    }
    // SegmentTimeline is sub-section to SegmentTemplate
    if ([[_mpdDict valueForKey:kDashMediaType] isEqual:@(SEGMENT_TEMPLATE_DURATION)]) {
      [_mpdDict setValue:[NSNumber numberWithUnsignedInteger:SEGMENT_TEMPLATE_TIMELINE]
                  forKey:kDashMediaType];
    }
  }
  if ([_mpdDict objectForKey:kDashMediaType]) {
    return YES;
  }
  // DashMediaType has not been set.
  return NO;
}

// Extract ranges from Dictionary, then parse and create Initialization Range.
- (NSDictionary *)setInitRange {
  NSString *range = [_mpdDict objectForKey:kDashSegmentBaseInitializationRange];
  [_mpdDict removeObjectForKey:kDashSegmentBaseInitializationRange];
  NSArray *rangeValues = [range componentsSeparatedByString:kDashSeparator];
  NSNumber *startRange = [NSNumber numberWithInteger:[rangeValues[0] intValue]];
  NSString *indexRange = [_mpdDict objectForKey:kAttrIndexRange];
  [_mpdDict removeObjectForKey:kAttrIndexRange];
  NSArray *indexRangeValues = [indexRange componentsSeparatedByString:kDashSeparator];

  NSNumber *length = [NSNumber numberWithInteger:0];
  if (indexRangeValues && rangeValues) {
    // Add 1 to avoid overlap in bytes to the length.
    length = [NSNumber numberWithInteger:([indexRangeValues[1] intValue] + 1)];
    if ([startRange intValue] >= [length intValue]) {
      NSLog(@"\n::ERROR::Start Range is greater than Length: %d, %d", [startRange intValue],
                                                                      [length intValue]);
      return nil;
    }
    if ([length intValue] == 0) {
      NSLog(@"\n::ERROR::Length is not valid: %d", [length intValue]);
    }
  }
  NSDictionary *initialRange = [[NSDictionary alloc] initWithObjectsAndKeys:startRange,
                                    kRangeStart, length, kRangeLength, nil];
  return initialRange;
}

// Parse MPEG Dash duration format and return seconds.
// https://en.wikipedia.org/wiki/ISO_8601#Durations
// TODO(seawardt): Implement support for Leap year and months that are not 30 days.
- (NSUInteger)convertDurationToSeconds:(NSString *)string {
  if (!string) {
    return 0;
  }
  NSString *pattern = @"^P(?:(\\d{0,2})Y)?(?:(\\d{0,2})M)?(?:(\\d{0,2})D)"
                      @"?.(?:(\\d{0,2})H)?(?:(\\d{0,2})M)?(?:(\\d*[.]?\\d+)S)?$";
  NSRange searchRange = NSMakeRange(0, [string length]);
  NSError *error = nil;
  NSUInteger duration = 0;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:0
                                                                           error:&error];
  int years = 0;
  int months = 0;
  int days = 0;
  int hours = 0;
  int minutes = 0;
  float seconds = 0;
  NSArray *matches = [regex matchesInString:string options:0 range:searchRange];
  for (NSTextCheckingResult *match in matches) {
    NSString* matchText = [string substringWithRange:[match range]];
    NSRange matchGroup1 = [match rangeAtIndex:1];
    NSRange matchGroup2 = [match rangeAtIndex:2];
    NSRange matchGroup3 = [match rangeAtIndex:3];
    NSRange matchGroup4 = [match rangeAtIndex:4];
    NSRange matchGroup5 = [match rangeAtIndex:5];
    NSRange matchGroup6 = [match rangeAtIndex:6];

    years = matchGroup1.length > 0 ? [[string substringWithRange:matchGroup1] intValue] : 0;
    months = matchGroup2.length > 0 ? [[string substringWithRange:matchGroup2] intValue] : 0;
    days = matchGroup3.length > 0 ? [[string substringWithRange:matchGroup3] intValue] : 0;
    hours = matchGroup4.length > 0 ? [[string substringWithRange:matchGroup4] intValue]: 0;
    minutes = matchGroup5.length > 0 ? [[string substringWithRange:matchGroup5] intValue]: 0;
    seconds = matchGroup6.length > 0 ? [[string substringWithRange:matchGroup6] floatValue]: 0;
  }
  duration = (60 * 60 * 24 * 365) * years +
             (60 * 60 * 24 * 30) * months +
             (60 * 60 * 24) * days +
             (60 * 60) * hours +
             60 * minutes +
             seconds;
  return duration;
}

// Builds Stream.LiveStream object. May be used for Non-Live streams depending on Manifest.
- (void)setLiveProperties:(Stream *)stream {
  if ([_mpdDict objectForKey:kDashMediaType] == [NSNumber numberWithUnsignedInteger:SEGMENT_BASE]) {
    // Ignore if SegmentBase manifest is being used.
    return;
  }
  stream.liveStream.duration = [[_mpdDict valueForKey:@"duration"] integerValue];
  stream.liveStream.initializationUrl =
      [self setStreamUrl:[_mpdDict valueForKey:@"initialization"]];
  stream.liveStream.mediaFileName = [_mpdDict valueForKey:@"media"];
  stream.liveStream.minBufferTime =
      [self convertDurationToSeconds:[_mpdDict valueForKey:@"minBufferTime"]];
  stream.liveStream.minimumUpdatePeriod = [_mpdDict valueForKey:@"minimumUpdatePeriod"];
  stream.liveStream.representationId = [_mpdDict valueForKey:@"id"];
  stream.liveStream.startNumber = [[_mpdDict valueForKey:@"startNumber"] integerValue];
  stream.liveStream.timescale = [[_mpdDict valueForKey:@"timescale"] integerValue];
  stream.liveStream.timeShiftBufferDepth = [_mpdDict valueForKey:@"timeShiftBufferDepth"];
  stream.liveStream.segmentDuration = (float)stream.liveStream.duration /
                                      (float)stream.liveStream.timescale;
}

// Adds a complete URL for each stream.
- (NSURL *)setStreamUrl:(NSString *)urlString {
  // BaseURL and Initialization URLs were not found. Use media URL then.
  if (!urlString) {
    urlString = [_mpdDict objectForKey:@"media"];
  }
  if (_playOffline) {
    return [(AppDelegate *)[[UIApplication sharedApplication] delegate]
            urlInDocumentDirectoryForFile:urlString.lastPathComponent];
  }
  // URL is already complete. Move on.
  if ([urlString containsString:kHttpString]) {
    return [[NSURL alloc] initWithString:urlString];
  }
  NSString *rootUrl = [_mpdDict objectForKey:kRootUrl];
  if (rootUrl) {
    // The root URL can start with // as opposed to a scheme, appends http(s)
    if ([rootUrl rangeOfString:kHttpString].location == NSNotFound) {
      rootUrl = [_mpdUrl.scheme stringByAppendingFormat:@":%@", rootUrl];
    }
    // Removes trailing path component (if present).
    NSURL *url = [[NSURL alloc] initWithString:rootUrl];
    if ([url pathExtension]) {
      url = [url URLByDeletingLastPathComponent];
    }
    return [url URLByAppendingPathComponent:urlString];
  }
  // Removes query arguments to properly append the last component path.
  NSURLComponents *urlComponents = [[NSURLComponents alloc] initWithURL:_mpdUrl
                                                resolvingAgainstBaseURL:YES];
  urlComponents.query = nil;
  urlComponents.fragment = nil;
  _mpdUrl = urlComponents.URL;
  return [[_mpdUrl URLByDeletingLastPathComponent] URLByAppendingPathComponent:urlString];
}

// Offline usage to delete files listed in MPD.
+ (void)deleteFilesInMpd:(NSURL *)mpdUrl {
  NSData *mpdData = [NSData dataWithContentsOfURL:mpdUrl];
  if (!mpdData) {
    NSLog(@"\n::ERROR:: No mpdData from %@", mpdData);
    return;
  }
  NSError *error = nil;
  NSArray *remoteUrls = [MpdParser parseMpdForOffline:mpdData
                                              baseUrl:mpdUrl];
  NSFileManager *defaultFileManager = [NSFileManager defaultManager];
  for (Stream *stream in remoteUrls) {
    NSURL *fileUrl = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
                      urlInDocumentDirectoryForFile:stream.sourceUrl.lastPathComponent];
    [defaultFileManager removeItemAtURL:fileUrl error:&error];
    if (error) {
      NSLog(@"\n::ERROR::Unable to delete existing file.\n" "Error: %@ %ld %@",
            [error domain], (long)[error code], [[error userInfo] description]);
      return;
    }
    NSLog(@"\n::INFO:: Deleting: %@", fileUrl);
  }
  [defaultFileManager removeItemAtURL:mpdUrl error:nil];
}

@end
