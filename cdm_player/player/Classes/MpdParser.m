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
NSString *const kAttrNumChannels = @"numChannels";
NSString *const kAttrSampleRate = @"sampleRate";
NSString *const kAttrWidth = @"width";

NSString *const kBoolNo = @"NO";
NSString *const kBoolYes = @"YES";
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

- (void)parserDidStartDocument:(NSXMLParser *)parser {
  _streamCount = 0;
}

- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)elementName
       namespaceURI:(NSString *)namespaceURI
      qualifiedName:(NSString *)qName
         attributes:(NSDictionary *)attributeDict {
  _currentElement = elementName;
  for (id key in attributeDict) {
    NSString *value = [[attributeDict objectForKey:key]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // Check that value isnt blank.
    if (!([value length] == 0)) {
      [_mpdDict setValue:value forKey:key];
      if ([key isEqualToString:kDashRepresentationMime]) {
         if ([value containsString:kVideoString]) {
           [_mpdDict setValue:kBoolYes forKey:kIsVideoString];
         } else {
           [_mpdDict setValue:kBoolNo forKey:kIsVideoString];
         }
      }
    }
  }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
  if (string) {
    if ([string hasPrefix:kSlashesString]) {
      [_mpdDict setValue:string forKey:kRootUrl];
    }
    if (![string containsString:@"\n "]) {
      [_mpdDict setValue:string forKey:_currentElement];
    }
  }
}

- (void)parser:(NSXMLParser *)parser
    didEndElement:(NSString *)elementName
     namespaceURI:(NSString *)namespaceURI
    qualifiedName:(NSString *)qName {
  if ([elementName isEqualToString:kDashRepresentation]) {
    if (![self setStreamProperties:elementName]) {
      [parser abortParsing];
    }
  }
}

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

- (NSString *)getPropertyType:(objc_property_t)property {
  const char *attribute = property_getAttributes(property);
  NSString *attributeString = [NSString stringWithUTF8String:attribute];
  NSArray *attributeArray = [attributeString componentsSeparatedByString:@","];
  NSString *attributeStripped = [[[attributeArray objectAtIndex:0] substringFromIndex:1]
                                     stringByReplacingOccurrencesOfString:@"\"" withString:@""];

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
      NSLog(@"No Property Matched");
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
        NSURL *value = [self setStreamUrl];
        [stream setValue:value forKey:propertyName];
      }
      if ([propertyType isEqualToString:@"NSDictionary"]) {
        NSDictionary *value = [self setInitRange];
        [stream setValue:value forKey:propertyName];
      }
      if ([propertyType isEqualToString:@"NSData"]) {
        NSData *value = [[NSData alloc] init];
        [stream setValue:value forKey:propertyName];
      }
      if ([propertyType isEqualToString:@"NSString"]) {
        NSString *value = [_mpdDict objectForKey:propertyName];
        [stream setValue:value forKey:propertyName];
      }
      break;
    case 'I' : // NSUinteger 32-bit
    case 'Q' : // NSUinteger 64-bit
      if ([propertyName isEqualToString:@"indexValue"]) {
        [stream setValue:[NSNumber numberWithInteger:_streamCount] forKey:propertyName];
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
        if (![propertyType isEqualToString:kStreamingString]) {
          NSString *propertyValue = [stream valueForKey:propertyName];
          if (!propertyValue) {
            NSLog(@"\n::ERROR::Property Not Set for Stream\n"
                  @"  Name: %@ | Type: %@ | Value: %@", propertyName, propertyType, propertyValue);
            attributeExists = NO;
          }
        }
      }
    }
  }
  return attributeExists;
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
  if (!indexRangeValues || !rangeValues) {
    return nil;
  }
  // Add 1 to avoid overlap in bytes to the length.
  NSNumber *length = [NSNumber numberWithInteger:([indexRangeValues[1] intValue] + 1)];
  if ([startRange intValue] >= [length intValue]) {
    NSLog(@"\n::ERROR::Start Range is greater than Length: %d, %d", [startRange intValue],
                                                                    [length intValue]);
    return nil;
  }
  if ([length intValue] == 0) {
    NSLog(@"\n::ERROR::Length is not valid: %d", [length intValue]);
    return nil;
  }
  NSDictionary *initialRange = [[NSDictionary alloc] initWithObjectsAndKeys:startRange,
                                    kRangeStart, length, kRangeLength, nil];
  return initialRange;
}

// Adds a complete URL for each stream.
- (NSURL *)setStreamUrl {
  NSString *string = [_mpdDict objectForKey:kDashRepresentationBaseUrl];
  if (_playOffline) {
    return [(AppDelegate *)[[UIApplication sharedApplication] delegate]
            urlInDocumentDirectoryForFile:string.lastPathComponent];
  }
  // URL is already complete. Move on.
  if ([string containsString:kHttpString]) {
    return [[NSURL alloc] initWithString:string];
  }
  NSString *rootUrl = [_mpdDict objectForKey:kRootUrl];
  if (rootUrl) {
    // The root URL can start with // as opposed to a scheme, appends http(s)
    if ([rootUrl rangeOfString:kHttpString].location == NSNotFound) {
      rootUrl = [_mpdUrl.scheme stringByAppendingFormat:@":%@", rootUrl];
    }
    return [[[NSURL alloc] initWithString:rootUrl] URLByAppendingPathComponent:string];
  }
  // Removes query arguments to properly append the last component path.
  NSURLComponents *urlComponents = [[NSURLComponents alloc] initWithURL:_mpdUrl
                                                resolvingAgainstBaseURL:YES];
  urlComponents.query = nil;
  urlComponents.fragment = nil;
  _mpdUrl = urlComponents.URL;
  return [[_mpdUrl URLByDeletingLastPathComponent] URLByAppendingPathComponent:string];
}

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
                      urlInDocumentDirectoryForFile:stream.url.lastPathComponent];
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
