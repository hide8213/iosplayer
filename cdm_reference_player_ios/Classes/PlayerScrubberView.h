@protocol PlayerScrubberDelegate
// Handles scrubber bar that allows seeking.

// Value is in seconds between 0 and player duration.
- (void)scrubberDidScrubToValue:(NSTimeInterval)value;

@end

@interface PlayerScrubberView : UIView

@property(nonatomic, weak) id<PlayerScrubberDelegate> scrubberDelegate;

- (void)initScrubber:(int)duration;
- (void)setScrubberTime:(int)currentTime;

@end
