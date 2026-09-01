#import <UIKit/UIKit.h>

@interface LCChatViewController : UIViewController <UITextViewDelegate>

@property (nonatomic, retain) NSMutableArray *messages;
@property (nonatomic, retain) NSMutableArray *allMessages;

@end
