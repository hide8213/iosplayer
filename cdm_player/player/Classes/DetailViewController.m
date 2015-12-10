// Copyright 2015 Google Inc. All rights reserved.
#import "DetailViewController.h"

#import <AudioToolbox/AudioToolbox.h>

#import "CdmWrapper.h"
#import "DashToHlsApi.h"
#import "DashToHlsApiAVFramework.h"
#import "MasterViewController.h"
#import "MediaResource.h"
#import "LicenseManager.h"
#import "PlaybackView.h"
#import "PlayerControlsView.h"
#import "PlayerScrubberView.h"
#import "Streaming.h"


static DetailViewController *sDetailViewController;

@interface DetailViewController() <PlayerControlsDelegate, PlayerScrubberDelegate> {
  BOOL _isSeeking;
  NSURL *_keyStoreURL;
  NSString *_mediaName;
  NSURL *_mediaUrl;
  BOOL *_offline;
  PlaybackView *_playbackView;
  AVPlayer *_player;
  UIView *_renderingView;
  float _restoreAfterScrubbingRate;
  float _resumeTime;
  BOOL _seekToZeroBeforePlay;
  Streaming *_streaming;
  UITapGestureRecognizer *_tapRecognizer;
  id _timeObserver;
  id _timer;
}
@end

@interface DetailViewController (Player)
- (BOOL)isPlaying;
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context;
- (void)playerItemDidReachEnd:(NSNotification *)notification ;
- (CMTime)playerItemDuration;
- (void)prepareToPlayAsset:(AVURLAsset *)asset withKeys:(NSArray *)requestedKeys;
- (void)removePlayerTimeObserver;
@end

static void *PlaybackViewControllerRateObservationContext =
    &PlaybackViewControllerRateObservationContext;
static void *PlaybackViewControllerStatusObservationContext =
    &PlaybackViewControllerStatusObservationContext;
static void *PlaybackViewControllerCurrentItemObservationContext =
    &PlaybackViewControllerCurrentItemObservationContext;

NSString *kDash2HlsUrl = @"http://%@:%d/dash2hls.m3u8";

@implementation DetailViewController

- (instancetype)initWithMediaResource:(MediaResource *)mediaResource {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    sDetailViewController = self;
    self.title = mediaResource.name;
    // Positions this view controller below the navigation bar.
    self.edgesForExtendedLayout = UIRectEdgeNone;
    [self setupStreaming:mediaResource];
  }
  return self;
}

- (void)setupStreaming:(MediaResource *)mediaResource {
  _streaming = [[Streaming alloc] initWithAirplay:[self isAirplayActive]];
  _streaming.offline = mediaResource.isDownloaded;
  _mediaName = mediaResource.name;
  if (_streaming.offline) {
    _mediaUrl = mediaResource.offlinePath;
  } else {
    _mediaUrl = mediaResource.url;
  }
  if ([_mediaUrl.pathExtension isEqualToString:@"mpd"]) {
    _streaming.manifestURL = _mediaUrl;
  }
}

- (void)configScrubber {
  _timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                            target:self
                                          selector:@selector(syncScrubber)
                                          userInfo:nil
                                           repeats:YES];
  CMTime playerDuration = [self playerItemDuration];
  if (CMTIME_IS_INVALID(playerDuration)) {
    playerDuration = kCMTimeZero;
  }
  [_playbackView.scrubberView initScrubber:CMTimeGetSeconds(playerDuration)];
}

- (void)handleTap {
  if ([_playbackView.controlsView isHidden]) {
    [_playbackView.controlsView setHidden:NO];
    [_playbackView.scrubberView setHidden:NO];
  } else {
    [_playbackView.controlsView setHidden:YES];
    [_playbackView.scrubberView setHidden:YES];
  }
}

#pragma mark EXODemoPlayerControlsDelegate

- (void)didPressPlay {
  [_player play];
}

- (void)didPressPause {
  [_player pause];
}

- (void)didPressRestart {
  [_player seekToTime:kCMTimeZero];
  [self setScrubberTime:CMTimeGetSeconds(kCMTimeZero)];
}

- (void)didPressToggleFullscreen {
  if (_playbackView.fullscreen) {
    [_playbackView layoutSubviews];
    [_playbackView removeGestureRecognizer:_tapRecognizer];
  } else {
    [_playbackView addGestureRecognizer:_tapRecognizer];
    [UIView animateWithDuration:0.5
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^(void) {
                       _playbackView.controlsView.hidden = true;
                       _playbackView.scrubberView.hidden = true;
                     }
                     completion:NULL];
  }
  _playbackView.fullscreen = !_playbackView.isFullscreen;
  [[self navigationController] setNavigationBarHidden:_playbackView.isFullscreen];
  [[UIApplication sharedApplication] setStatusBarHidden:_playbackView.isFullscreen
                                          withAnimation:NO];
}

#pragma mark PlayerScrubberDelegate

- (void)scrubberDidScrubToValue:(NSTimeInterval)value {
  CMTime time = CMTimeMakeWithSeconds(value, NSEC_PER_SEC);
  [_player seekToTime:time];
}

- (void)setScrubberTime:(int)currentTime {
  [_playbackView.scrubberView setScrubberTime:currentTime];
}

- (void)syncScrubber {
  [self setScrubberTime:CMTimeGetSeconds([_player currentTime])];
}

#pragma mark
#pragma mark View Controller

- (void)loadView {
  _playbackView = [[PlaybackView alloc] init];
  _playbackView.controlsView.delegate = self;
  _playbackView.scrubberView.scrubberDelegate = self;
  [_playbackView setVideoRenderingView:_renderingView];
  [self setView:_playbackView];
  _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                           action:@selector(handleTap)];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(streamingReady:)
                                               name:kStreamingReadyNotification
                                             object:nil];
  // Notification when Airplay route has been invoked.
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(audioRouteHasChangedNotification:)
                                               name:AVAudioSessionRouteChangeNotification
                                             object:[AVAudioSession sharedInstance]];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  [_player pause];
  [_streaming stop];
  _streaming = nil;
  _mediaUrl = nil;
  [self removePlayerTimeObserver];
  [_playerItem removeObserver:self forKeyPath:@"status"];
  [_player removeObserver:self forKeyPath:@"rate"];
  [_player removeObserver:self forKeyPath:@"currentItem"];
  _playerItem = nil;
  [self setPlayer:nil];
  _playbackView = nil;
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:kStreamingReadyNotification
                                                object:nil];
}

- (void)streamingReady:(NSNotification *)notification {
  NSString *address = [[NSString alloc] initWithFormat:kDash2HlsUrl,
                       _streaming.address, _streaming.httpPort];
  _mediaUrl = [[NSURL alloc] initWithString:address];
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:_mediaUrl options:nil];
  if (DashToHls_SetAVURLAsset(asset, NULL, dispatch_get_main_queue()) != kDashToHlsStatus_OK) {
    NSLog(@"Cannot set the loopback encryption");
  }

  NSArray *requestedKeys = @[@"playable"];
  // Tells the asset to load the values of any of the specified keys that are not already loaded.
  [asset loadValuesAsynchronouslyForKeys:requestedKeys completionHandler:
   ^{
     dispatch_async( dispatch_get_main_queue(),
                    ^{
                      // IMPORTANT: Must dispatch to main queue.
                      [self prepareToPlayAsset:asset withKeys:requestedKeys];
                    });
   }];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

#pragma mark - External screen handling

- (BOOL)isAirplayActive {
  AVAudioSession* audioSession = [AVAudioSession sharedInstance];
  AVAudioSessionRouteDescription* currentRoute = audioSession.currentRoute;
  for (AVAudioSessionPortDescription* outputPort in currentRoute.outputs){
    if ([outputPort.portType isEqualToString:AVAudioSessionPortAirPlay])
    return YES;
  }
  return NO;
}

- (void)audioRouteHasChangedNotification:(NSNotification*)notification {
  _resumeTime = CMTimeGetSeconds([_player currentTime]);
  [_streaming restart:[self isAirplayActive]];
  [[NSNotificationCenter defaultCenter] postNotificationName:kStreamingReadyNotification
                                                      object:self];
}

@end

@implementation DetailViewController (Player)
#pragma mark Player Item

- (BOOL)isPlaying {
  return _restoreAfterScrubbingRate != 0.f || [_player rate] != 0.f;
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
  // After the movie has played to its end time, seek back to time zero to play it again.
  _seekToZeroBeforePlay = YES;
}

- (CMTime)playerItemDuration {
  AVPlayerItem *playerItem = [_player currentItem];
  if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
    return([playerItem duration]);
  }
  return(kCMTimeInvalid);
}


// Cancels the previously registered time observer.
- (void)removePlayerTimeObserver {
  if (_timeObserver) {
    [_player removeTimeObserver:_timeObserver];
    _timeObserver = nil;
  }
}

#pragma mark -
#pragma mark Error Handling - Preparing Assets for Playback Failed

/* --------------------------------------------------------------
 **  Called when an asset fails to prepare for playback for any of
 **  the following reasons:
 **
 **  1) values of asset keys did not load successfully,
 **  2) the asset keys did load successfully, but the asset is not
 **     playable
 **  3) the item did not become ready to play.
 ** ----------------------------------------------------------- */

- (void)assetFailedToPrepareForPlayback:(NSError *)error {
  [self removePlayerTimeObserver];
  // Display the error.
  UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[error localizedDescription]
                                                      message:[error localizedFailureReason]
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil];
  [alertView show];
}


#pragma mark Prepare to play asset, URL

/*
 Invoked at the completion of the loading of the values for all keys on the asset that we require.
 Checks whether loading was successfull and whether the asset is playable.
 If so, sets up an AVPlayerItem and an AVPlayer to play the asset.
 */
- (void)prepareToPlayAsset:(AVURLAsset *)asset withKeys:(NSArray *)requestedKeys {
  // Make sure that the value of each key has loaded successfully.
  for (NSString *thisKey in requestedKeys) {
    NSError *error = nil;
    AVKeyValueStatus keyStatus = [asset statusOfValueForKey:thisKey error:&error];
    if (keyStatus == AVKeyValueStatusFailed) {
      [self assetFailedToPrepareForPlayback:error];
      return;
    }
  }
  // Use the AVAsset playable property to detect whether the asset can be played.
  if (!asset.playable) {
    // Generate an error describing the failure.
    NSString *localizedDescription =
        NSLocalizedString(@"Item cannot be played", @"Item cannot be played description");
    NSString *localizedFailureReason =
        NSLocalizedString(@"The assets tracks were loaded, but could not be made playable.",
                          @"Item cannot be played failure reason");
    NSDictionary *errorDict = [NSDictionary dictionaryWithObjectsAndKeys:
                               localizedDescription, NSLocalizedDescriptionKey,
                               localizedFailureReason, NSLocalizedFailureReasonErrorKey,
                               nil];
    NSError *assetCannotBePlayedError = [NSError errorWithDomain:@"StitchedStreaplayer"
                                                            code:0
                                                        userInfo:errorDict];
    // Display the error to the user.
    [self assetFailedToPrepareForPlayback:assetCannotBePlayedError];
    return;
  }

  // Stop observing our prior AVPlayerItem, if we have one.
  if (_playerItem) {
    // Remove existing player item key value observers and notifications.
    [_playerItem removeObserver:self forKeyPath:@"status"];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:_playerItem];
  }
  _playerItem = [AVPlayerItem playerItemWithAsset:asset];
  [_playerItem addObserver:self
                     forKeyPath:@"status"
                        options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                        context:PlaybackViewControllerStatusObservationContext];
  // When the player item has played to its end time we'll toggle the movie controller Pause button.
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(playerItemDidReachEnd:)
                                               name:AVPlayerItemDidPlayToEndTimeNotification
                                             object:_playerItem];

  _seekToZeroBeforePlay = NO;
  // Create new player, if we don't already have one.
  if (!_player) {
    [self setPlayer:[AVPlayer playerWithPlayerItem:_playerItem]];
    /* Observe the AVPlayer "currentItem" property to find out when any
     AVPlayer replaceCurrentItemWithPlayerItem: replacement will/did
     occur". */
    [_player addObserver:self
                  forKeyPath:@"currentItem"
                     options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                     context:PlaybackViewControllerCurrentItemObservationContext];

    // Observe the AVPlayer "rate" property to update the scrubber control.
    [_player addObserver:self
                  forKeyPath:@"rate"
                     options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                     context:PlaybackViewControllerRateObservationContext];
  }
  if (_player.currentItem != _playerItem) {
    /* Replace the player item with a new player item. The item replacement occurs
     asynchronously; observe the currentItem property to find out when the
     replacement will/did occur.
     */
    [_player replaceCurrentItemWithPlayerItem:_playerItem];
  }
  if (_resumeTime) {
    [_player seekToTime:(CMTimeMakeWithSeconds(_resumeTime, NSEC_PER_SEC))];
  }
  [_player play];
}

#pragma mark -
#pragma mark Asset Key Value Observing
#pragma mark

#pragma mark Key Value Observer for player rate, currentItem, player item status

- (void)observeValueForKeyPath:(NSString *)path
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (context == PlaybackViewControllerStatusObservationContext) {
    AVPlayerItemStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
    switch (status) {
        /* Indicates that the status of the player is not yet known because
         it has not tried to load new media resources for playback. */
      case AVPlayerItemStatusUnknown: {
        [self removePlayerTimeObserver];
      }
        break;
      case AVPlayerItemStatusReadyToPlay: {
        /* Once the AVPlayerItem becomes ready to play, i.e.
         [playerItem status] == AVPlayerItemStatusReadyToPlay,
         its duration can be fetched from the item. */
        [self configScrubber];
      }
        break;
      case AVPlayerItemStatusFailed: {
        AVPlayerItem *playerItem = (AVPlayerItem *)object;
        [self assetFailedToPrepareForPlayback:playerItem.error];
      }
        break;
    }
  } else if (context == PlaybackViewControllerRateObservationContext) {
    // TODO(seawardt): Handle Bit rate changes
  } else if (context == PlaybackViewControllerCurrentItemObservationContext) {
    AVPlayerItem *newPlayerItem = [change objectForKey:NSKeyValueChangeNewKey];
    [_playbackView setPlayer:_player];
    /* Specifies that the player should preserve the video’s aspect ratio and
       fit the video within the layer’s bounds. */
    [_playbackView setVideoFillMode:AVLayerVideoGravityResizeAspect];
  } else {
    [super observeValueForKeyPath:path ofObject:object change:change context:context];
  }
}

@end
