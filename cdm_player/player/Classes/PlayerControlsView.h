@protocol PlayerControlsDelegate

- (void)didPressPlay;
- (void)didPressPause;
- (void)didPressRestart;
- (void)didPressToggleFullscreen;

@end

@interface PlayerControlsView : UIView

@property(nonatomic, weak) id<PlayerControlsDelegate> controlsDelegate;

@end
