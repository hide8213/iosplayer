// Copyright 2015 Google Inc. All rights reserved.

@class Downloader;

// Delegate to communicate the status of a download.
@protocol DownloadDelegate <NSObject>
// Checks the status of the existing download and reports back a percentage.
- (void)updateDownloadProgress:(NSNumber *)progress fileURL:(NSURL *)fileURL;
// Starts the downloader to pull the file and save to disk.
- (void)startDownloading:(Downloader *)downloader fileURL:(NSURL *)fileURL;
// Used to signal download is complete and kick off a noticiation.
- (void)finishedDownloading:(Downloader *)downloader
                    fileURL:(NSURL *)fileURL
               initialRange:(NSDictionary *)initialRange;
// Reports an error when a download does not finish.
- (void)failedDownloading:(Downloader *)downloader
                  fileURL:(NSURL *)fileURL
                    error:(NSError *)error;
@end

@interface Downloader : NSObject <NSURLConnectionDataDelegate>
@property(nonatomic, weak) id<DownloadDelegate> delegate;
@property(nonatomic, strong) NSNumber *progress;

// Init method used to start the download.
// [url] is remote path and [file] is local filename, both are NSURL.
// [initialRange] contains two keys ("start" & "length") paired with a numerical value defined as
// strings.
+ (instancetype)downloaderWithURL:(NSURL *)URL
                          fileURL:(NSURL *)fileURL
                     initialRange:(NSDictionary *)initialRange
                         delegate:(id<DownloadDelegate>)delegate;

// Used to pull only the range of the requested file and does NOT save the data to disk.
+ (NSData *)downloadPartialData:(NSURL *)URL
                   initialRange:(NSDictionary *)initialRange
                     completion:(void (^)(NSData *data, NSURLResponse *response, NSError *error))
                                    completion;
@end
