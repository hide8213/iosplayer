#import "MediaCell.h"

static NSString *const kNormalStateIconName = @"ico_download_before.png";
static NSString *const kDownloadedStateIconName = @"ico_download_after.png";

@implementation MediaCell {
  UILabel *_downloadPercentLabel;
  UIButton *_offlineButton;
  UITapGestureRecognizer *_tap;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    _downloadPercentLabel = [[UILabel alloc] init];
    _offlineButton = [[UIButton alloc] init];
    _tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                   action:@selector(didPressPlay)];
    [self.textLabel setUserInteractionEnabled:YES];
    [self addSubview:_downloadPercentLabel];
    [self addSubview:_offlineButton];
  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  [self.textLabel removeGestureRecognizer:_tap];
  [_offlineButton removeTarget:self
                        action:NULL
              forControlEvents:UIControlEventAllEvents];
  [_downloadPercentLabel setHidden:YES];
}

# pragma mark - Load View

- (void)updateDisplay {
  if (_filesBeingDownloaded.count == 0 && _isDownloaded) {
    // Completed Downloads - Ready for Offline
    [self.textLabel addGestureRecognizer:_tap];
    [self.textLabel setTextColor:[self offlineColor]];
    [_offlineButton addTarget:self
                       action:@selector(didPressDelete)
             forControlEvents:UIControlEventTouchUpInside];
    [_offlineButton setBackgroundImage:[UIImage imageNamed:kDownloadedStateIconName]
                              forState:UIControlStateNormal];
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
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self.contentView setNeedsLayout];
  [self.contentView layoutIfNeeded];

  [self setConstraints:_offlineButton attribute:NSLayoutAttributeCenterY constant:0];
  [self setConstraints:_offlineButton attribute:NSLayoutAttributeTrailing constant:-5];

  [self setConstraints:_downloadPercentLabel attribute:NSLayoutAttributeCenterY constant:0];
  [self setConstraints:_downloadPercentLabel attribute:NSLayoutAttributeTrailing constant:-45];
}

- (void) setConstraints:(UIView *)element
              attribute:(NSLayoutAttribute *)attribute
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
  return [UIColor colorWithRed:0.0
                         green:122.0/255.0
                          blue:1.0
                         alpha:1.0];
}

- (UIColor *)offlineColor {
  return [UIColor colorWithRed:255.0/255.0
                  green:127.0/255.0
                   blue:0.0
                  alpha:1.0];


}


# pragma mark - Player Methods

- (void)didPressDelete {
  [_delegate didPressDelete:self];
}

- (void)didPressDownload {
  [_delegate didPressDownload:self];
}

- (void)didPressPlay {
  [_delegate didPressPlay:self];
}

@end
