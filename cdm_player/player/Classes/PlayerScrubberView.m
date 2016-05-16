#import "PlayerScrubberView.h"

#import "PlaybackView.h"

@implementation PlayerScrubberView {
  UILabel *_currentTimeLabel;
  UILabel *_endTimeLabel;
  UIToolbar *_scrubberBar;
  NSMutableArray *_scrubberBarItems;
  UISlider *_slider;
}

- (instancetype)init {
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _scrubberBar = [[UIToolbar alloc] init];
    _scrubberBar.translucent = YES;
    _scrubberBar.barTintColor = [UIColor blackColor];
    _scrubberBar.tintColor = [UIColor whiteColor];
    _scrubberBarItems = [[NSMutableArray alloc] init];
    _currentTimeLabel =
        [[UILabel alloc] initWithFrame:CGRectMake(0, 0, kElementWidth, kElementHeight)];
    _currentTimeLabel.textColor = [UIColor whiteColor];
    _endTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, kElementWidth, kElementHeight)];
    _endTimeLabel.textColor = [UIColor whiteColor];
    UIBarButtonItem *flexItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                      target:nil
                                                      action:nil];
    UIBarButtonItem *currentTimeItem =
        [[UIBarButtonItem alloc] initWithCustomView:_currentTimeLabel];
    [_scrubberBarItems addObject:currentTimeItem];
    [_scrubberBarItems addObject:flexItem];
    _slider = [[UISlider alloc] init];
    [_slider addTarget:self
                action:@selector(scrubberDidScrubToValue)
      forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *sliderItem = [[UIBarButtonItem alloc] initWithCustomView:_slider];
    [_scrubberBarItems addObject:sliderItem];
    UIBarButtonItem *endTimeItem = [[UIBarButtonItem alloc] initWithCustomView:_endTimeLabel];
    [_scrubberBarItems addObject:flexItem];
    [_scrubberBarItems addObject:endTimeItem];
    _scrubberBar.items = _scrubberBarItems;
    [self addSubview:_scrubberBar];
  }
  return self;
}

- (void)dealloc {
  [_slider removeTarget:self action:nil forControlEvents:UIControlEventValueChanged];
}

- (void)layoutSubviews {
  _scrubberBar.frame = CGRectMake(0, 0, self.frame.size.width, kElementHeight);
  _slider.frame = CGRectMake(0, 0, self.frame.size.width - 200, kElementHeight);
}

#pragma mark Private Methods

- (void)configScrubber:(int)duration {
  _slider.minimumValue = 0;
  _slider.maximumValue = duration;
  [_currentTimeLabel setText:[self convertSeconds:0]];
  [_endTimeLabel setText:[self convertSeconds:duration]];
  if (duration < 0) {
    [_endTimeLabel setText:@"LIVE"];
    _slider.userInteractionEnabled = NO;
  }

}

- (NSString *)convertSeconds:(int)seconds {
  NSString *time = nil;
  NSUInteger hrs = floor(seconds / 3600);
  NSUInteger mins = floor(seconds % 3600 / 60);
  NSUInteger secs = floor(seconds % 3600 % 60);
  if (hrs == 0) {
    time = [NSString stringWithFormat:@"%02ld:%02ld",
            (unsigned long)mins, (unsigned long)secs];
  } else {
    time = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",
               (unsigned long)hrs, (unsigned long)mins, (unsigned long)secs];
  }
  return time;
}

- (void)setScrubberTime:(int)currentTime {
  [_currentTimeLabel setText:[self convertSeconds:currentTime]];
  [_slider setValue:currentTime];
}

- (void)scrubberDidScrubToValue {
  [_scrubberDelegate scrubberDidScrubToValue:_slider.value];
}

@end
