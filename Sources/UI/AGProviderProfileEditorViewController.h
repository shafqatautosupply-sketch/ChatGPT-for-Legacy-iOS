#import <UIKit/UIKit.h>

@interface AGProviderProfileEditorViewController : UITableViewController <UITextFieldDelegate>

- (id)initForNewProfile;
- (id)initWithProfile:(NSDictionary *)profile;

@end
