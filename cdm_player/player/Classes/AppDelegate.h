// Copyright 2015 Google Inc. All rights reserved.

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(strong, nonatomic) UIWindow *window;
- (NSURL *)urlInDocumentDirectoryForFile:(NSString *)filename;

@end
