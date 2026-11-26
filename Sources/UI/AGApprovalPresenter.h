#import <Foundation/Foundation.h>

/// The screen side of AGApproval.
///  * App in the foreground: an alert inside the app (Deny / Allow once / Allow for this task).
///  * App in the background or the phone locked: a SYSTEM dialog (CFUserNotification, shown by
///    SpringBoard) over whatever the person is doing, so the agent can ask without the app
///    being opened. The same three buttons; the agent thread waits for the tap.
///  * If the system dialog cannot be shown (sandbox, API missing, switched off), a local
///    notification is posted instead and the question waits inside the app.
/// It also posts a local notification when a task finishes while the app is in the background.
@interface AGApprovalPresenter : NSObject

+ (void)install;

/// A yes/no question shown the same way as an approval: an alert in the app, a system dialog when
/// the app is not visible, a notification as the last resort. Used for "Allow web access?".
/// `answer` gets Allow, Deny, or TimedOut (nobody answered within `timeout`); it is NOT called for a
/// question taken back with +cancelQuestion:. Any thread. Returns a handle for +cancelQuestion:.
+ (id)askQuestionWithTitle:(NSString *)title detail:(NSString *)detail allowTitle:(NSString *)allowTitle timeout:(NSTimeInterval)timeout answer:(void (^)(NSInteger answer))answer;
/// Takes a question that is still waiting off the screen. Any thread.
+ (void)cancelQuestion:(id)handle;

/// `agent_global_prompts`, default YES: use the system dialog when the app is not visible.
+ (BOOL)globalDialogsEnabled;

/// Settings > Test: asks a harmless question after 6 seconds so the person can press Home
/// first and see which kind of prompt appears. The outcome is shown in an alert.
+ (void)runTestPrompt;

@end
