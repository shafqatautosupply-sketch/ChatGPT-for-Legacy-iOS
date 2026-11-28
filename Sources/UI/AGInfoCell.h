#import <UIKit/UIKit.h>

/// A table cell with a small (i) button right after its title. Tapping the
/// button shows `infoText` in an alert, so settings do not need a paragraph of
/// explanation under them. Leave `infoText` nil and no button is shown.
@interface AGInfoCell : UITableViewCell

@property (nonatomic, copy) NSString *infoText;

@end
