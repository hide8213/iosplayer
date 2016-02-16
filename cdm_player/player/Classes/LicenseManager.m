// Copyright 2015 Google Inc. All rights reserved.

#import "LicenseManager.h"

#import "Streaming.h"

NSString *kStorageName = @"Keystore/";
NSString *kKeyMapName = @"KeyMap";
NSString *kLicenseUrlString = @"https://widevine-proxy.appspot.com/proxy";

@interface LicenseManager () {
  Streaming *_streaming;
  NSURL *_keyStoreURL;
  dispatch_queue_t _queue;
}

@end

@implementation LicenseManager
// Very naive archival of offline licenses.  The naivity is to help integration
// by keeping the keyfiles in the clear.  These keyfiles could be lifted and
// placed on another device to authorize that device.
//
// A real implementation should encrypt these files.
//
// A minimal encryption would be combining a keychain random password with an
// application password.  This scheme would prevent just lifting the keys and
// moving them to another user, but as the keychain can be dumped and modified
// a user would be able to copy the licenses.

+ (void)startup {
  [self sharedInstance];
}

// No actual work done to shut us down.
+ (void)shutdown {
}

- (instancetype) init {
  self = [super init];
  if (self) {
    _queue = dispatch_queue_create("Licensing", NULL);
    _keyStoreURL =
        [NSURL URLWithString:kStorageName
               relativeToURL:[[NSFileManager defaultManager]URLsForDirectory:NSDocumentDirectory
                                                                   inDomains:NSUserDomainMask][0]];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:_keyStoreURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&error];
    if (error) {
      NSLog(@"Could not create directory because %@", error);
      return nil;
    }

  }
  return self;
}

+ (LicenseManager *)sharedInstance {
  static dispatch_once_t token;
  static LicenseManager *s_licMgr = nil;
  dispatch_once(&token, ^{
    s_licMgr = [[LicenseManager alloc] init];
    [[iOSCdm sharedInstance] setupCdmWithDelegate:s_licMgr];
  });
  return s_licMgr;
}

- (NSData *)readFile:(NSString *)fileName {
  return [NSData dataWithContentsOfURL:[NSURL URLWithString:fileName relativeToURL:_keyStoreURL]];
}

- (void)writeData:(NSData *)data file:(NSString *)fileName {
  NSError *error = nil;
  NSString *filePath = [[_keyStoreURL path] stringByAppendingPathComponent:fileName];
  [data writeToFile:filePath options:NSDataWritingAtomic error:&error];
  if (error) {
    NSLog(@"Could not write data to %@ because %@", fileName, error);
  }
}

- (BOOL)fileExists:(NSString *)fileName {
  NSString *filePath = [[_keyStoreURL path] stringByAppendingPathComponent:fileName];
  return [[NSFileManager defaultManager] fileExistsAtPath:filePath];
}

- (int32_t)fileSize:(NSString *)fileName {
  NSError *error;
  NSString *filePath = [[_keyStoreURL path] stringByAppendingPathComponent:fileName];
  NSDictionary *fileAttributes = [[NSFileManager defaultManager]
      attributesOfItemAtPath:filePath error:&error];
  if (error) {
    return -1;
  }
  NSNumber *sizeNumber = [fileAttributes objectForKey:NSFileSize];
  return [sizeNumber intValue];
}

- (BOOL)removeFile:(NSString *)fileName {
  NSError *error;
  NSString *filePath = [[_keyStoreURL path] stringByAppendingPathComponent:fileName];
  [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
  if (error) {
    NSLog(@"Could not remove %@ due to %@", fileName, error);
  }
  return error == nil;
}

- (void)onSessionCreatedWithPssh:(NSData *)pssh webId:(NSString *)webId {
  NSURL *fileURL = [NSURL URLWithString:kKeyMapName relativeToURL:_keyStoreURL];

  NSData *keyMapData = [NSData dataWithContentsOfURL:fileURL];
  NSMutableDictionary *keyMap = [NSKeyedUnarchiver unarchiveObjectWithData:keyMapData];
  if (!keyMap) {
    keyMap = [NSMutableDictionary dictionary];
  }
  keyMap[pssh] = webId;

  keyMapData = [NSKeyedArchiver archivedDataWithRootObject:keyMap];
  [keyMapData writeToURL:fileURL atomically:YES];
}

- (NSString *)webSessionForPssh:(NSData *)pssh {
  NSURL *fileURL = [NSURL URLWithString:kKeyMapName relativeToURL:_keyStoreURL];

  NSData *keyMapData = [NSData dataWithContentsOfURL:fileURL];
  if (keyMapData) {
    NSMutableDictionary *keyMap = [NSKeyedUnarchiver unarchiveObjectWithData:keyMapData];
    return [keyMap objectForKey:pssh];
  }
  return nil;
}

- (dispatch_queue_t)iOSCdmDispatchQueue:(iOSCdm *)iOSCdm {
  return _queue;
}

- (void)iOSCdm:(iOSCdm *)iOSCdm
    fetchLicenseWithData:(NSData *)data
         completionBlock:(void(^)(NSData *, NSError *))completionBlock {
  NSMutableURLRequest *request =
      [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLicenseUrlString]];
  [request setHTTPMethod:@"POST"];
  [request setHTTPBody:data];
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *response_data = [NSURLConnection sendSynchronousRequest:request
                                                returningResponse:&response
                                                            error:&error];
  completionBlock(response_data, error);
}

@end
