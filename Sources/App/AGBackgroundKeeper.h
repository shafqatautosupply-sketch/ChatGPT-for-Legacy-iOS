#import <Foundation/Foundation.h>

/// Keeps the app running while an agent task is in progress and the user has left the app
/// (home button, lock, switching apps). Without this iOS suspends the process after a few
/// seconds and the task stalls.
///
/// Two layers, both only while a task is running:
///  * Info.plist asks for the private background modes `continuous` and `unboundedTaskCompletion`
///    (jailbroken iOS honours them; the App Store would not), which keep the process running or
///    lift the ~10 minute limit of background tasks.
///  * A background task assertion is held while the task runs and released when it ends.
/// There is no audio trick any more. The debug log records `backgroundTimeRemaining` when the app
/// goes to the background ("unlimited" = the plist modes are in effect).
///
/// Switch: `agent_background_enabled` (default YES).
@interface AGBackgroundKeeper : NSObject

+ (void)install;
+ (BOOL)enabled;

@end
