@class MediaCell;

@protocol MasterViewControllerDelegate

- (void)didPressDelete:(MediaCell *)cell;
- (void)didPressDownload:(MediaCell *)cell;
- (void)didPressPlay:(MediaCell *)cell;

@end

@interface MediaCell : UITableViewCell
@property(nonatomic, weak) id<MasterViewControllerDelegate> delegate;
@property BOOL isDownloaded;
@property(nonatomic, copy) NSArray *filesBeingDownloaded;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, assign) int percentage;

- (void)updateDisplay;

@end
