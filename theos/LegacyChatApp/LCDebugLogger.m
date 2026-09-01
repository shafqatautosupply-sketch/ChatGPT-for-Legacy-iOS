#import "LCDebugLogger.h"
#import <UIKit/UIKit.h>
#import <libkern/OSAtomic.h>

@implementation LCDebugLogger

+ (NSString *)logFilePath {
	return @"/tmp/LegacyChatApp_debug.log";
}

+ (void)logDebug:(NSString *)message {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *timestamp = [[NSDate date] description];
	NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
	
	NSString *path = [self logFilePath];
	NSFileManager *fm = [NSFileManager defaultManager];
	
	@synchronized(self) {
		if (![fm fileExistsAtPath:path]) {
			[logEntry writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
		} else {
			NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
			[handle seekToEndOfFile];
			[handle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
			[handle closeFile];
		}
	}
	NSLog(@"[LCDebugLogger] %@", message);
	[pool drain];
}

void LCUncaughtExceptionHandler(NSException *exception) {
	NSArray *stackTrace = [exception callStackSymbols];
	NSString *reason = [exception reason];
	NSString *name = [exception name];
	
	NSString *crashReport = [NSString \
		stringWithFormat:@"\n=== CRASH EXCEPTION ===\nName: %@\nReason: %@\nStack Trace:\n%@\n=======================\n",
		name, reason, [stackTrace componentsJoinedByString:@"\n"]];
		
	[LCDebugLogger logDebug:crashReport];
}

void LCSignalHandler(int signal) {
	NSString *signalReport = [NSString stringWithFormat:@"\n=== CRASH SIGNAL %d ===\n", signal];
	[LCDebugLogger logDebug:signalReport];
}

+ (void)setupCrashHandler {
	NSSetUncaughtExceptionHandler(&LCUncaughtExceptionHandler);
	signal(SIGABRT, LCSignalHandler);
	signal(SIGILL, LCSignalHandler);
	signal(SIGSEGV, LCSignalHandler);
	signal(SIGFPE, LCSignalHandler);
	signal(SIGBUS, LCSignalHandler);
	signal(SIGPIPE, LCSignalHandler);
	
	[self logDebug:@"=== Debug logger & crash handler initialized ==="];
}

@end
