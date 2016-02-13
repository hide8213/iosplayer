// Copyright 2015 Google Inc. All rights reserved.

#import "MasterViewController.h"

#import "AppDelegate.h"
#import "DetailViewController.h"
#import "LicenseManager.h"
#import "MediaCell.h"
#import "MediaResource.h"
#import "MpdParser.h"


static NSString *kOfflineChangedNotification = @"OfflineChangedNotification";
static NSString *kAlertTitle = @"Info";
static NSString *kAlertButtonTitle = @"OK";
static NSString *kPlaylistTitle = @"Playlist";

@interface MasterViewController ()<MasterViewControllerDelegate>
@property(nonatomic, strong) MediaResource *mediaResource;
@property(nonatomic, strong) NSMutableArray *mediaResources;
@property(nonatomic, strong) NSIndexPath *offlineIndexPath;
@property(nonatomic, strong) NSIndexPath *selectedIndexPath;
@end

@implementation MasterViewController

- (instancetype)init {
  self = [super initWithStyle:UITableViewStylePlain];
  if (self) {
    self.title = kPlaylistTitle;
    self.mediaResources = [NSMutableArray array];
    self.detailViewController = (DetailViewController *)
        [[self.splitViewController.viewControllers lastObject] topViewController];
    // Load Media from JSON file (mediaResources.json)
    NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"mediaResources"
                                                         ofType:@"json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSArray *mediaResources =
        [NSJSONSerialization JSONObjectWithData:jsonData
                                        options:NSJSONReadingAllowFragments
                                          error:&error];
    for (NSDictionary *mediaResource in mediaResources) {
      if ([mediaResource isKindOfClass:[NSDictionary class]] && error == nil) {
        NSString *name = [mediaResource objectForKey:@"name"];
        NSString *thumbnail = [mediaResource objectForKey:@"thumbnail"];
        NSString *url = [mediaResource objectForKey:@"url"];
        [self.mediaResources
             addObject:[[MediaResource alloc] initWithName:name
                                                 thumbnail:nil
                                                       url:[NSURL URLWithString:url]]];
      }
    }
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [[NSNotificationCenter defaultCenter] addObserver:self.tableView
                                           selector:@selector(reloadData)
                                               name:kOfflineChangedNotification
                                             object:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return self.mediaResources.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString * const sReuseIdentifier = @"mediaCell";
  MediaResource *mediaResource = _mediaResources[indexPath.row];

  MediaCell *mediaCell =
      [tableView dequeueReusableCellWithIdentifier:sReuseIdentifier];
  if (!mediaCell) {
    mediaCell =  [[MediaCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:sReuseIdentifier];
  }
  mediaCell.textLabel.text = mediaResource.name;
  mediaCell.isDownloaded = mediaResource.isDownloaded;
  mediaCell.filesBeingDownloaded = mediaResource.filesBeingDownloaded;
  mediaCell.percentage = mediaResource.percentage;
  mediaCell.delegate = self;
  [mediaCell updateDisplay];

  return mediaCell;
}

#pragma mark - Private Methods

- (BOOL)isInternetConnectionAvailable {
  NSURL *scriptUrl = [NSURL URLWithString:@"http://www.google.com"];
  NSData *data = [NSData dataWithContentsOfURL:scriptUrl];
  if (data) {
    return YES;
  } else {
    return NO;
  }
}

- (void)connectionErrorAlert {
  // Display the error.
  NSError *error = [NSError errorWithDomain:@"No Connection Found." code:404 userInfo:nil];
  UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[error localizedDescription]
                                                      message:[error localizedFailureReason]
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil];
  [alertView show];
}

- (void)didPressDelete:(MediaCell *)cell {
  NSInteger row = [self.tableView indexPathForCell:cell].row;
  MediaResource *mediaResource = [_mediaResources objectAtIndex:row];
  NSURL *mpdUrl = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
                       urlInDocumentDirectoryForFile:[mediaResource.url lastPathComponent]];
  [MpdParser deleteFilesInMpd:mpdUrl];
  [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                      object:self];
  UIAlertView* alert;
  NSString *alertMessage = [NSString stringWithFormat:@"Downloaded File Removed.\n File: %@",
                               [mediaResource.url lastPathComponent]];
  alert = [[UIAlertView alloc] initWithTitle:kAlertTitle
                                     message:alertMessage
                                    delegate:nil
                           cancelButtonTitle:kAlertButtonTitle
                           otherButtonTitles: nil];
  [alert show];
}

- (void)didPressDownload:(MediaCell *)cell {
  if ([self isInternetConnectionAvailable]) {
    NSInteger row = [self.tableView indexPathForCell:cell].row;
    MediaResource *mediaResource = [_mediaResources objectAtIndex:row];
    NSURL *fileUrl = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
                          urlInDocumentDirectoryForFile:[mediaResource.url lastPathComponent]];
    [Downloader DownloadWithUrl:mediaResource.url file:fileUrl
                   initialRange:nil
                       delegate:mediaResource];
  } else {
    [self connectionErrorAlert];
  }
}

- (void)didPressPlay:(MediaCell *)cell {
  NSInteger row = [self.tableView indexPathForCell:cell].row;
  MediaResource *mediaResource = [_mediaResources objectAtIndex:row];
  if (!mediaResource.isDownloaded) {
    if (![self isInternetConnectionAvailable]) {
      [self connectionErrorAlert];
      return;
    }
  }
  DetailViewController *playerViewController =
      [[DetailViewController alloc] initWithMediaResource:mediaResource];
  [[self navigationController] pushViewController:playerViewController
                                         animated:YES];
}

@end
