#import <Foundation/Foundation.h>

@interface AGDebugLogger : NSObject

+ (void)setupCrashHandler;
+ (void)logDebug:(NSString *)message;
+ (NSString *)logFilePath;

@end
