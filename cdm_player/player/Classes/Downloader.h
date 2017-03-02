// Copyright 2015 Google Inc. All rights reserved.

@class Downloader;

// Delegate to communicate the status of a download.
@protocol DownloadDelegate <NSObject>
// Checks the status of the existing download and reports back a percentage.
- (void)downloader:(Downloader *)downloader
    didUpdateDownloadProgress:(float)progress
                   forFileURL:(NSURL *)fileURL;
// Starts the downloader to pull the file and save to disk.
- (void)downloader:(Downloader *)downloader
    didStartDownloadingToURL:(NSURL *)sourceURL
                   toFileURL:(NSURL *)fileURL;
// Signals download is complete.
- (void)downloader:(Downloader *)downloader
    didFinishDownloadingToURL:(NSURL *)sourceURL
                    toFileURL:(NSURL *)fileURL;
// Signals download has failed, with the attached error.
- (void)downloader:(Downloader *)downloader
    downloadFailedForURL:(NSURL *)sourceURL
               withError:(NSError *)error;

@end

@interface Downloader : NSObject <NSURLSessionDownloadDelegate>

+ (instancetype)sharedInstance;
// Init method used to start the download.
// [url] is remote path and [file] is local filename, both are NSURL.
// All of the delegate methods are called asynchronously onto the main queue.
- (instancetype)init NS_UNAVAILABLE;
- (void)downloadURL:(NSURL *)URL
          toFileURL:(NSURL *)fileURL
           delegate:(id<DownloadDelegate>)delegate;

// Used to pull only the range of the requested file and does NOT save the data to disk.
- (void)downloadPartialData:(NSURL *)URL
                      range:(NSRange)range
                 completion:(void (^)(NSData *data, NSError *error)) completion;

// Synchronous version of downloadPartialData:range:completion
- (NSData *)downloadPartialDataSync:(NSURL *)URL range:(NSRange)range;

// Downloader singleton and url sessions. Exposed to allow mocking in unit tests.
@property(strong, nonatomic) NSURLSession *downloadSession;

@end
