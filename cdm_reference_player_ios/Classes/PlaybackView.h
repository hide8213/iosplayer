// Copyright 2015 Google Inc. All rights reserved.

#import <UIKit/UIKit.h>

@class AVPlayer;
@class PlayerControlsView;
@class PlayerScrubberView;

@interface PlaybackView : UIView

extern const float kAspectRatio;
extern const int kIconSize;
extern const int kElementHeight;
extern const int kElementWidth;

@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) UIView *videoRenderingView;
@property(nonatomic, readonly) PlayerControlsView *controlsView;
@property(nonatomic, readonly) PlayerScrubberView *scrubberView;

// Sets whether to show the rendering view as the entire screen.
@property(nonatomic, assign, getter=isFullscreen) BOOL fullscreen;

- (void)setVideoFillMode:(NSString *)fillMode;

@end