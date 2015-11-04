// Copyright 2015 Google Inc. All rights reserved.
#import <AVFoundation/AVFoundation.h>
#import "PlaybackView.h"

#import "PlayerControlsView.h"
#import "PlayerScrubberView.h"

@implementation PlaybackView

const float kAspectRatio = 0.5625;
const int kIconSize = 24;
const int kElementHeight = 44;
const int kElementWidth = 70;

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor blackColor];
    _videoRenderingView = [[UIView alloc] init];
    _videoRenderingView.backgroundColor = [UIColor grayColor];
    [self addSubview:_videoRenderingView];

    _controlsView = [[PlayerControlsView alloc] init];
    [self addSubview:_controlsView];

    _scrubberView = [[PlayerScrubberView alloc] init];
    [self addSubview:_scrubberView];
  }
  return self;
}

- (void)setFullscreen:(BOOL)fullscreen {
  _fullscreen = fullscreen;
  [self setNeedsLayout];
}

- (void)layoutSubviews {
  CGFloat height = self.bounds.size.height;
  CGFloat width = self.bounds.size.width;
  [_scrubberView setFrame:CGRectMake(0, 0, width, kElementHeight)];
  [_controlsView setFrame:CGRectMake(0, height - kElementHeight, width, kElementHeight)];
  [self bringSubviewToFront:_scrubberView];
  [self bringSubviewToFront:_controlsView];
  if (_fullscreen) {
    [_videoRenderingView setFrame:self.bounds];
  } else {
    [_videoRenderingView setFrame:CGRectInset(self.bounds, 0, kElementHeight)];
    [_videoRenderingView setContentMode:UIViewContentModeScaleAspectFit];
    [_videoRenderingView setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
  }
}

+ (Class)layerClass {
  return [AVPlayerLayer class];
}

- (AVPlayer*)player {
  return [(AVPlayerLayer *)[self layer] player];
}

- (void)setPlayer:(AVPlayer *)player {
  [(AVPlayerLayer *)[self layer] setPlayer:player];
}

/* Specifies how the video is displayed within a player layer’s bounds.
 (AVLayerVideoGravityResizeAspect is default) */
- (void)setVideoFillMode:(NSString *)fillMode {
  AVPlayerLayer *playerLayer = (AVPlayerLayer*)[self layer];
  playerLayer.videoGravity = fillMode;
}

@end
