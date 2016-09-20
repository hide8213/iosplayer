// Copyright 2015 Google Inc. All rights reserved.

#import "MediaResource.h"

#import "AppDelegate.h"
#import "CdmPlayerErrors.h"
#import "MpdParser.h"

static NSString *kOfflineChangedNotification = @"OfflineChangedNotification";
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
                                                NSLog(@"\n::ERROR::Removing License: %@", error);
                                              }
                                            }];
    return kDashToHlsStatus_OK;
  }
  if (mediaResource.getLicenseInfo) {
    [[iOSCdm sharedInstance]
     getLicenseInfo:psshData
     completionBlock:^(int64_t *expiration, NSError *error) {
       if (error) {
         NSLog(@"\n::ERROR::Retrieving License Info: %@", error);
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

@implementation MediaResource
- (instancetype)initWithName:(NSString *)name thumbnail:(NSURL *)thumbnail URL:(NSURL *)URL {
  self = [super init];
  NSPointerFunctionsOptions options = NSPointerFunctionsStrongMemory;
  if (self) {
    _name = [name copy];
    _thumbnail = thumbnail;
    _URL = URL;
    _offlinePath = [MediaResource urlInDocumentDirectoryForFile:[_URL lastPathComponent]];
    if ([self isDownloaded]) {
      _offline = YES;
    }
    _releaseLicense = NO;
    _downloadQ = dispatch_queue_create("com.google.widevine.cdm-player.download", NULL);
    _filesBeingDownloaded = [NSMutableArray array];
    _downloads = [NSMapTable mapTableWithKeyOptions:options valueOptions:options];
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
                 NSURL *fileURL = [documentDirectoryURL
                                   URLByAppendingPathComponent:[stream.sourceURL lastPathComponent]
                                   isDirectory:NO];
                 [[NSFileManager defaultManager] removeItemAtURL:fileURL error:&error];
                 if (error) {
                   NSLog(@"::ERROR::Unable to delete existing file.\n");
                   deleteError = error;
                 } else {
                   NSLog(@"\n::INFO:: Deleting: %@", fileURL);
                 }
                 dispatch_group_leave(deleteGroup);
               }];
  }

  dispatch_group_notify(deleteGroup, deleteQueue, ^{
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:mpdURL error:&error];
    if (error) {
      NSLog(@"\n::ERROR::Unable to delete existing file.\n");
      completionBlock(error);
      return;
    }
    if (deleteError) {
      error = deleteError;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      NSLog(@"\n::INFO::Deleted MPD: %@", mpdURL);
      _releaseLicense = NO;
      completionBlock(error);
    });
  });
}

- (void)failedDownloading:(Downloader *)downloader
                  fileURL:(NSURL *)fileURL
                    error:(NSError *)error {
  UIAlertView *alert;
  NSString *errorMessage =
  [NSString stringWithFormat:@"\n::ERROR::Download Failed! \n %@: %@",
   fileURL, error];

  alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                     message:errorMessage
                                    delegate:nil
                           cancelButtonTitle:@"OK"
                           otherButtonTitles:nil];
  [alert show];
}

- (void)finishedDownloading:(Downloader *)downloader
                    fileURL:(NSURL *)fileURL
               initialRange:(NSDictionary *)initialRange {
  [_filesBeingDownloaded removeObject:fileURL];
  _offline = YES;
  if (![fileURL.pathExtension isEqualToString:@"mpd"]) {
    [self fetchPsshFromFileURL:fileURL
                  initialRange:initialRange
               completionBlock:^(NSError *error) {
                 if (error) {
                   NSLog(@"\n::ERROR::Getting Offline License: %@", error);
                 }
               }];
  }
  if (_filesBeingDownloaded.count == 0) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                        object:self];
  }
  NSLog(@"\n::INFO::Download Complete: %@", fileURL);
}

- (void)fetchLicenseInfo:(NSURL *)mpdURL
         completionBlock:(void (^)(NSError *))completionBlock {
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
                   NSLog(@"\n::ERROR::Unable to get expiration from file.\n"
                         "%@ %ld %@",
                         [error domain], (long)[error code],
                         [[error userInfo] description]);
                   expirationError = error;
                 }
                 dispatch_group_leave(expirationGroup);
               }];
  }

  dispatch_group_notify(expirationGroup, expirationQueue, ^{
    NSError *error = expirationError;
    if (error) {
      NSLog(@"\n::ERROR::Unable to get expiration from file.\n"
            "%@ %ld %@",
            [error domain], (long)[error code], [[error userInfo] description]);
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
                initialRange:(NSDictionary *)initialRange
             completionBlock:(void (^)(NSError *))completionBlock {
  [Downloader
      downloadPartialData:fileURL
             initialRange:initialRange
               completion:^(NSData *data, NSURLResponse *response,
                            NSError *connectionError) {
                 dispatch_async(_downloadQ, ^() {
                   if (!data) {
                     NSLog(@"\n::ERROR::Did not download %@", connectionError);
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
    NSLog(@"\n::ERROR::Could not initialize session URL=%@", _URL);
    return NO;
  }
  status = DashToHls_SetCenc_PsshHandler(session, (__bridge DashToHlsContext)(self),
                                         mediaResourcePsshHandler);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"\n::ERROR::Could not set PSSH Handler URL=%@", _URL);
    return NO;
  }
  status = DashToHls_SetCenc_DecryptSample(session, nil, mediaResourceDecryptionHandler, false);
  if (status != kDashToHlsStatus_OK) {
    NSLog(@"\n::ERROR::Could not set Decrypt Handler URL=%@", _URL);
    return NO;
  }
  status = Udt_ParseDash(session, 0, (uint8_t *)[initializationData bytes],
                         [initializationData length], nil, nil, nil);
  if (status == kDashToHlsStatus_ClearContent) {
  } else if (status == kDashToHlsStatus_OK) {
  } else {
    NSLog(@"\n::ERROR::Could not parse dash url=%@", _URL);
    return NO;
  }
  return YES;
}

- (BOOL)isDownloaded {
  return [[NSFileManager defaultManager]
          fileExistsAtPath:[NSString stringWithUTF8String:_offlinePath.fileSystemRepresentation]];
}

- (void)startDownloading:(Downloader *)downloader fileURL:(NSURL *)fileURL {
  [_filesBeingDownloaded addObject:fileURL];
}

- (void)updateDownloadProgress:(NSNumber *)progress fileURL:(NSURL *)fileURL {
  NSEnumerator *enumerator = [_downloads objectEnumerator];
  id value;
  float valueTotal = 0.f;
  if (![fileURL.pathExtension isEqualToString:@"mpd"]) {
    [_downloads setObject:progress forKey:fileURL];
    while ((value = [enumerator nextObject])) {
      valueTotal = valueTotal + [value floatValue];
    }
  }
  _percentage = (valueTotal / _downloads.count) * 100;
  int updateInterval = 3;  // Check Every 3%
  if ((_percentage % updateInterval) == 0) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kOfflineChangedNotification
                                                        object:self];
  }
}

+ (NSURL *)urlInDocumentDirectoryForFile:(NSString *)filename {
  return [(AppDelegate *)[[UIApplication sharedApplication] delegate]
          urlInDocumentDirectoryForFile:filename];
}

@end
