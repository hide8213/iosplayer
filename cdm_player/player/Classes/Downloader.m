// Copyright 2015 Google Inc. All rights reserved.

#import "Downloader.h"

#import "CdmPlayerErrors.h"
#import "CdmPlayerHelpers.h"
#import "MpdParser.h"
#import "Logging.h"

@interface DownloadInfo : NSObject
@property(nonatomic, weak) id<DownloadDelegate> delegate;
@property(nonatomic) NSURL *fileURL;
@property(nonatomic) NSURLSessionDownloadTask *task;
@end

@implementation DownloadInfo
@end

static NSString *const kMpdString = @"mpd";
NSString *const kRangeHeaderString = @"Range";
NSTimeInterval const kDownloadTimeout = 10.0;

@interface Downloader () <NSURLSessionDownloadDelegate>
@property(nonatomic) NSMutableDictionary<NSURL *, DownloadInfo *> *downloadInfoForRequest;
@property dispatch_queue_t delegateQueue;
-(instancetype)initInternal;
@end

@implementation Downloader

- (instancetype)initInternal {
  if (self = [super init]) {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = kDownloadTimeout;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.downloadSession = [NSURLSession sessionWithConfiguration:config
                                                         delegate:self
                                                    delegateQueue:nil];
    self.downloadInfoForRequest = [[NSMutableDictionary<NSURL *, DownloadInfo *> alloc] init];
    self.delegateQueue = dispatch_get_main_queue();
  }
  return self;
}

+ (instancetype)sharedInstance {
  static Downloader *downloader = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    downloader = [[Downloader alloc] initInternal];
  });
  return downloader;
}

- (void)downloadURL:(NSURL *)URL
          toFileURL:(NSURL *)fileURL
           delegate:(id<DownloadDelegate>)delegate {
  // make the download task
  NSURLSessionDownloadTask *task = [self.downloadSession downloadTaskWithURL:URL];
  if ([self downloadInfoForTask:task shouldRemove:NO] != nil) {
    // someone is already downloading something with the same URL!
    NSError *error = [NSError cdmErrorWithCode:CdmPlayeriOSErrorCode_AlreadyDownloading
                                      userInfo:nil];
    dispatch_async(self.delegateQueue, ^{
      [delegate downloader:self downloadFailedForURL:URL withError:error];
    });
    return;
  }

  // save all of the session-related data into the session info dict, for safekeeping
  DownloadInfo *info = [[DownloadInfo alloc] init];
  info.delegate = delegate;
  info.fileURL = fileURL;
  info.task = task;
  [self setDownloadInfo:info forTask:task];

  // and now start the download task
  CDMLogInfo(@"Downloading data at %@.", URL);
  dispatch_async(self.delegateQueue, ^{
    [delegate downloader:self didStartDownloadingToURL:URL toFileURL:fileURL];
  });

  [task resume];
}


- (void)downloadPartialData:(NSURL *)URL
                      range:(NSRange)range
                 completion:(void (^)(NSData *data, NSError *error)) completion {
  CDMLogInfo(@"Downloading data at %@.", URL);

  if ([URL isFileURL]) {
    // it's a local file
    NSError *error;
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:URL error:&error];
    if (error) {
      completion(nil, error);
      return;
    }
    [fileHandle seekToFileOffset:range.location];
    NSData *data = [fileHandle readDataOfLength:range.length];
    completion(data, nil);
    return;
  }

  // format a request to download from that URL, optionally with a byte range
  NSURLRequestCachePolicy policy = NSURLRequestReloadIgnoringLocalCacheData;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL
                                                         cachePolicy:policy
                                                     timeoutInterval:kDownloadTimeout];

  if (range.length != 0) {
    NSString *byteRangeString = [NSString stringWithFormat:@"bytes=%lu-%lu",
                                 (unsigned long)range.location,
                                 (unsigned long)NSMaxRange(range)];
    [request setValue:byteRangeString forHTTPHeaderField:kRangeHeaderString];
  }

  void (^wrapped)(NSData *, NSURLResponse *, NSError *) = NULL;
  wrapped = ^(NSData * _Nullable data,
              NSURLResponse * _Nullable response,
              NSError * _Nullable error) {
    completion(data, error);
  };
  NSURLSessionDataTask *task = [self.downloadSession dataTaskWithRequest:request
                                                       completionHandler:wrapped];
  [task resume];
}

- (NSData *)downloadPartialDataSync:(NSURL *)URL range:(NSRange)range {
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSData *downloaded = nil;
  void (^completion)(NSData *, NSError *);
  completion = ^(NSData * _Nullable data, NSError * _Nullable error) {
    downloaded = data;
    dispatch_semaphore_signal(semaphore);
  };

  [self downloadPartialData:URL range:range completion:completion];
  dispatch_time_t timeOut = dispatch_time(DISPATCH_TIME_NOW,
                                          (uint64_t)(NSEC_PER_SEC * kDownloadTimeout));
  dispatch_semaphore_wait(semaphore, timeOut);
  return downloaded;
}

#pragma mark - helpers

// Dispatches an error to the delegate of the download info.
- (void)dispatchError:(NSError *)error forDownload:(DownloadInfo *)info withSourceURL:(NSURL *)url {
  dispatch_async(self.delegateQueue, ^{
    [info.delegate downloader:self downloadFailedForURL:url withError:error];
  });
}

// Accesses the download info for the given task.
- (DownloadInfo *)downloadInfoForTask:(NSURLSessionTask *)task shouldRemove:(BOOL)shouldRemove {
  @synchronized (self) {
    DownloadInfo *info;
    info = self.downloadInfoForRequest[task.originalRequest.URL];
    if (shouldRemove) {
      [self.downloadInfoForRequest removeObjectForKey:task.originalRequest.URL];
    }
    return info;
  }
}

// Sets the download info for the given task.
- (void)setDownloadInfo:(DownloadInfo *)info forTask:(NSURLSessionTask *)task {
  @synchronized (self) {
    self.downloadInfoForRequest[task.originalRequest.URL] = info;
  }
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
  if (error) {
    DownloadInfo *info = [self downloadInfoForTask:task shouldRemove:YES];
    [self dispatchError:error forDownload:info withSourceURL:task.originalRequest.URL];
  }
}

- (void)URLSession:(NSURLSession *)session
                 downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didFinishDownloadingToURL:(NSURL *)location {
  // move the file from its temporary location to a permanent one
  NSFileManager *fileManager = [NSFileManager defaultManager];

  DownloadInfo *info = [self downloadInfoForTask:downloadTask shouldRemove:YES];

  NSURL *url = downloadTask.originalRequest.URL;
  NSURL *fileURL = info.fileURL;
  CDMLogInfo(@"Moving file from temporary location %@ to permanent location %@.",
             location,
             fileURL);

  NSError *error;
  [fileManager moveItemAtURL:location toURL:fileURL error:&error];
  if (error) {
    [self dispatchError:error forDownload:info withSourceURL:downloadTask.originalRequest.URL];
    return;
  }

  if ([fileURL.pathExtension isEqualToString:kMpdString]) {
    // download the files referenced by the MPD
    NSData *data = [NSData dataWithContentsOfURL:fileURL];
    // TODO (theodab): properly parse manifests with SegmentTemplate fields
    // since we have one and it has a download button
    NSArray<Stream *> *parsed = [MpdParser parseMpdWithStreaming:nil
                                                         mpdData:data
                                                         baseURL:url
                                                    storeOffline:YES];
    if (parsed.count == 0) {
      // delete the manifest
      [fileManager removeItemAtURL:fileURL error:nil];
      error = [NSError cdmErrorWithCode:CdmPlayeriOSErrorCode_EmptyMPD userInfo:nil];
      [self dispatchError:error forDownload:info withSourceURL:downloadTask.originalRequest.URL];
      return;
    }
    for (Stream *stream in parsed) {
      NSURL *streamURL = CDMDocumentFileURLForFilename(stream.sourceURL.lastPathComponent);
      [self downloadURL:stream.sourceURL
              toFileURL:streamURL
               delegate:info.delegate];
    }
  }

  dispatch_async(self.delegateQueue, ^{
    [info.delegate downloader:self didFinishDownloadingToURL:url toFileURL:fileURL];
  });
}

-(void)URLSession:(NSURLSession *)session
             downloadTask:(NSURLSessionDownloadTask *)downloadTask
             didWriteData:(int64_t)bytesWritten
        totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
  DownloadInfo *info = [self downloadInfoForTask:downloadTask shouldRemove:NO];
  float progress;
  if (totalBytesExpectedToWrite == 0) {
    progress = 0;
  } else {
    progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
  }
  dispatch_async(self.delegateQueue, ^{
    [info.delegate downloader:self didUpdateDownloadProgress:progress forFileURL:info.fileURL];
  });
}

@end
