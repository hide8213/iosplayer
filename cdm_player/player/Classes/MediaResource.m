// Copyright 2015 Google Inc. All rights reserved.

#import "MediaResource.h"

#import "AppDelegate.h"
#import "CdmPlayerErrors.h"
#import "CdmPlayerHelpers.h"
#import "MpdParser.h"
#import "Logging.h"

static NSString *kJsonMediaName = @"media_name";
static NSString *kJsonMediaThumbnailURL = @"media_thumbnail_url";
static NSString *kJsonMediaURL = @"media_url";
static NSString *kJsonLicenseServerURL = @"license_server_url";

static NSString *kOfflineChangedNotification = @"OfflineChangedNotification";
static const NSInteger kProgressUpdateInterval = 3;
NSString *kMimeType = @"video/mp4";

static DashToHlsStatus mediaResourcePsshHandler(void *context,
                                                const uint8_t *pssh,
                                                size_t pssh_length) {
  MediaResource *mediaResource = (__bridge MediaResource *)(context);
  NSData *psshData = [NSData dataWithBytes:pssh length:pssh_length];
  if (mediaResource.releaseLicense) {
    [[iOSCdm sharedInstance] removeOfflineLicenseForPsshKey:psshData
                                            completionBlock:^(NSError *error) {
                                              if (error) {
                                                CDMLogNSError(error,
                                                              @"removing license of %@",
                                                              mediaResource.name);
                                              }
                                            }];
    return kDashToHlsStatus_OK;
  }
  if (mediaResource.getLicenseInfo) {
    [[iOSCdm sharedInstance]
     getLicenseInfo:psshData
     completionBlock:^(int64_t *expiration, NSError *error) {
       if (error) {
         CDMLogNSError(error, @"retrieving license info for %@", mediaResource.name);
       }
     }];
    return kDashToHlsStatus_OK;
  }
  [[iOSCdm sharedInstance] processPsshKey:psshData
                             isOfflineVod:YES
                          completionBlock:^(NSError *error){
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

@implementation MediaResource {
  dispatch_queue_t _downloadQ;
}

- (instancetype)initWithJson:(NSDictionary *)jsonDictionary {
  self = [super init];
  NSPointerFunctionsOptions options = NSPointerFunctionsStrongMemory;
  if (!jsonDictionary) {
    return nil;
  }
  if (self) {
     NSString *name = [jsonDictionary objectForKey:kJsonMediaName];
     NSString *licenseServerURL = [jsonDictionary objectForKey:kJsonLicenseServerURL];
     NSString *thumbnailURL = [jsonDictionary objectForKey:kJsonMediaThumbnailURL];
     NSString *URL = [jsonDictionary objectForKey:kJsonMediaURL];
     if (URL && name) {
       _name = [name copy];
       _licenseServerURL = [NSURL URLWithString:licenseServerURL];
       _thumbnailURL = [NSURL URLWithString:thumbnailURL];
       _URL = [NSURL URLWithString:URL];
       _offlinePath = CDMDocumentFileURLForFilename(_URL.lastPathComponent);
       if ([self isDownloaded]) {
         _offline = YES;
       }
       _downloadQ = dispatch_queue_create("com.google.widevine.cdm-player.download", NULL);
       _filesBeingDownloaded = [NSMutableArray array];
       _downloads = [[NSMutableDictionary alloc] init];
     } else {
       CDMLogWarn(@"Media entry found, but not complete. Skipping %@", jsonDictionary);
       return nil;
     }
  }
  return self;
}

- (void)deleteMediaResource:(NSURL *)mpdURL
            completionBlock:(void (^)(NSError *))completionBlock {
  _releaseLicense = YES;
  NSURL *documentDirectoryURL =
      [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory
                                             inDomain:NSUserDomainMask
                                    appropriateForURL:nil
                                               create:YES
                                                error:NULL];
  NSArray *offlineFiles =
      [MpdParser parseMpdWithStreaming:nil
                               mpdData:[NSData dataWithContentsOfURL:mpdURL]
                               baseURL:mpdURL
                          storeOffline:YES];
  __block NSError *deleteError = nil;
  dispatch_group_t deleteGroup = dispatch_group_create();
  dispatch_queue_t deleteQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  for (Stream *stream in offlineFiles) {
    dispatch_group_enter(deleteGroup);

    [self fetchPsshFromFileURL:stream.sourceURL
                  initialRange:stream.initialRange
               completionBlock:^(NSError *error) {
                 deleteError = error;
                 NSString *fileName = stream.sourceURL.lastPathComponent;
                 NSURL *fileURL = [documentDirectoryURL URLByAppendingPathComponent:fileName
                                                                        isDirectory:NO];
                 [[NSFileManager defaultManager] removeItemAtURL:fileURL error:&error];
                 if (error) {
                   CDMLogNSError(error, @"deleting existing file at %@", fileURL);
                   deleteError = error;
                 } else {
                   CDMLogInfo(@"Deleting %@", fileURL);
                 }
                 dispatch_group_leave(deleteGroup);
               }];
  }

  dispatch_group_notify(deleteGroup, deleteQueue, ^{
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:mpdURL error:&error];
    if (error) {
      CDMLogNSError(error, @"deleting existing file at %@", mpdURL);
      dispatch_async(dispatch_get_main_queue(), ^{
        completionBlock(error);
      });
      return;
    }
    if (deleteError) {
      error = deleteError;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      CDMLogInfo(@"Deleted MPD %@", mpdURL);
      _releaseLicense = NO;
      completionBlock(error);
    });
  });
}

- (void)fetchLicenseInfo:(NSURL *)mpdURL
         completionBlock:(void (^)(NSError *))completionBlock {
  CDMLogInfo(@"Fetching license info for %@", mpdURL);

  // Set flag to let PSSH Handler pull license information.
  _getLicenseInfo = YES;
  NSArray *offlineFiles =
      [MpdParser parseMpdWithStreaming:nil
                               mpdData:[NSData dataWithContentsOfURL:mpdURL]
                               baseURL:mpdURL
                          storeOffline:YES];
  __block NSError *expirationError = nil;
  dispatch_group_t expirationGroup = dispatch_group_create();
  dispatch_queue_t expirationQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  for (Stream *stream in offlineFiles) {
    dispatch_group_enter(expirationGroup);
    [self fetchPsshFromFileURL:stream.sourceURL
                  initialRange:stream.initialRange
               completionBlock:^(NSError *error) {
                 expirationError = error;
                 if (error) {
                   CDMLogNSError(error, @"getting expiration date from file");
                   expirationError = error;
                 }
                 dispatch_group_leave(expirationGroup);
               }];
  }

  dispatch_group_notify(expirationGroup, expirationQueue, ^{
    NSError *error = expirationError;
    if (error) {
      CDMLogNSError(error, @"getting expiration date from file");
      completionBlock(error);
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      _getLicenseInfo = NO;
      completionBlock(error);
    });
  });
}

- (void)fetchPsshFromFileURL:(NSURL *)fileURL
                initialRange:(NSRange)initialRange
             completionBlock:(void (^)(NSError *))completionBlock {
  CDMLogInfo(@"Fetching PSSH from %@", fileURL);

  Downloader *downloader = [Downloader sharedInstance];
  [downloader downloadPartialData:fileURL
                            range:initialRange
                       completion:^(NSData *data, NSError *connectionError) {
                         dispatch_async(_downloadQ, ^() {
                           if (!data) {
                             CDMLogNSError(connectionError, @"downloading file %@", fileURL);
                             return;
                           }
                           if (![self findPssh:data]) {
                             return;
                           }
                           completionBlock(connectionError);
                         });
                       }];
}

- (BOOL)findPssh:(NSData *)initializationData {
  NSParameterAssert(initializationData);

  struct DashToHlsSession *session = NULL;
  DashToHlsStatus status = Udt_CreateSession(&session);
  if (status != kDashToHlsStatus_OK) {
    CDMLogError(@"failed to initialize dash to HLS session for %@", _URL);
    return NO;
  }
  status = DashToHls_SetCenc_PsshHandler(session, (__bridge DashToHlsContext)(self),
                                         mediaResourcePsshHandler);
  if (status != kDashToHlsStatus_OK) {
    CDMLogError(@"failed to set PSSH handler with URL %@", _URL);
    return NO;
  }
  status = DashToHls_SetCenc_DecryptSample(session, nil, mediaResourceDecryptionHandler, false);
  if (status != kDashToHlsStatus_OK) {
    CDMLogError(@"failed to set decrypt handler for URL %@", _URL);
    return NO;
  }
  status = Udt_ParseDash(session, 0, (uint8_t *)[initializationData bytes],
                         [initializationData length], nil, 0, nil);
  if (status == kDashToHlsStatus_ClearContent) {
  } else if (status == kDashToHlsStatus_OK) {
  } else {
    CDMLogError(@"failed to parse DASH for session with URL %@", _URL);
    return NO;
  }
  return YES;
}

- (BOOL)isDownloaded {
  return [[NSFileManager defaultManager]
          fileExistsAtPath:[NSString stringWithUTF8String:_offlinePath.fileSystemRepresentation]];
}

#pragma mark - downloader delegate methods

- (void)downloader:(Downloader *)downloader
    didStartDownloadingToURL:(NSURL *)sourceURL
                   toFileURL:(NSURL *)fileURL {
  [_filesBeingDownloaded addObject:fileURL];
}

- (void)downloader:(Downloader *)downloader
    downloadFailedForURL:(NSURL *)sourceURL
               withError:(NSError *)error {
  CDMLogNSError(error, @"downloading %@", sourceURL);

  UIAlertView *alert;
  NSString *message = [NSString stringWithFormat:@"Failed to download %@\n%@", sourceURL, error];

  alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                     message:message
                                    delegate:nil
                           cancelButtonTitle:@"OK"
                           otherButtonTitles:nil];
  [alert show];
}

- (void)downloader:(Downloader *)downloader
    didFinishDownloadingToURL:(NSURL *)sourceURL
                    toFileURL:(NSURL *)fileURL {
  [_filesBeingDownloaded removeObject:fileURL];
  _offline = YES;
  if (![fileURL.pathExtension isEqualToString:@"mpd"]) {
    NSString *resourceName = self.name;
    [self fetchPsshFromFileURL:fileURL
                  initialRange:NSMakeRange(0, NSUIntegerMax)
               completionBlock:^(NSError *error) {
                 if (error) {
                   CDMLogNSError(error, @"getting offline license for %@", resourceName);
                 }
               }];
  }
  if (_filesBeingDownloaded.count == 0) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                        object:self];
  }
  CDMLogInfo(@"Finished downloading %@", fileURL);
}

- (void)downloader:(Downloader *)downloader
  didUpdateDownloadProgress:(float)progress
                 forFileURL:(NSURL *)fileURL {
  float totalDownloadProgress = 0.f;
  if (![fileURL.pathExtension isEqualToString:@"mpd"]) {
    _downloads[fileURL] = @(progress);
    for (NSNumber *progress in _downloads.allValues) {
      totalDownloadProgress += progress.floatValue;
    }
  }
  _percentage = (totalDownloadProgress / _downloads.count) * 100;
  if ((_percentage % kProgressUpdateInterval) == 0) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                        object:self];
  }
}

@end
