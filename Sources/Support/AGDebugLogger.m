#import "AGDebugLogger.h"
#import <UIKit/UIKit.h>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

static int g_logFD = -1;
static const unsigned long long AGMaxLogBytes = 256 * 1024;

@implementation AGDebugLogger

+ (NSString *)logFilePath {
	NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *directory = [library stringByAppendingPathComponent:@"LegacyChatApp"];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
	return [directory stringByAppendingPathComponent:@"debug.log"]; // was /tmp (readable by every process)
}

+ (void)logDebug:(NSString *)message {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *entry = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
	NSString *path = [self logFilePath];
	@synchronized(self) {
		NSFileManager *fm = [NSFileManager defaultManager];
		NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
		if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > AGMaxLogBytes) [fm removeItemAtPath:path error:nil]; // never grows without bound
		if (![fm fileExistsAtPath:path]) {
			[entry writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
		} else {
			NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
			[handle seekToEndOfFile];
			[handle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
			[handle closeFile];
		}
	}
	[pool drain];
}

static void AGUncaughtExceptionHandler(NSException *exception) {
	[AGDebugLogger logDebug:[NSString stringWithFormat:@"\n=== CRASH EXCEPTION ===\nName: %@\nReason: %@\nStack:\n%@\n",
		[exception name], [exception reason], [[exception callStackSymbols] componentsJoinedByString:@"\n"]]];
}

/// Async-signal-safe: only write(), backtrace_symbols_fd(), signal() and raise().
/// The previous handler called Objective-C (allocation, locks) from the signal
/// context and then RETURNED. Returning from SIGSEGV re-runs the faulting
/// instruction, so a crash turned into an infinite loop that froze the app and
/// grew the log forever.
static void AGSignalHandler(int sig) {
	if (g_logFD >= 0) {
		static const char banner[] = "\n=== CRASH SIGNAL ===\n";
		write(g_logFD, banner, sizeof(banner) - 1);
		char number[12]; int n = 0, value = sig;
		char reversed[12]; int r = 0;
		do { reversed[r++] = (char)('0' + value % 10); value /= 10; } while (value > 0 && r < 11);
		while (r > 0) number[n++] = reversed[--r];
		number[n++] = '\n';
		write(g_logFD, number, (size_t)n);
		void *frames[48];
		int count = backtrace(frames, 48);
		backtrace_symbols_fd(frames, count, g_logFD);
	}
	signal(sig, SIG_DFL);
	raise(sig); // let the system produce its normal crash report
}

+ (void)setupCrashHandler {
	g_logFD = open([[self logFilePath] fileSystemRepresentation], O_WRONLY | O_CREAT | O_APPEND, 0600);
	NSSetUncaughtExceptionHandler(&AGUncaughtExceptionHandler);
	signal(SIGABRT, AGSignalHandler);
	signal(SIGILL, AGSignalHandler);
	signal(SIGSEGV, AGSignalHandler);
	signal(SIGFPE, AGSignalHandler);
	signal(SIGBUS, AGSignalHandler);
	signal(SIGPIPE, SIG_IGN); // a closed pipe/socket is an error code, not a reason to stop
	[self logDebug:@"=== Debug logger & crash handler initialized ==="];
}

@end
