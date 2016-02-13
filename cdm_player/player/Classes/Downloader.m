#import "Downloader.h"

#import "AppDelegate.h"
#import "MpdParser.h"
#import "Streaming.h"

static NSMutableArray *sDownloaders;

@interface Downloader()
@property(nonatomic, strong) NSURLConnection *connection;
@property(nonatomic) NSDictionary *initialRange;
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
                     initialRange:(NSDictionary *)initialRange
                         delegate:(id<DownloadDelegate>)delegate{
  Downloader *downloader = [[Downloader alloc] init];
  if (downloader) {
    downloader.delegate = delegate;
    downloader.url = url;
    downloader.initialRange = initialRange;
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
           initialRange:(NSDictionary *)initialRange
              delegate:(id<DownloadDelegate>)delegate {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sDownloaders = [NSMutableArray array];
  });
  if (!initialRange) {
    initialRange = [[NSDictionary alloc] initWithObjectsAndKeys:@"0", @"startRange", @"0", @"length", nil];
  }
  @synchronized(sDownloaders) {
    [sDownloaders addObject:[Downloader DownloaderWithUrl:url
                                                     file:file
                                             initialRange:initialRange
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
  for (Stream *stream in urlArray) {
    NSURL *fileUrl = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
        urlInDocumentDirectoryForFile:stream.url.lastPathComponent];
    [Downloader DownloadWithUrl:stream.url
                           file:fileUrl
                   initialRange:stream.initialRange
                       delegate:_delegate];
  }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  [_fileHandle closeFile];
  if (_isMpd) {
    NSData *mpdData = [NSData dataWithContentsOfURL:_file];
    [self downloadUrlArray:[MpdParser parseMpdWithStreaming:nil
                                                    mpdData:mpdData
                                                    baseUrl:_url]];
  }
  if ([_delegate respondsToSelector:@selector(finishedDownloading:file:initialRange:)]) {
    [_delegate finishedDownloading:self file:_file initialRange:_initialRange];
  }
  @synchronized(sDownloaders) {
    [sDownloaders removeObject:self];
  }
}

// completion can be nil and it will run sync.
+ (NSData *)downloadPartialData:(NSURL *)url
                   initialRange:(NSDictionary *)initialRange
                     completion:(void(^)(NSData *data,
                                         NSURLResponse *response,
                                         NSError *error))completion {
  NSError *error = nil;
  NSURLResponse *response = nil;
  int startRange = [[initialRange objectForKey:@"startRange"] intValue];
  int length = [[initialRange objectForKey:@"length"] intValue];

  if ([url isFileURL]) {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:&error];
    if (error) {
      if (completion) {
        completion(nil, response, error);
      }
      return nil;
    }
        [fileHandle seekToFileOffset:startRange];
    NSData *data = [fileHandle readDataOfLength:length];
    if (completion) {
      completion(data, response, nil);
    }
    return data;
  } else {
    NSMutableURLRequest *request = [NSMutableURLRequest
                                    requestWithURL:url
                                    cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                    timeoutInterval:5];
    NSString *byteRangeString = [NSString stringWithFormat:@"bytes=%d-%d",
                                 startRange,
                                 startRange + length];
    [request setValue:byteRangeString forHTTPHeaderField:@"Range"];
    if (completion) {
      [NSURLConnection sendAsynchronousRequest:request
                                         queue:[NSOperationQueue mainQueue]
                             completionHandler:^(NSURLResponse *response,
                                                 NSData *data,
                                                 NSError *connectionError) {
                               completion(data, response, connectionError);
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
