#import "TBXML.h"

@interface Mpd : NSObject

extern NSString *const kDashAdaptationSet;
extern NSString *const kDashPeriod;
extern NSString *const kDashRepresentation;
extern NSString *const kDashRepresentationBaseUrl;
extern NSString *const kDashRepresentationBW;
extern NSString *const kDashRepresentationCodec;
extern NSString *const kDashRepresentationHeight;
extern NSString *const kDashRepresentationMime;
extern NSString *const kDashRepresentationWidth;
extern NSString *const kDashSegmentBase;
extern NSString *const kDashSegmentBaseIndexRange;
extern NSString *const kDashSegmentBaseInitializationRange;
extern NSString *const kDashSegmentInitRange;

+ (NSArray *)parseMpd:(NSData *)mpd baseUrl:(NSURL *)baseUrl;
+ (void)deleteFilesInMpd:(NSURL *)mpd;
+ (NSRange)getInitRangeFromElement:(TBXMLElement *)segmentBaseXML;
@end

@interface MpdResult : NSObject
+ (instancetype)mpdResultWithUrl:(NSURL *)url initRange:(NSRange)initRange;
@property(nonatomic, strong) NSURL *url;
@property NSRange initRange;
@end