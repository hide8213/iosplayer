#import "PlayerControlsView.h"

#import <MediaPlayer/MediaPlayer.h>

#import "PlaybackView.h"

@implementation PlayerControlsView {
  UIToolbar *_buttonBar;
  NSMutableArray *_buttonBarItems;
  UIBarButtonItem *_flexItem;
  BOOL _isFullscreen;
  UIBarButtonItem *_fullscreenButtonItem;
  UIBarButtonItem *_playButtonItem;
  UIBarButtonItem *_pauseButtonItem;
  UIBarButtonItem *_restartButtonItem;
  UIImage *_fullscreenEnterImage;
  UIImage *_fullscreenExitImage;
}

- (instancetype)init {
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _buttonBar = [[UIToolbar alloc] init];
    _buttonBar.translucent = NO;
    // TODO(seawardt): Condense color configuration into central location
    _buttonBar.barTintColor = [UIColor blackColor];
    _buttonBar.items = _buttonBarItems;
    _buttonBar.tintColor = [UIColor whiteColor];
    _buttonBarItems = [[NSMutableArray alloc] init];
    // TODO(seawardt): Clean up images (location/support multiple resolutions)
    _fullscreenEnterImage = [UIImage imageNamed:@"inline_playback_enter_fullscreen_2x.png"];
    _fullscreenExitImage = [UIImage imageNamed:@"inline_playback_exit_fullscreen_2x.png"];

    // Load button bar items in order to be displayed.
    _pauseButtonItem = [self barButtonWithTitle:@"Pause"
                                     systemItem:UIBarButtonSystemItemPause
                                       selector:@selector(didPressPause)];
    _flexItem = [self barButtonWithTitle:@"Flex"
                              systemItem:UIBarButtonSystemItemFlexibleSpace
                                selector:nil];
    MPVolumeView *airplayView = [[MPVolumeView alloc] init];
    [airplayView setShowsVolumeSlider:NO];
    [airplayView sizeToFit];
    UIBarButtonItem *airplayButtonItem = [[UIBarButtonItem alloc] initWithCustomView:airplayView];
    [_buttonBarItems addObject:airplayButtonItem];
    _restartButtonItem = [self barButtonWithTitle:@"Restart"
                                       systemItem:UIBarButtonSystemItemRefresh
                                         selector:@selector(didPressRestart)];
    _fullscreenButtonItem = [self barButtonWithImage:_fullscreenEnterImage
                                            selector:@selector(didPressToggleFullscreen)];
    [_buttonBarItems addObject:_fullscreenButtonItem];
    _playButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                                      target:self
                                                      action:@selector(didPressPlay)];
    _buttonBar.items = _buttonBarItems;
    [self addSubview:_buttonBar];
  }
  return self;
}

- (void)dealloc {
  [_fullscreenButtonItem setTarget:nil];
  [_pauseButtonItem setTarget:nil];
  [_playButtonItem setTarget:nil];
  [_restartButtonItem setTarget:nil];
}

- (void)layoutSubviews {
  _buttonBar.frame = CGRectMake(0, 0, self.frame.size.width, kElementHeight);
}

#pragma mark Private Methods

- (void)didPressPlay {
  [_controlsDelegate didPressPlay];
  [self showPauseButton];
}

- (void)didPressPause {
  [_controlsDelegate didPressPause];
  [self showPlayButton];
}

- (void)didPressRestart {
  [_controlsDelegate didPressRestart];
  [self didPressPlay];
}

- (void)didPressToggleFullscreen {
  if (_isFullscreen) {
    _isFullscreen = NO;
  } else {
    _isFullscreen = YES;
  }
  [_controlsDelegate didPressToggleFullscreen];
  [self toggleFullscreenButton];
}

- (void)showPauseButton {
  [_buttonBarItems replaceObjectAtIndex:0 withObject:_pauseButtonItem];
  _buttonBar.items = _buttonBarItems;
}

- (void)showPlayButton {
  [_buttonBarItems replaceObjectAtIndex:0 withObject:_playButtonItem];
  _buttonBar.items = _buttonBarItems;
}

- (void)toggleFullscreenButton {
  if (_isFullscreen) {
    [_fullscreenButtonItem setImage:_fullscreenExitImage];
  } else {
    [_fullscreenButtonItem setImage:_fullscreenEnterImage];
  }
}

- (UIBarButtonItem *)barButtonWithImage:(UIImage *)image
                     selector:(SEL)selector {
  UIBarButtonItem *barButton = [[UIBarButtonItem alloc]  initWithImage:_fullscreenEnterImage
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:selector];
  return barButton;
}

- (UIBarButtonItem *)barButtonWithTitle:(NSString *)title
                             systemItem:(UIBarButtonSystemItem)systemItem
                               selector:(SEL)selector {
  UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:systemItem
                                                                             target:self
                                                                             action:selector];
  [barButton setStyle:UIBarButtonItemStyleDone];
  [barButton setTitle:title];
  [_buttonBarItems addObject:barButton];
  return barButton;
}

@end
