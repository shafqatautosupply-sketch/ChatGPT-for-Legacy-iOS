#import <Foundation/Foundation.h>

@interface CGAgentTools : NSObject

+ (NSString *)executeShellCommand:(NSString *)command workspaceDirectory:(NSString *)workspaceDir;
+ (NSString *)writeFileAtPath:(NSString *)path content:(id)content workspaceDirectory:(NSString *)workspaceDir;

@end
