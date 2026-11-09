#import <UIKit/UIKit.h>

@class AGConversation;
@class AGConversationsViewController;

@protocol AGConversationsViewControllerDelegate <NSObject>

- (void)conversationsViewControllerDidRequestNewChat:(AGConversationsViewController *)controller;
- (void)conversationsViewController:(AGConversationsViewController *)controller didSelectConversation:(AGConversation *)conversation;

@end

@interface AGConversationsViewController : UITableViewController

@property (nonatomic, assign) id<AGConversationsViewControllerDelegate> delegate;

@end
