#import <Foundation/Foundation.h>

/// Policy layer for the agent tools: what may run, where it may touch files.
///
/// Threat model (be honest about it): the model is not trusted, and neither is
/// any text it read (files, tool output = prompt injection). The shell tool
/// therefore never goes through /bin/sh, so there is no injection surface
/// ($(), backticks, redirects, globs, ~ and $VAR all do nothing). On top of that:
/// a binary whitelist, a symlink-aware path jail, and per-binary argument
/// checks for the flags that turn an innocent tool into a command runner.
///
/// Known limit: `make` and the compilers are Turing-complete (a Makefile can run
/// anything). Guardrails cannot fix that; they keep a confused or injected model
/// away from *accidental* damage and from paths outside the workspace.
@interface AGGuardrails : NSObject

// --- Configuration (single source of truth; the settings UI reads these) ---
+ (NSArray *)defaultAllowedBinaries;
+ (NSArray *)defaultHardBlockPaths;
+ (NSArray *)defaultSecretPaths;
+ (NSArray *)defaultPreExecutionCommands;

/// User list if one is saved, otherwise the defaults.
+ (NSSet *)allowedBinaries;
/// Built-in list UNION user additions: the user can add protection, never remove it.
+ (NSArray *)hardBlockPaths;
+ (NSArray *)secretPaths;

+ (NSString *)workspaceDirectory;   // created on demand, falls back to ~/Documents/SandBox
+ (NSString *)theosDirectory;
+ (NSArray *)allowedRoots;          // canonical: workspace + Theos

// --- Path checks ---
/// Resolves `path` (relative paths are relative to `base`) and checks it against
/// the jail. Returns the canonical path, or nil with `reason` filled in.
+ (NSString *)authorizePath:(NSString *)path
                 relativeTo:(NSString *)base
                   forWrite:(BOOL)write
                     reason:(NSString **)reason;

// --- Command checks ---
/// Absolute path of an allowed binary found on the fixed exec PATH, or nil.
+ (NSString *)resolveBinary:(NSString *)name;
+ (NSArray *)execSearchPath;

/// Validates one parsed command (argv[0] is the bare binary name).
+ (BOOL)validateArgv:(NSArray *)argv cwd:(NSString *)cwd reason:(NSString **)reason;

@end
