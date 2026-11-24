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

/// `agent_global_prompts`, default YES: use the system dialog when the app is not visible.
+ (BOOL)globalDialogsEnabled;

/// Settings > Test: asks a harmless question after 6 seconds so the person can press Home
/// first and see which kind of prompt appears. The outcome is shown in an alert.
+ (void)runTestPrompt;

@end
