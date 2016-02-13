// Copyright 2015 Google Inc. All rights reserved.

#import "AppDelegate.h"

#import "MasterViewController.h"
#import "DetailViewController.h"
#import "LicenseManager.h"

@implementation AppDelegate {
  UIWindow *_window;
}

- (NSURL *)urlInDocumentDirectoryForFile:(NSString *)filename {
  NSURL *documentDirectoryUrl =
      [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                             inDomains:NSUserDomainMask][0];
  return [NSURL URLWithString:filename relativeToURL:documentDirectoryUrl];
}

- (UIWindow *)window {
  if (!_window) {
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.backgroundColor = [UIColor blackColor];
  }
  return _window;
}

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  // Disable the idle timer so that the screen does not sleep while playing video.
  application.idleTimerDisabled = YES;
  MasterViewController *masterViewController = [[MasterViewController alloc] init];
  UINavigationController *navController =
      [[UINavigationController alloc] initWithRootViewController:masterViewController];
  [self.window makeKeyAndVisible];
  [self.window setRootViewController:navController];
  [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
  [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:NO];
  [LicenseManager startup];
  return YES;
}

@end
