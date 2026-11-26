#import <Foundation/Foundation.h>
#include <stdint.h>

/// Exit status a sandboxed child uses when sandbox_init() fails; the command was NOT run.
#define AGSandboxFailExit 253

typedef int (*AGSandboxInitFn)(const char *profile, uint64_t flags, char **errorbuf);

/// Kernel-enforced confinement (Seatbelt, via sandbox_init) for the programs the agent runs.
///
/// The profile is applied in the forked child right before execve(). It is inherited by
/// everything that child starts, cannot be loosened afterwards, and does not need root.
/// Measured on iOS 6.1.3 (see Docs/SECURITY.md): the child
///  * can write only inside the workspace (plus /dev/null and /var/tmp, which iOS exempts),
///  * cannot read anything under /var/mobile except the workspace and the read-only
///    directories (Theos, Settings > agent_sandbox_read_dirs),
///  * has no network,
///  * cannot look up Mach services (launchd, SpringBoard, ...).
/// NOT covered: ptrace/kill/signals against other processes of the same user, and the
/// exec policy (process-exec rules are ignored by this kernel). The approval prompts stay.
///
/// Settings (NSUserDefaults, all optional):
///   agent_sandbox               BOOL, default YES
///   agent_sandbox_deny_network  BOOL, default YES
///   agent_sandbox_deny_mach     BOOL, default YES  (set NO if a tool needs Mach services)
///   agent_sandbox_read_dirs     NSArray of absolute paths the commands may read
@interface AGSandbox : NSObject

/// sandbox_init, resolved once. NULL on systems that do not have it.
+ (AGSandboxInitFn)initFunction;

/// Builds the profile text for `workspace`. nil + reason if it cannot be done safely
/// (workspace is "/" or contains the whole home folder, odd characters in a path...).
+ (NSString *)profileForWorkspace:(NSString *)workspace reason:(NSString **)reason;

/// YES when the setting is on AND this system has sandbox_init(): a failure to actually apply
/// the sandbox is then worth telling the model/user about (on other systems it is just absent).
+ (BOOL)isExpected;

/// Honours the settings, builds the profile and PROVES (once per profile) that the kernel
/// enforces it: a throw-away child applies it and must be refused when it writes outside.
/// YES + profile: run commands with it. NO + reason: run without (and `rm` stays off).
+ (BOOL)prepareForWorkspace:(NSString *)workspace profile:(NSString **)profile reason:(NSString **)reason;

@end
