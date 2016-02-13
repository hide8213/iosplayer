#import <Foundation/Foundation.h>

#import "AppDelegate.h"
#import "Stream.h"

@interface MpdParser : NSObject <NSXMLParserDelegate>
@property(nonatomic, strong) NSMutableArray *streams;

- (id)initWithStreaming:(Streaming *)streaming
                mpdData:(NSData *)mpdData
                baseUrl:(NSURL *)baseUrl;

+ (void)deleteFilesInMpd:(NSURL *)mpdUrl;
+ (NSMutableArray *)parseMpdWithStreaming:(Streaming *)streaming
                                  mpdData:(NSData *)mpdData
                                  baseUrl:(NSURL *)baseUrl;
@end


