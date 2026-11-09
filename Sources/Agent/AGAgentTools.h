#import <Foundation/Foundation.h>

/// The model-facing tools: runShellCommand, readFile, writeFile, editFile.
/// Every path goes through AGGuardrails/AGPathJail; every result is bounded.
@interface AGAgentTools : NSObject

/// Gemini `functionDeclarations` payload (kept short: it is sent with every request).
+ (NSArray *)toolDeclarations;

/// Runs one tool call. `arguments` comes straight from the model and may have
/// any shape; bad input yields an error string, never an exception.
+ (NSString *)executeToolNamed:(NSString *)name
                     arguments:(id)arguments
                     workspace:(NSString *)workspace
                   isCancelled:(BOOL (^)(void))cancelled;

+ (NSString *)readFileAtPath:(NSString *)path lineStart:(NSInteger)lineStart lineEnd:(NSInteger)lineEnd workspace:(NSString *)workspace;
+ (NSString *)writeFileAtPath:(NSString *)path content:(id)content workspace:(NSString *)workspace;
+ (NSString *)editFileAtPath:(NSString *)path oldText:(NSString *)oldText newText:(NSString *)newText replaceAll:(BOOL)replaceAll workspace:(NSString *)workspace;

/// Max characters of one tool result sent to the model (default 8000).
+ (NSUInteger)toolOutputLimit;

/// Keeps the beginning AND the end of long text (errors are usually at the end
/// of build output) and says how much was dropped.
+ (NSString *)clipText:(NSString *)text toLimit:(NSUInteger)limit tailFraction:(double)tailFraction;

@end
