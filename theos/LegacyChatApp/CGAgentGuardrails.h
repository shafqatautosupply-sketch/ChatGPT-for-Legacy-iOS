#import <Foundation/Foundation.h>

@interface CGAgentGuardrails : NSObject

+ (NSSet *)allowedBinaries;
+ (NSArray *)hardBlockPaths;
+ (NSArray *)secretPaths;
+ (NSArray *)obfuscationBlocks;
+ (BOOL)isCommandSafe:(NSString *)command reason:(NSString **)reasonOut;
+ (BOOL)isPathAllowed:(NSString *)pathstr;

@end
