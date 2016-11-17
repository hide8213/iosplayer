// Copyright 2015 Google Inc. All rights reserved.

#import "MediaCell.h"

static NSString *const kNormalStateIconName = @"ico_download_before.png";
static NSString *const kDownloadedStateIconName = @"ico_download_after.png";
static CGFloat kImageSize = 40;

@implementation MediaCell {
  UILabel *_downloadPercentLabel;
  UIButton *_licenseButton;
  UIButton *_offlineButton;
  UITapGestureRecognizer *_tap;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    _downloadPercentLabel = [[UILabel alloc] init];
    _licenseButton = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
    _offlineButton = [[UIButton alloc] init];
    _licenseButton.hidden = YES;
    _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didPressPlay)];
    [self.textLabel setUserInteractionEnabled:YES];
    // Set corner radius to arbitrary value based on visual appeal.
    self.imageView.layer.cornerRadius = 4;
    self.imageView.layer.masksToBounds = YES;
    [self addSubview:_licenseButton];
    [self addSubview:_offlineButton];
    [self addSubview:_downloadPercentLabel];

    [self setConstraints:_offlineButton
               attribute:NSLayoutAttributeCenterY
                constant:0];
    [self setConstraints:_offlineButton
               attribute:NSLayoutAttributeTrailing
                constant:-5];

    [self setConstraints:_downloadPercentLabel
               attribute:NSLayoutAttributeCenterY
                constant:0];
    [self setConstraints:_downloadPercentLabel
               attribute:NSLayoutAttributeTrailing
                constant:-45];

    [self setConstraints:_licenseButton
               attribute:NSLayoutAttributeCenterY
                constant:0];
    [self setConstraints:_licenseButton
               attribute:NSLayoutAttributeTrailing
                constant:-45];

  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.thumbnail = nil;
  [self.textLabel removeGestureRecognizer:_tap];
  [_offlineButton removeTarget:self action:NULL forControlEvents:UIControlEventAllEvents];
  [_downloadPercentLabel setHidden:YES];
}

#pragma mark - Load View

- (void)updateDisplay {
  if (!self.imageView.image) {
    [self setThumbnail:_thumbnail];
  }
  if (_filesBeingDownloaded.count == 0 && _isDownloaded) {
    // Completed Downloads - Ready for Offline
    [self.textLabel addGestureRecognizer:_tap];
    [self.textLabel setTextColor:[self offlineColor]];
    [_offlineButton addTarget:self
                       action:@selector(didPressDelete)
             forControlEvents:UIControlEventTouchUpInside];
    [_offlineButton setBackgroundImage:[UIImage imageNamed:kDownloadedStateIconName]
                              forState:UIControlStateNormal];
    [_licenseButton addTarget:self
                       action:@selector(didPressLicense)
             forControlEvents:UIControlEventTouchUpInside];
    _licenseButton.hidden = NO;
    return;
  }
  if (_filesBeingDownloaded.count > 0) {
    // Currently being downloaded -- Disable ability to play
    [self.textLabel setTextColor:[UIColor grayColor]];
    [_downloadPercentLabel setHidden:NO];
    [_downloadPercentLabel setText:[NSString stringWithFormat:@"%d%%", _percentage]];
    return;
  }
  // Streaming Files
  [self.textLabel addGestureRecognizer:_tap];
  [self.textLabel setTextColor:[self streamingColor]];
  [_offlineButton setBackgroundImage:[UIImage imageNamed:kNormalStateIconName]
                            forState:UIControlStateNormal];
  [_offlineButton addTarget:self
                     action:@selector(didPressDownload)
           forControlEvents:UIControlEventTouchUpInside];
  _licenseButton.hidden = YES;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self.contentView setNeedsLayout];
  [self.contentView layoutIfNeeded];
}

- (void)setConstraints:(UIView *)element
             attribute:(NSLayoutAttribute)attribute
              constant:(CGFloat)constant {
  [element setTranslatesAutoresizingMaskIntoConstraints:NO];
  [self addConstraint:[NSLayoutConstraint constraintWithItem:element
                                                   attribute:attribute
                                                   relatedBy:NSLayoutRelationEqual
                                                      toItem:self
                                                   attribute:attribute
                                                  multiplier:1.0
                                                    constant:constant]];
}

- (UIColor *)streamingColor {
  return [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:1.0 alpha:1.0];
}

- (UIColor *)offlineColor {
  return [UIColor colorWithRed:255.0 / 255.0 green:127.0 / 255.0 blue:0.0 alpha:1.0];
}

- (void)setThumbnail:(UIImage *)image {
  // Resize and scale downloaded image, then add to ImageView.
  // Size set to cell height.
  // TODO(seawardt): Change to use CoreGraphics
  if (image) {
    CGSize size = CGSizeMake(kImageSize, kImageSize);
    UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    self.imageView.image = thumbnail;
    [self setNeedsLayout];
  } else {
    self.imageView.image = nil;
  }
}

#pragma mark - Player Methods

- (void)didPressDelete {
  [_delegate didPressDelete:self];
}

- (void)didPressDownload {
  [_delegate didPressDownload:self];
}

- (void)didPressLicense {
  [_delegate didPressLicense:self];
}

- (void)didPressPlay {
  [_delegate didPressPlay:self];
}

@end
