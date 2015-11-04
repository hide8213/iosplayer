#import "Mpd.h"

#import "AppDelegate.h"
#import "Streaming.h"

NSString *const kDashAdaptationSet = @"AdaptationSet";
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

@implementation Mpd

+ (NSArray *)parseMpd:(NSData *)mpd baseUrl:(NSURL *)baseUrl {
  NSMutableArray *resultArray = [NSMutableArray array];
  NSString *urlPrefix = [[baseUrl URLByDeletingLastPathComponent] absoluteString];
  NSError *error = nil;


  if (!urlPrefix) {
    urlPrefix = @"http://localhost/";
  }

  TBXML *manifestXml = [TBXML tbxmlWithXMLData:mpd error:&error];
  if (error) {
    NSLog(@"Error: %@\n", error);
    EXIT_FAILURE;
  }

  // Create TBXML Elements and walk the DOM to find the necessary values
  TBXMLElement *mpdXML = manifestXml.rootXMLElement;
  TBXMLElement *periodXML = [TBXML childElementNamed:kDashPeriod
                                       parentElement:mpdXML
                                               error:&error];
  TBXMLElement *adaptationXML = [TBXML childElementNamed:kDashAdaptationSet
                                           parentElement:periodXML
                                                   error:&error];
  do {
    // Extract Segment specific details: URL, Bandwidth, byte ranges, etc...
    TBXMLElement *representationXML = [TBXML childElementNamed:kDashRepresentation
                                                 parentElement:adaptationXML
                                                         error:&error];
    do {
      TBXMLElement *baseUrlXML = [TBXML childElementNamed:kDashRepresentationBaseUrl
                                            parentElement:representationXML
                                                    error:&error];
      NSString *baseUrl = [TBXML textForElement:baseUrlXML error:&error];
      TBXMLElement *segmentBaseXML = [TBXML childElementNamed:kDashSegmentBase
                                                parentElement:representationXML
                                                        error:&error];
      NSString *urlString = [baseUrl stringByReplacingOccurrencesOfString:@"&amp;"
                                                               withString:@"&"];
      // Handle relative file name paths by appending Manifest URL
      if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"]) {
        urlString = [urlPrefix stringByAppendingString:urlString];
      }

      [resultArray addObject:
       [MpdResult mpdResultWithUrl:[NSURL URLWithString:urlString]
                         initRange:[self getInitRangeFromElement:segmentBaseXML]]];
      // END Representation Loop
    } while ((representationXML = representationXML->nextSibling));
    // END AdaptionSet Loop
  } while ((adaptationXML = adaptationXML->nextSibling));
  return resultArray;
}

+ (NSRange)getInitRangeFromElement:(TBXMLElement *)segmentBaseXML {
  NSError *error = nil;
  NSString *indexRange = [TBXML valueOfAttributeNamed:kDashSegmentBaseIndexRange
                                           forElement:segmentBaseXML
                                                error:&error];
  NSArray *indexRangeValues = [indexRange componentsSeparatedByString:@"-"];
  NSUInteger endRange = [indexRangeValues[1] integerValue] + 1;

  TBXMLElement *segmentIndexRangeXML = [TBXML childElementNamed:kDashSegmentInitRange
                                                  parentElement:segmentBaseXML
                                                          error:&error];
  NSString *initRange = [TBXML valueOfAttributeNamed:@"range"
                                          forElement:segmentIndexRangeXML
                                               error:&error];
  NSArray *initRangeValues = [initRange componentsSeparatedByString:@"-"];
  NSUInteger startRange = [initRangeValues[0] integerValue];

  return NSMakeRange(startRange, endRange);
}

+ (void)deleteFilesInMpd:(NSURL *)mpdUrl {
  NSData *mpdData = [NSData dataWithContentsOfURL:mpdUrl];
  if (!mpdData) {
    NSLog(@"No mpdData from %@", mpdData);
    return;
  }

  NSArray *remoteUrls = [Mpd parseMpd:mpdData baseUrl:nil];
  NSFileManager *defaultFileManager = [NSFileManager defaultManager];
  for (MpdResult *mpdResult in remoteUrls) {
    NSURL *fileUrl = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
                      urlInDocumentDirectoryForFile:mpdResult.url.lastPathComponent];
    [defaultFileManager removeItemAtURL:fileUrl error:nil];
    NSLog(@"delete %@", fileUrl);
  }
  [defaultFileManager removeItemAtURL:mpdUrl error:nil];
  NSLog(@"delete %@", mpdUrl);
}

@end

@implementation MpdResult
+ (instancetype)mpdResultWithUrl:(NSURL *)url initRange:(NSRange)initRange {
  MpdResult *mpdResult = [[MpdResult alloc] init];
  if (mpdResult) {
    mpdResult.url = url;
    mpdResult.initRange = initRange;
  }
  return mpdResult;
}
@end
