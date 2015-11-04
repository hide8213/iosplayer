// Copyright 2015 Google Inc. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@class AVPlayer;
@class MediaResource;

@interface DetailViewController : UIViewController

@property(strong, setter=setPlayer:, getter=player) AVPlayer *player;
@property(strong) AVPlayerItem *playerItem;

- (instancetype)initWithMediaResource:(MediaResource *)mediaResource;

@end
