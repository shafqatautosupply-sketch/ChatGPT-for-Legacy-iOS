#import <Foundation/Foundation.h>

/// Runs the model's `runShellCommand` requests WITHOUT a shell.
///
/// Supported: simple commands, quoting ('..' ".." \x), `*`/`?`/`[..]` globbing
/// (expanded in-process), `cd`/`pwd` builtins, and `a && b && c` chains (stop at
/// the first failure). Anything else that /bin/sh would interpret
/// (`; | & < > $ ` ( )`) is rejected with a message the model can act on.
@interface AGShellRunner : NSObject

/// Parses a command line into commands; each command is an array of
/// {@"s": NSString, @"glob": NSNumber(BOOL)} tokens. nil + error on bad syntax.
+ (NSArray *)parseCommandLine:(NSString *)line error:(NSString **)error;

/// Validates and runs `line` inside `workspace`. Always returns text for the model.
/// `cancelled` may be nil; it is polled ~10x/second while a child runs.
+ (NSString *)runCommandLine:(NSString *)line
                   workspace:(NSString *)workspace
                 isCancelled:(BOOL (^)(void))cancelled;

@end
