// Copyright 2015 Google Inc. All rights reserved.

#import "Downloader.h"
#import "MasterViewController.h"

@class MasterViewController;

@interface MediaResource : NSObject <DownloadDelegate>

@property(nonatomic, weak) MasterViewController *controller;
@property(nonatomic) NSMapTable *downloads;
@property(nonatomic, strong) NSMutableArray *filesBeingDownloaded;
// Query CDM for License Status and Expiration.
@property(nonatomic) BOOL getLicenseInfo;
@property(nonatomic, strong) NSURL *keyStoreURL;
@property(nonatomic, assign) int percentage;
@property(nonatomic, strong) NSString *name;
@property(nonatomic, assign) BOOL offline;
@property(nonatomic, strong) NSURL *offlinePath;
@property(nonatomic, strong) NSData *pssh;
// Offline License File ready to be deleted.
@property BOOL releaseLicense;
@property(nonatomic, strong) NSURL *thumbnail;
@property(nonatomic, strong) NSURL *URL;
@property dispatch_queue_t downloadQ;
@property(nonatomic) NSRange initRange;

- (instancetype)initWithName:(NSString *)name thumbnail:(NSURL *)thumbnail URL:(NSURL *)URL;

- (void)deleteMediaResource:(NSURL *)mpdURL completionBlock:(void (^)(NSError *))completionBlock;
- (void)fetchPsshFromFileURL:(NSURL *)fileURL
                initialRange:(NSDictionary *)initialRange
             completionBlock:(void (^)(NSError *))completionBlock;
- (void)fetchLicenseInfo:(NSURL *)mpdURL
         completionBlock:(void (^)(NSError *))completionBlock;
- (BOOL)isDownloaded;
+ (NSURL *)urlInDocumentDirectoryForFile:(NSString *)filename;

@end
