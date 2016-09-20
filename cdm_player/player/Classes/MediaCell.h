// Copyright 2015 Google Inc. All rights reserved.

@class MediaCell;
@class MediaCellImage;

@protocol MediaCellDelegate

- (void)didPressDelete:(MediaCell *)cell;
- (void)didPressDownload:(MediaCell *)cell;
- (void)didPressLicense:(MediaCell *)cell;
- (void)didPressPlay:(MediaCell *)cell;

@end

@interface MediaCell : UITableViewCell
@property(nonatomic, weak) id<MediaCellDelegate> delegate;
@property BOOL isDownloaded;
@property(nonatomic, copy) NSArray *filesBeingDownloaded;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) UIImage *thumbnail;
@property(nonatomic, assign) int percentage;

- (void)updateDisplay;

@end
