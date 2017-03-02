// Copyright 2015 Google Inc. All rights reserved.

#import "Downloader.h"
#import "MasterViewController.h"

@class MasterViewController;

@interface MediaResource : NSObject <DownloadDelegate>

@property(nonatomic) NSMutableDictionary<NSURL *, NSNumber *> *downloads;
@property(nonatomic, strong) NSMutableArray *filesBeingDownloaded;
// Query CDM for License Status and Expiration.
@property(nonatomic) BOOL getLicenseInfo;
@property(nonatomic, assign) int percentage;
@property(nonatomic, strong) NSURL *licenseServerURL;
@property(nonatomic, strong) NSString *name;
@property(nonatomic, assign) BOOL offline;
@property(nonatomic, strong) NSURL *offlinePath;
@property(nonatomic, strong) NSData *pssh;
// Offline License File ready to be deleted.
@property BOOL releaseLicense;
@property(nonatomic, strong) NSURL *thumbnailURL;
@property(nonatomic, strong) UIImage *thumbnailImage;
@property(nonatomic, assign) int thumbnailLoadTries;
@property(nonatomic, strong) NSURL *URL;
@property(nonatomic) NSRange initRange;

- (instancetype)initWithJson:(NSDictionary *)jsonDictionary;

- (void)deleteMediaResource:(NSURL *)mpdURL completionBlock:(void (^)(NSError *))completionBlock;
- (void)fetchPsshFromFileURL:(NSURL *)fileURL
                initialRange:(NSRange)initialRange
             completionBlock:(void (^)(NSError *))completionBlock;
- (void)fetchLicenseInfo:(NSURL *)mpdURL
         completionBlock:(void (^)(NSError *))completionBlock;
- (BOOL)isDownloaded;

@end
