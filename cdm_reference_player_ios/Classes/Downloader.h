
@class Downloader;

@protocol DownloadDelegate<NSObject>
@optional
- (void)updateDownloadProgress:(NSNumber *)progress file:(NSURL *)file;
- (void)startDownloading:(Downloader *)downloader file:(NSURL *)file;
- (void)finishedDownloading:(Downloader *)downloader file:(NSURL *)file initRange:(NSRange)range;
- (void)failedDownloading:(Downloader *)downloader file:(NSURL *)file error:(NSError *)error;
@end

@interface Downloader : NSObject<NSURLConnectionDataDelegate>
@property(nonatomic, weak) id<DownloadDelegate> delegate;
@property(nonatomic, strong) NSNumber *progress;

+ (instancetype)DownloaderWithUrl:(NSURL *)url
                             file:(NSURL *)file
                        initRange:(NSRange)initRange
                         delegate:(id<DownloadDelegate>)delegate;
+ (void)DownloadWithUrl:(NSURL *)url
                   file:(NSURL *)file
              initRange:(NSRange)initRange
               delegate:(id<DownloadDelegate>)delegate;

+ (NSData *)downloadPartialData:(NSURL *)url
                      range:(NSRange)range
                 completion:(void(^)(NSData *data, NSError *error))completion;
@end
