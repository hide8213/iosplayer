#import "MediaResource.h"

#import "AppDelegate.h"
#import "CdmWrapper.h"
#import "DashToHlsApi.h"
#import "Downloader.h"
#import "LicenseManager.h"
#import "Stream.h"

static NSString *kOfflineChangedNotification = @"OfflineChangedNotification";
NSString *kMimeType = @"video/mp4";

static DashToHlsStatus mediaResourcePsshHandler (void *context, const uint8_t *pssh,
                                                 size_t pssh_length) {
  [[iOSCdm sharedInstance] processPsshKey:[NSData dataWithBytes:pssh length:pssh_length]
                                 mimeType:kMimeType
                             isOfflineVod:YES
                          completionBlock:^(NSError *error) {

                          }];
  return kDashToHlsStatus_OK;
}

DashToHlsStatus mediaResourceDecryptionHandler(void *context,
                                               const uint8_t *encrypted,
                                               uint8_t *clear,
                                               size_t length,
                                               uint8_t *iv,
                                               size_t iv_length,
                                               const uint8_t *key_id,
                                               struct SampleEntry *sampleEntry,
                                               size_t sampleEntrySize) {
  return kDashToHlsStatus_OK;
}

@implementation MediaResource
- (instancetype)initWithName:(NSString *)name
                   thumbnail:(NSString *)thumbnail
                         url:(NSURL *)url
                     offline:(BOOL)offline {
  self = [super init];
  NSPointerFunctionsOptions options = NSPointerFunctionsStrongMemory;
  if (self) {
    _name = [name copy];
    _thumbnail = [UIImage imageNamed:thumbnail];
    _url = url;
    _offline = offline;
    _downloadQ = dispatch_queue_create("Downloading", NULL);
    _offlinePath = [(AppDelegate *)[[UIApplication sharedApplication] delegate]
                    urlInDocumentDirectoryForFile:[_url lastPathComponent]];
    _filesBeingDownloaded = [NSMutableArray array];
    _downloads = [NSMapTable mapTableWithKeyOptions:options valueOptions:options];
  }
  return self;
}

- (void)finishedDownloading:(Downloader *)downloader file:(NSURL *)file initRange:(NSRange)range {
  [_filesBeingDownloaded removeObject:file];
  _offline = YES;
  if (![file.pathExtension isEqualToString:@"mpd"]) {
    [self getLicenseFromFile:file range:range];
  }
  if (_filesBeingDownloaded.count == 0) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                        object:self];
  }
}

- (void)failedDownloading:(Downloader *)downloader file:(NSURL *)file error:(NSError *)error {
  UIAlertView* alert;
  NSString *errorMessage = [NSString stringWithFormat:@"Download Failed! \n %@: %@", file, error];

  alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                     message:errorMessage
                                    delegate:nil
                           cancelButtonTitle:@"OK"
                           otherButtonTitles: nil];
  [alert show];
}

- (void)startDownloading:(Downloader *)downloader file:(NSURL *)file {
  [_filesBeingDownloaded addObject:file];
}

- (void)updateDownloadProgress:(NSNumber *)progress file:(NSURL *)file {
  NSEnumerator *enumerator = [_downloads objectEnumerator];
  id value;
  float valueTotal;
  if (![file.pathExtension isEqualToString:@"mpd"]) {
    [_downloads setObject:progress forKey:file];
    while ((value = [enumerator nextObject])) {
      valueTotal = valueTotal + [value floatValue];
    }
  }
  _percentage = (valueTotal / _downloads.count) * 100;
  int updateInterval = 3; // Check Every 3%
  if ((_percentage % updateInterval) == 0) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                        object:self];
  }
}

- (BOOL)isDownloaded {
  return [[NSFileManager defaultManager] fileExistsAtPath:
          [NSString stringWithUTF8String:_offlinePath.fileSystemRepresentation]];
}

- (BOOL)findPssh:(NSData*)initializationData {
  struct DashToHlsSession *session = NULL;
  DashToHlsStatus status = DashToHls_CreateSession(&session);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not initialize session url=%@", _url);
    return NO;
  }
  status = DashToHls_SetCenc_PsshHandler(session,
                                         nil,
                                         mediaResourcePsshHandler);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set PSSH Handler url=%@", _url);
    return NO;
  }
  status = DashToHls_SetCenc_DecryptSample(session,
                                           nil,
                                           mediaResourceDecryptionHandler,
                                           false);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"Could not set Decrypt Handler url=%@", _url);
    return NO;
  }
  if (_offline) {
    status = DashToHls_ParseLivePssh(session,
                                     (const uint8_t *)[initializationData bytes],
                                     [initializationData length]);
    if (status == kDashToHlsStatus_ClearContent) {
    } else if (status == kDashToHlsStatus_OK) {
    } else {
      NSLog(@"Could not parse dash url=%@", _url);
      return NO;
    }
  }
  return YES;
}

- (void)getLicenseFromFile:(NSURL *)file range:(NSRange)range {
  [Downloader downloadPartialData:file
                            range:range
                       completion:^(NSData *data, NSError *connectionError) {
                         dispatch_async(_downloadQ, ^() {
                           if (!data) {
                             NSLog(@"Did not download %@", connectionError);
                           }
                           if (![self findPssh:data]) {
                             return;
                           }
                         });
                       }];
}

@end
