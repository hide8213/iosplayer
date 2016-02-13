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

@implementation MpdParser {
  NSString *_currentElement;
  NSXMLParser *_parser;
  NSMutableDictionary *_mpdDict;
  NSURL *_mpdUrl;
  BOOL _offline;
  NSInteger _streamCount;
  Streaming *_streaming;
}

- (id)initWithStreaming:(Streaming *)streaming
                mpdData:(NSData *)mpdData
                baseUrl:(NSURL *)baseUrl {
  self = [super init];
  if (self) {
    _mpdDict = [[NSMutableDictionary alloc] init];
    _parser = [[NSXMLParser alloc] initWithData:mpdData];
    _mpdUrl = baseUrl;
    _streams = [[NSMutableArray alloc] init];
    _streaming = streaming;
    if ([_mpdUrl isFileURL]) {
      _offline = YES;
    }

  }
  if (_parser) {
    [_parser setDelegate:self];
    [_parser parse];
  } else {
    self = nil;
  }
  return self;
}

+ (NSMutableArray *)parseMpdWithStreaming:(Streaming *)streaming
                                  mpdData:(NSData *)mpdData
                                  baseUrl:(NSURL *)baseUrl {
  MpdParser *mpdParser = [[MpdParser alloc] initWithStreaming:streaming
                                                      mpdData:mpdData
                                                      baseUrl:baseUrl];
  return mpdParser.streams;
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
    NSString *value = [attributeDict objectForKey:key];
    // Check that value isnt blank.
    if (![[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
         length] == 0) {
      [_mpdDict setValue:value forKey:key];
      if ([key isEqualToString:@"mimeType"]) {
         if ([value containsString:@"video"]) {
           [_mpdDict setValue:@"YES" forKey:@"isVideo"];
         } else {
           [_mpdDict setValue:@"NO" forKey:@"isVideo"];
         }
      }
    }
  }
}

- (void)parser:(NSXMLParser *)parser
    foundCharacters:(NSString *)string {
  if (string) {
    if ([string hasPrefix:@"//"]) {
      [_mpdDict setValue:string forKey:@"rootUrl"];
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

static const char *getPropertyType(objc_property_t property) {
  const char *attributes = property_getAttributes(property);
  char buffer[1 + strlen(attributes)];
  strcpy(buffer, attributes);
  char *state = buffer, *attribute;
  while ((attribute = strsep(&state, ",")) != NULL) {
    if (attribute[0] == 'T' && attribute[1] != '@') {
      NSString *name = [[NSString alloc] initWithBytes:attribute + 1 length:strlen(attribute) - 1 encoding:NSASCIIStringEncoding];
      return (const char *)[name cStringUsingEncoding:NSASCIIStringEncoding];
    }
    else if (attribute[0] == 'T' && attribute[1] == '@' && strlen(attribute) == 2) {
      // it's an ObjC id type:
      return "id";
    }
    else if (attribute[0] == 'T' && attribute[1] == '@') {
      // it's another ObjC object type:
      NSString *name = [[NSString alloc] initWithBytes:attribute + 3 length:strlen(attribute) - 4 encoding:NSASCIIStringEncoding];
      return (const char *)[name cStringUsingEncoding:NSASCIIStringEncoding];
    }
  }
  return "";
}

// Look up aviailable properties from Stream object and populate the required values.
- (BOOL)setStreamProperties:(NSString *)elementName {
  Stream *stream = [[Stream alloc] initWithStreaming:_streaming];
  NSMutableDictionary *results = [[NSMutableDictionary alloc] init];

  unsigned int numberOfProperties, i;
  objc_property_t *properties = class_copyPropertyList([Stream class], &numberOfProperties);
  for (i = 0; i < numberOfProperties; i++) {
    objc_property_t property = properties[i];
    const char *propName = property_getName(property);
    if (propName) {
      const char *propType = getPropertyType(property);
      NSString *propertyName = [NSString stringWithUTF8String:propName];
      NSString *propertyType = [NSString stringWithUTF8String:propType];
      [results setObject:propertyType forKey:propertyName];
      [self setProperty:stream name:propertyName type:propertyType];
    }
  }
  // Stream Complete
  [_streams addObject:stream];
  _streamCount++;
  if ([self validateStreamAttributes:stream]) {
    return YES;
  }
  return NO;
}

// Uses available property in Stream object and value when property and key match.
- (void)setProperty:(Stream *)stream name:(NSString *)name type:(NSString *)type {
  NSString *selectorName = [NSString stringWithFormat:@"set%@%@:",
                            [[name substringToIndex:1] uppercaseString],
                            [name substringFromIndex:1]];
  SEL selector = NSSelectorFromString(selectorName);
  if ([stream respondsToSelector:selector]) {
    IMP imp = [stream methodForSelector:selector];
    // TODO(seawardt): Improve setProperty to be more efficient and cleaner.
    if ([type isEqualToString:@"NSString"]) {
      // Property type is NSString.
      NSString *value = [_mpdDict objectForKey:name];
      void (*func)(id, SEL, NSString *) = (void *)imp;
      func(stream, selector, value);
    } else if ([type isEqualToString:@"Q"] || [type isEqualToString:@"I"]) {
      // Property type is Integer (aka Q).
      [_mpdDict setValue:[NSNumber numberWithInteger:_streamCount] forKey:@"indexValue"];
      NSUInteger value = [[_mpdDict objectForKey:name] integerValue];
      void (*func)(id, SEL, NSUInteger) = (void *)imp;
      func(stream, selector, value);
    } else if ([type isEqualToString:@"B"] || [type isEqualToString:@"c"]) {
      // Property type is BOOL (aka c).
      [_mpdDict setValue:@"NO" forKey:@"done"];
      BOOL value = [[_mpdDict objectForKey:name] boolValue];
      void (*func)(id, SEL, BOOL) = (void *)imp;
      func(stream, selector, value);
    } else if ([type isEqualToString:@"NSURL"]) {
      // Property type is NSURL.
      NSURL *value = [self setStreamUrl];
      void (*func)(id, SEL, NSURL *) = (void *)imp;
      func(stream, selector, value);
    } else if ([type isEqualToString:@"NSDictionary"]) {
      // Property type is NSDictionary.
      NSDictionary *value = [self setInitRange];
      void (*func)(id, SEL, NSDictionary *) = (void *)imp;
      func(stream, selector, value);
    } else if ([type isEqualToString:@"NSData"]) {
      // Property type is NSData.
      NSData *value = [[NSData alloc] init];
      void (*func)(id, SEL, NSData *) = (void *)imp;
      func(stream, selector, value);
    } 
  }
}

// Ensure all properties are populated from the MPD, otherwise return false.
- (BOOL)validateStreamAttributes:(Stream *)stream {
  BOOL attributeExists = YES;
  NSMutableDictionary *results = [[NSMutableDictionary alloc] init];
  unsigned int numberOfProperties, i;
  objc_property_t *properties = class_copyPropertyList([Stream class], &numberOfProperties);
  for (i = 0; i < numberOfProperties; i++) {
    objc_property_t property = properties[i];
    const char *propName = property_getName(property);
    if (propName) {
      const char *propType = getPropertyType(property);
      NSString *propertyName = [NSString stringWithUTF8String:propName];
      NSString *propertyType = [NSString stringWithUTF8String:propType];
      if (![propertyType containsString:@"DashToHls"]) {
        if (![propertyType isEqualToString:@"Streaming"]) {
          NSString *propertyValue = [stream valueForKey:propertyName];
          if (!propertyValue) {
            NSLog(@"\n::ERROR::Property Not Set for Stream\n"
                  @"Name: %@ | Type: %@ | Value: %@", propertyName, propertyType, propertyValue);
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
  NSString *range = [_mpdDict objectForKey:@"range"];
  [_mpdDict removeObjectForKey:@"range"];
  NSArray *rangeValues = [range componentsSeparatedByString:@"-"];
  NSNumber *startRange = [NSNumber numberWithInteger:[rangeValues[0] intValue]];
  NSString *indexRange = [_mpdDict objectForKey:@"indexRange"];
  [_mpdDict removeObjectForKey:@"indexRange"];
  NSArray *indexRangeValues = [indexRange componentsSeparatedByString:@"-"];
  if (!indexRangeValues || !rangeValues) {
    return nil;
  }
  // Add 1 to avoid overlap in bytes to the length.
  NSNumber *length = [NSNumber numberWithInteger:([indexRangeValues[1] intValue] + 1)];
  if ([startRange intValue] >= [length intValue]) {
    NSLog(@"\n::ERROR::Start Range is greater than Length: %d, %d", [startRange intValue], [length intValue]);
    return nil;
  }
  if ([length intValue] == 0) {
    NSLog(@"\n::ERROR::Length is not valid: %d", [length intValue]);
    return nil;
  }
  NSDictionary *initialRange = [[NSDictionary alloc] initWithObjectsAndKeys:startRange,
                                    @"startRange", length, @"length", nil];
  return initialRange;
}

// Adds a complete URL for each stream.
- (NSURL *)setStreamUrl {
  NSURL *url = nil;
  NSString *string = [_mpdDict objectForKey:@"BaseURL"];
  if (_offline) {
    return [(AppDelegate *)[[UIApplication sharedApplication] delegate]
            urlInDocumentDirectoryForFile:string.lastPathComponent];
  }
  // URL is already complete. Move on.
  if ([string containsString:@"http"]) {
    return [[NSURL alloc] initWithString:string];
  }
  NSString *rootUrl = [_mpdDict objectForKey:@"rootUrl"];
  if (rootUrl) {
    // The root URL can start with // as opposed to a scheme, appends http(s)
    if ([rootUrl rangeOfString:@"http"].location == NSNotFound) {
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
  NSMutableArray *remoteUrls = [MpdParser parseMpdWithStreaming:nil
                                                        mpdData:mpdData
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
