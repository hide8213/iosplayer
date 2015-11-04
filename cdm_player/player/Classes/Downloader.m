#import "Downloader.h"

#import "AppDelegate.h"
#import "Mpd.h"

static NSMutableArray *sDownloaders;

@interface Downloader()
@property(nonatomic, strong) NSURLConnection *connection;
@property(nonatomic) NSRange initRange;
@property(nonatomic, strong) NSURL *file;
@property(nonatomic, strong) NSFileHandle *fileHandle;
@property(nonatomic) BOOL isMpd;
@property(nonatomic, strong) NSURL *url;
@end

@implementation Downloader {
  NSUInteger _expectedBytes;
  NSUInteger _receivedBytes;
}

+ (instancetype)DownloaderWithUrl:(NSURL *)url
                             file:(NSURL *)file
                        initRange:(NSRange)initRange
                         delegate:(id<DownloadDelegate>)delegate{
  Downloader *downloader = [[Downloader alloc] init];
  if (downloader) {
    downloader.delegate = delegate;
    downloader.url = url;
    downloader.initRange = initRange;
    downloader.file = file;
    NSString *fileString = [NSString stringWithUTF8String:file.fileSystemRepresentation];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createFileAtPath:fileString contents:[NSData data] attributes:nil]) {
      NSLog(@"Error was code: %d - message: %s", errno, strerror(errno));
    }
    downloader.isMpd = [file.pathExtension isEqualToString:@"mpd"];
    downloader.fileHandle = [NSFileHandle fileHandleForWritingAtPath:fileString];

    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:90];
    downloader.connection = [[NSURLConnection alloc] initWithRequest:request
                                                            delegate:downloader
                                                    startImmediately:NO];
    [downloader.connection scheduleInRunLoop:[NSRunLoop mainRunLoop]
                                     forMode:NSDefaultRunLoopMode];
    if ([delegate respondsToSelector:@selector(startDownloading:file:)]) {
      [delegate startDownloading:downloader file:file];
    }
    [downloader.connection start];
  }
  return downloader;
}

+ (void)DownloadWithUrl:(NSURL *)url
                   file:(NSURL *)file
              initRange:(NSRange)initRange
              delegate:(id<DownloadDelegate>)delegate {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sDownloaders = [NSMutableArray array];
  });

  @synchronized(sDownloaders) {
    [sDownloaders addObject:[Downloader DownloaderWithUrl:url
                                                     file:file
                                                initRange:initRange
                                                 delegate:delegate]];
  }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
  _expectedBytes = [response expectedContentLength];
}

- (void)connection:(NSURLConnection *)connection
    didReceiveData:(NSData *)data {
  [_fileHandle writeData:data];
  _receivedBytes += [data length];
  _progress = [NSNumber numberWithFloat:((float)_receivedBytes)/((float)_expectedBytes)];
  if ([_delegate respondsToSelector:@selector(updateDownloadProgress:file:)]) {
    [_delegate updateDownloadProgress:_progress file:_file];
  }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
  if ([_delegate respondsToSelector:@selector(failedDownloading:file:error:)]) {
    [_delegate failedDownloading:self file:_file error:error];
  }
  @synchronized(sDownloaders) {
    [sDownloaders removeObject:self];
  }
}

- (void)downloadUrlArray:(NSArray *)urlArray {
  for (MpdResult *mpdResult in urlArray) {
    NSURL *fileUrl = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
        urlInDocumentDirectoryForFile:mpdResult.url.lastPathComponent];
    [Downloader DownloadWithUrl:mpdResult.url
                           file:fileUrl
                      initRange:mpdResult.initRange
                       delegate:_delegate];
  }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  [_fileHandle closeFile];
  if (_isMpd) {
    NSData *mpd = [NSData dataWithContentsOfURL:_file];
    [self downloadUrlArray:[Mpd parseMpd:mpd baseUrl:_url]];
  }
  if ([_delegate respondsToSelector:@selector(finishedDownloading:file:initRange:)]) {
    [_delegate finishedDownloading:self file:_file initRange:_initRange];
  }
  @synchronized(sDownloaders) {
    [sDownloaders removeObject:self];
  }
}

// completion can be nil and it will run sync.
+ (NSData *)downloadPartialData:(NSURL *)url
                          range:(NSRange)range
                     completion:(void(^)(NSData *data, NSError *error))completion {
  NSError *error = nil;
  if ([url isFileURL]) {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:&error];
    if (error) {
      if (completion) {
        completion(nil, error);
      }
      return nil;
    }
    [fileHandle seekToFileOffset:range.location];
    NSData *data = [fileHandle readDataOfLength:range.length];
    if (completion) {
      completion(data, nil);
    }
    return data;
  } else {
    NSMutableURLRequest *request = [NSMutableURLRequest
                                    requestWithURL:url
                                    cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                    timeoutInterval:5];
    NSString *byteRangeString = [NSString stringWithFormat:@"bytes=%lu-%lu",
                                 (unsigned long)range.location,
                                 (unsigned long)(range.location + range.length)];
    [request setValue:byteRangeString forHTTPHeaderField:@"Range"];
    if (completion) {
      [NSURLConnection sendAsynchronousRequest:request
                                         queue:[NSOperationQueue mainQueue]
                             completionHandler:^(NSURLResponse *response,
                                                 NSData *data,
                                                 NSError *connectionError) {
                               completion(data, connectionError);
                             }];
      return nil;
    }
    NSURLResponse *response = nil;
    return [NSURLConnection sendSynchronousRequest:request
                                 returningResponse:&response
                                             error:&error];
  }
}


@end
