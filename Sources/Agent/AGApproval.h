#import <Foundation/Foundation.h>

/// Human-in-the-loop gate for the two things the path jail cannot judge:
/// programs that run code (make, python) and deleting files.
///
/// This file is Foundation-only. The UI (alert, local notification when the app is in
/// the background) is plugged in with +setHandler: by AGApprovalPresenter. With no
/// handler installed every request is DENIED, so tests and headless runs fail safe.
typedef enum {
	AGApprovalDeny = 0,
	AGApprovalAllowOnce = 1,
	AGApprovalAllowForTask = 2   // remembered until the next agent run starts or Stop is tapped
} AGApprovalChoice;

typedef void (^AGApprovalResponder)(AGApprovalChoice choice);

/// Called on the agent's worker thread. `respond` may be called from any thread, once
/// (later calls are ignored). Copy it (Block_copy / -copy) if you keep it past the call. `taskLabel` is nil when "allow for this task" is not offered.
typedef void (^AGApprovalHandler)(NSString *title, NSString *detail, NSString *taskLabel, AGApprovalResponder respond);

/// Posted (on the calling thread) when a waiting request is abandoned (Stop, timeout),
/// so the UI can take the prompt away.
extern NSString * const AGApprovalAbandonedNotification;

/// Posted (on the calling thread) when a question starts or stops waiting for the person, so a
/// remote view can say "waiting for you on the phone". Only the TITLE is exposed through
/// +pendingTitle, never the command or file contents in the prompt: those are shown on the phone only.
extern NSString * const AGApprovalPendingChangedNotification;

@interface AGApproval : NSObject

+ (void)setHandler:(AGApprovalHandler)handler;

/// Title of the question that is waiting for an answer right now (e.g. "Run make?"), or nil.
+ (NSString *)pendingTitle;

// --- Settings (NSUserDefaults) ---
/// `agent_confirm_code`, default YES: ask before make / python.
+ (BOOL)confirmCodeEnabled;
/// `agent_confirm_delete`, default YES: ask before moving something to the trash.
+ (BOOL)confirmDeleteEnabled;
/// Seconds to wait for an answer before treating it as "deny" (default 600).
+ (NSTimeInterval)timeout;

// --- Which commands are gated ---
/// Built-in list (make, python, python2, python2.7, python3) UNION user additions
/// under `agent_confirm_binaries`. The user can add to it, never shrink it.
+ (NSSet *)gatedBinaries;
+ (BOOL)argvNeedsApproval:(NSArray *)argv;
/// Text for the prompt: the command, the folder, and the first lines of the script
/// (python) or Makefile (make) that is about to run. Bounded and control-char free.
+ (NSString *)describeArgv:(NSArray *)argv cwd:(NSString *)cwd;

// --- Asking ---
/// Blocks the calling (worker) thread until the person answers. Returns YES to go ahead.
/// On NO, `denial` holds the text to give the model. `taskKey` (e.g. "python3") enables
/// "allow for this task"; pass nil to always ask.
+ (BOOL)requestApprovalForKey:(NSString *)taskKey
                        title:(NSString *)title
                       detail:(NSString *)detail
                    taskLabel:(NSString *)taskLabel
                  isCancelled:(BOOL (^)(void))cancelled
                       denial:(NSString **)denial;

/// Forget every "allow for this task". Called when a run starts or is stopped.
+ (void)resetTaskApprovals;

@end
