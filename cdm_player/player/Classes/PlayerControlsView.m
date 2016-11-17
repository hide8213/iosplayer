#import "PlayerControlsView.h"

#import <MediaPlayer/MediaPlayer.h>

#import "PlaybackView.h"

@implementation PlayerControlsView {
  UIToolbar *_buttonBar;
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
    _buttonBar.tintColor = [UIColor whiteColor];
    // TODO(seawardt): Clean up images (location/support multiple resolutions)
    _fullscreenEnterImage = [UIImage imageNamed:@"inline_playback_enter_fullscreen_2x.png"];
    _fullscreenExitImage = [UIImage imageNamed:@"inline_playback_exit_fullscreen_2x.png"];

    MPVolumeView *airplayView = [[MPVolumeView alloc] init];
    airplayView.showsVolumeSlider = NO;
    airplayView.showsRouteButton = YES;
    [airplayView sizeToFit];

    // Generate bar button items
    _playButtonItem = [self barButtonItemWithTitle:@"Play" systemItem:UIBarButtonSystemItemPlay
                                          selector:@selector(didPressPlay)];
    _pauseButtonItem = [self barButtonItemWithTitle:@"Pause"
                                         systemItem:UIBarButtonSystemItemPause
                                           selector:@selector(didPressPause)];
    _flexItem = [self barButtonItemWithTitle:@"Flex"
                              systemItem:UIBarButtonSystemItemFlexibleSpace
                                selector:nil];
    UIBarButtonItem *airplayItem =
        [[UIBarButtonItem alloc] initWithCustomView:airplayView];
    _restartButtonItem = [self barButtonItemWithTitle:@"Restart"
                                       systemItem:UIBarButtonSystemItemRefresh
                                         selector:@selector(didPressRestart)];
    _fullscreenButtonItem = [self barButtonItemWithImage:_fullscreenEnterImage
                                            selector:@selector(didPressToggleFullscreen)];
    _buttonBar.items = @[ _pauseButtonItem,
                          _flexItem,
                          airplayItem,
                          _restartButtonItem,
                          _fullscreenButtonItem ];
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
  NSMutableArray *newItems = [NSMutableArray arrayWithArray:_buttonBar.items];
  [newItems replaceObjectAtIndex:0 withObject:_pauseButtonItem];
  [_buttonBar setItems:newItems];
}

- (void)showPlayButton {
  NSMutableArray *newItems = [NSMutableArray arrayWithArray:_buttonBar.items];
  [newItems replaceObjectAtIndex:0 withObject:_playButtonItem];
  [_buttonBar setItems:newItems];
}

- (void)toggleFullscreenButton {
  if (_isFullscreen) {
    [_fullscreenButtonItem setImage:_fullscreenExitImage];
  } else {
    [_fullscreenButtonItem setImage:_fullscreenEnterImage];
  }
}

- (UIBarButtonItem *)barButtonItemWithImage:(UIImage *)image selector:(SEL)selector {
  UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithImage:_fullscreenEnterImage
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:selector];
  return barButton;
}

- (UIBarButtonItem *)barButtonItemWithTitle:(NSString *)title
                                 systemItem:(UIBarButtonSystemItem)systemItem
                                   selector:(SEL)selector {
  UIBarButtonItem *barButton =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:systemItem target:self action:selector];
  [barButton setStyle:UIBarButtonItemStyleDone];
  NSString *titleString = NSLocalizedString(title,"");
  [barButton setTitle:titleString];
  return barButton;
}

@end
