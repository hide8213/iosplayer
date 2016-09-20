// Copyright 2015 Google Inc. All rights reserved.

#import "Downloader.h"

#import "MpdParser.h"

static NSMutableArray *sDownloaders;

NSString *const kMpdString = @"mpd";
NSString *const kLengthString = @"length";
NSString *const kRangeHeaderString = @"Range";
NSString *const kStartString = @"startRange";
NSString *const kZeroString = @"0";
NSTimeInterval const kPartialDownloadTimeout = 10.0;
NSTimeInterval const kDownloadTimeout = 90.0;

@interface Downloader ()
@property(nonatomic, strong) NSURLConnection *connection;
@property(nonatomic) NSDictionary *initialRange;
@property(nonatomic, strong) NSURL *fileURL;
@property(nonatomic, strong) NSFileHandle *fileHandle;
@property(nonatomic) BOOL isMpd;
@property(nonatomic, strong) NSURL *URL;
@end

@implementation Downloader {
  NSUInteger _expectedBytes;
  NSUInteger _receivedBytes;
}

+ (instancetype)downloaderWithURL:(NSURL *)URL
                          fileURL:(NSURL *)fileURL
                     initialRange:(NSDictionary *)initialRange
                         delegate:(id<DownloadDelegate>)delegate {
  Downloader *downloader = [[Downloader alloc] init];
  if (downloader) {
    downloader.delegate = delegate;
    downloader.URL = URL;
    if (!initialRange) {
      initialRange = [[NSDictionary alloc]
          initWithObjectsAndKeys:kZeroString, kStartString, kZeroString, kLengthString, nil];
    }
    downloader.initialRange = initialRange;
    downloader.fileURL = fileURL;
    NSString *fileString =
        [NSString stringWithUTF8String:fileURL.fileSystemRepresentation];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createFileAtPath:fileString contents:[NSData data] attributes:nil]) {
      NSLog(@"Error for creating file at %@ was code: %d - message: %s",
            URL, errno, strerror(errno));
    }
    downloader.isMpd = [fileURL.pathExtension isEqualToString:kMpdString];
    downloader.fileHandle = [NSFileHandle fileHandleForWritingAtPath:fileString];

    // TODO(seawardt): Switch to NSURLSession
    NSURLRequest *request = [NSURLRequest requestWithURL:URL
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:kDownloadTimeout];
    downloader.connection =
        [[NSURLConnection alloc] initWithRequest:request delegate:downloader startImmediately:NO];
    [downloader.connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    if ([delegate respondsToSelector:@selector(startDownloading:fileURL:)]) {
      [delegate startDownloading:downloader fileURL:fileURL];
    }
    [downloader.connection start];
  }
  return downloader;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
  _expectedBytes = (NSUInteger)[response expectedContentLength];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
  [_fileHandle writeData:data];
  _receivedBytes += [data length];
  _progress = [NSNumber numberWithFloat:((float)_receivedBytes) / ((float)_expectedBytes)];
  if ([_delegate
          respondsToSelector:@selector(updateDownloadProgress:fileURL:)]) {
    [_delegate updateDownloadProgress:_progress fileURL:_fileURL];
  }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
  if ([_delegate
          respondsToSelector:@selector(failedDownloading:fileURL:error:)]) {
    [_delegate failedDownloading:self fileURL:_fileURL error:error];
  }
  @synchronized(sDownloaders) {
    [sDownloaders removeObject:self];
  }
}

- (void)downloadURLArray:(NSArray *)URLArray {
  for (Stream *stream in URLArray) {
    NSURL *fileURL = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
        urlInDocumentDirectoryForFile:stream.sourceURL.lastPathComponent];
    [Downloader downloaderWithURL:stream.sourceURL
                          fileURL:fileURL
                     initialRange:stream.initialRange
                         delegate:_delegate];
  }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  [_fileHandle closeFile];
  if (_isMpd) {
    NSData *mpdData = [NSData dataWithContentsOfURL:_fileURL];
    [self downloadURLArray:[MpdParser parseMpdWithStreaming:nil
                                                    mpdData:mpdData
                                                    baseURL:_URL
                                               storeOffline:YES]];
  }
  if ([_delegate respondsToSelector:@selector(finishedDownloading:
                                                          fileURL:
                                                     initialRange:)]) {
    [_delegate finishedDownloading:self
                           fileURL:_fileURL
                      initialRange:_initialRange];
  }
  @synchronized(sDownloaders) {
    [sDownloaders removeObject:self];
  }
}

// completion can be nil and it will run sync.
+ (NSData *)downloadPartialData:(NSURL *)URL
                   initialRange:(NSDictionary *)initialRange
                     completion:(void (^)(NSData *data, NSURLResponse *response, NSError *error))
                                    completion {
  NSError *error = nil;
  NSURLResponse *response = nil;
  int startRange = [[initialRange objectForKey:kStartString] intValue];
  int length = [[initialRange objectForKey:kLengthString] intValue];

  if ([URL isFileURL]) {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:URL error:&error];
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
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:URL
                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                            timeoutInterval:kPartialDownloadTimeout];
    // Check if it is a byte range request or full file request.
    if (length != 0) {
      NSString *byteRangeString =
          [NSString stringWithFormat:@"bytes=%d-%d", startRange, startRange + length];
      [request setValue:byteRangeString forHTTPHeaderField:kRangeHeaderString];
    }
    if (completion) {
      [NSURLConnection sendAsynchronousRequest:request
                                         queue:[NSOperationQueue mainQueue]
                             completionHandler:^(
                                 NSURLResponse *response, NSData *data, NSError *connectionError) {
                               completion(data, response, connectionError);
                             }];
      return nil;
    }
    NSURLResponse *response = nil;
    NSData *data =
        [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    if (error != nil) {
      NSLog(@"Error reading %@: %@", URL, error);
      return nil;
    }
    return data;
  }
}

@end
