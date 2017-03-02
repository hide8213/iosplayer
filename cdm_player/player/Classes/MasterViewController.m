// Copyright 2015 Google Inc. All rights reserved.

#import "MasterViewController.h"

#import "AppDelegate.h"
#import "DetailViewController.h"
#import "CdmPlayerErrors.h"
#import "CdmPlayerHelpers.h"
#import "MediaCell.h"
#import "MediaResource.h"
#import "Logging.h"

static NSString *kOfflineChangedNotification = @"OfflineChangedNotification";
static NSString *kAlertTitle = @"Info";
static NSString *kAlertButtonTitle = @"OK";
static NSString *kPlaylistTitle = @"Playlist";
int const kMaxThumbnailLoadTries = 5;


@interface MasterViewController () <MediaCellDelegate>
@property(nonatomic, strong) NSMutableArray *mediaResources;
@property(nonatomic, strong) NSIndexPath *offlineIndexPath;
@property(nonatomic, strong) NSIndexPath *selectedIndexPath;
@property(nonatomic, strong) NSURLSession *thumbnailSession;
@end

@implementation MasterViewController

- (instancetype)init {
  self = [super initWithStyle:UITableViewStylePlain];
  if (self) {
    self.title = kPlaylistTitle;
    _mediaResources = [NSMutableArray array];
    _detailViewController = (DetailViewController *)[
        [self.splitViewController.viewControllers lastObject] topViewController];
    // Load Media from JSON file (mediaResources.json)
    NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"mediaResources" ofType:@"json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    NSError *error = nil;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    _thumbnailSession = [NSURLSession sessionWithConfiguration:config];
    NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData:jsonData
                                                              options:NSJSONReadingAllowFragments
                                                                error:&error];
    if (error == nil) {
      for (NSDictionary *jsonDictionary in jsonArray) {
        MediaResource *mediaResource = [[MediaResource alloc] initWithJson:jsonDictionary];
        if (mediaResource) {
          [_mediaResources addObject:mediaResource];
        }
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return _mediaResources.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString *const sReuseIdentifier = @"mediaCell";
  MediaResource *mediaResource = _mediaResources[indexPath.row];

  MediaCell *mediaCell = [tableView dequeueReusableCellWithIdentifier:sReuseIdentifier];
  if (!mediaCell) {
    mediaCell = [[MediaCell alloc] initWithStyle:UITableViewCellStyleDefault
                                 reuseIdentifier:sReuseIdentifier];
  }
  mediaCell.textLabel.text = mediaResource.name;
  mediaCell.isDownloaded = mediaResource.isDownloaded;
  mediaCell.filesBeingDownloaded = mediaResource.filesBeingDownloaded;
  mediaCell.percentage = mediaResource.percentage;
  if (mediaResource.thumbnailImage) {
    mediaCell.thumbnail = mediaResource.thumbnailImage;
  } else {
    [self downloadThumbnailForResource:mediaResource atIndexPath:indexPath];
  }
  mediaCell.delegate = self;
  [mediaCell updateDisplay];
  return mediaCell;
}

- (void)downloadThumbnailForResource:(MediaResource *)resource
                         atIndexPath:(NSIndexPath *)indexPath {
  CDMLogInfo(@"Downloading thumbnail for %@.", resource.name);

  resource.thumbnailLoadTries += 1;
  NSURLSessionDataTask *task = [_thumbnailSession
        dataTaskWithURL:resource.thumbnailURL
      completionHandler:^(NSData *data, NSURLResponse *response,
                          NSError *error) {
        [self didDownloadThumbnailData:data forResource:resource atIndexPath:indexPath];
      }];
  [task resume];
}

- (void)didDownloadThumbnailData:(NSData *)data
                     forResource:(MediaResource *)resource
                     atIndexPath:(NSIndexPath *)indexPath {
  if (data) {
    dispatch_sync(dispatch_get_main_queue(), ^{
      MediaCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
      resource.thumbnailImage = [UIImage imageWithData:data];
      cell.thumbnail = resource.thumbnailImage;
    });
  }
  if (!resource.thumbnailImage) {
    // either there was an error downloading, or the data failed to turn into an image
    // so try to download again
    if (resource.thumbnailLoadTries < kMaxThumbnailLoadTries) {
      // don't try to load indefinitely; don't want to eat up the user's network plan if the server
      // is down
      [self downloadThumbnailForResource:resource atIndexPath:indexPath];
    } else {
      CDMLogWarn(@"Failed to download thumbnail image for %@, at %@.", resource.name, resource.URL);
    }
  }
}

#pragma mark - Private Methods

// TODO(seawardt): Add Reachability in place of basic check (b/27264396).
- (BOOL)isInternetConnectionAvailable {
  NSURL *scriptURL = [NSURL URLWithString:@"http://www.google.com"];
  NSData *data = [NSData dataWithContentsOfURL:scriptURL];
  return (data != nil);
}

- (void)connectionErrorAlert {
  // Display the error.
  NSError *error = [NSError cdmErrorWithCode:CdmPlayeriOSErrorCode_NoConnection userInfo:nil];
  UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"No Connection Available"
                                                      message:[error localizedFailureReason]
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil];
  [alertView show];
}

- (void)didDeleteMediaURL:(NSURL *)mediaURL error:(NSError *)error {
  if (error) {
    CDMLogNSError(error, @"deleting %@", mediaURL);
    return;
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                      object:self];
  UIAlertView *alert = nil;
  NSString *alertMessage = [NSString
      stringWithFormat:@"Downloaded File Removed.\n File: %@", [mediaURL lastPathComponent]];
  alert = [[UIAlertView alloc] initWithTitle:kAlertTitle
                                     message:alertMessage
                                    delegate:nil
                           cancelButtonTitle:kAlertButtonTitle
                           otherButtonTitles:nil];
  [alert show];
}

- (void)didPressDelete:(MediaCell *)cell {
  NSInteger row = [self.tableView indexPathForCell:cell].row;
  MediaResource *mediaResource = [_mediaResources objectAtIndex:row];
  NSURL *mpdURL = CDMDocumentFileURLForFilename(mediaResource.URL.lastPathComponent);
  [mediaResource deleteMediaResource:mpdURL
                     completionBlock:^(NSError *error) {
                       [self didDeleteMediaURL:mediaResource.URL error:error];
                     }];
}

// TODO (theodab): break media resource downloading, deleting, etc into a separate manager class
- (void)didPressDownload:(MediaCell *)cell {
  if ([self isInternetConnectionAvailable]) {
    NSInteger row = [self.tableView indexPathForCell:cell].row;
    MediaResource *mediaResource = [_mediaResources objectAtIndex:row];
    NSURL *fileURL = CDMDocumentFileURLForFilename(mediaResource.URL.lastPathComponent);
    [[Downloader sharedInstance] downloadURL:mediaResource.URL
                                   toFileURL:fileURL
                                    delegate:mediaResource];
  } else {
    [self connectionErrorAlert];
  }
}

- (void)didPressLicense:(MediaCell *)cell {
  NSInteger row = [self.tableView indexPathForCell:cell].row;
  MediaResource *mediaResource = [_mediaResources objectAtIndex:row];
  [mediaResource
      fetchLicenseInfo:mediaResource.URL
       completionBlock:^(NSError *error) {
         if (error) {
           CDMLogNSError(error, @"fetching license for %@", mediaResource.name);
         }
       }];
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
  [[self navigationController] pushViewController:playerViewController animated:YES];
}

@end
