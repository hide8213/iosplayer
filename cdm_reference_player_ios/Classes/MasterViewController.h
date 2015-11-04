// Copyright 2015 Google Inc. All rights reserved.

#import <UIKit/UIKit.h>

#import "Downloader.h"

@class DetailViewController;

@interface MasterViewController : UITableViewController<DownloadDelegate>
@property(nonatomic, strong) DetailViewController *detailViewController;
@end
