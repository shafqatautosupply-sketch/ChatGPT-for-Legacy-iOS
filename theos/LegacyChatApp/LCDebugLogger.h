#import <Foundation/Foundation.h>

@interface LCDebugLogger : NSObject

+ (void)setupCrashHandler;
+ (void)logDebug:(NSString *)message;
+ (NSString *)logFilePath;

@end
