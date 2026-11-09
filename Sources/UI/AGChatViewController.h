#import <UIKit/UIKit.h>

@interface AGChatViewController : UIViewController <UITextViewDelegate>

@property (nonatomic, retain) NSMutableArray *messages;
@property (nonatomic, retain) NSMutableArray *allMessages;

@end
