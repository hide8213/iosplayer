// Copyright 2015 Google Inc. All rights reserved.

#import "Downloader.h"
#import "MasterViewController.h"

@class MasterViewController;

@interface MediaResource : NSObject<DownloadDelegate>

@property(nonatomic, weak) MasterViewController *controller;
@property(nonatomic) NSMapTable *downloads;
@property(nonatomic, strong) NSMutableArray *filesBeingDownloaded;
@property(nonatomic, strong) NSURL *keyStoreURL;
@property(nonatomic, assign) int percentage;
@property(nonatomic, strong) NSString *name;
@property(nonatomic, assign) BOOL offline;
@property(nonatomic, strong) NSURL *offlinePath;
@property(nonatomic, strong) NSURL *thumbnail;
@property(nonatomic, strong) NSURL *url;
@property dispatch_queue_t downloadQ;
@property(nonatomic) NSRange initRange;

- (instancetype)initWithName:(NSString *)name
                   thumbnail:(NSURL *)thumbnail
                         url:(NSURL *)url;

- (BOOL)isDownloaded;

@end
