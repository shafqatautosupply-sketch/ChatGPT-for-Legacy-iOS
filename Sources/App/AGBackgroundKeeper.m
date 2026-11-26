#import "AGBackgroundKeeper.h"
#import "AGChatClient.h"
#import "AGDebugLogger.h"
#import "AGWebAccess.h"
#import <UIKit/UIKit.h>
#include <string.h>

@interface AGBackgroundKeeper () {
	BOOL _running;
	UIBackgroundTaskIdentifier _task;
}
@end

@implementation AGBackgroundKeeper

+ (BOOL)enabled {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_background_enabled"];
	return (value != nil && [value respondsToSelector:@selector(boolValue)]) ? [value boolValue] : YES;
}

+ (void)install {
	static AGBackgroundKeeper *keeper = nil;
	if (keeper != nil) return;
	keeper = [[AGBackgroundKeeper alloc] init];   // lives for the whole process
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:keeper selector:@selector(statusChanged:) name:AGAPIStatusDidChangeNotification object:nil];
	[center addObserver:keeper selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
	[center addObserver:keeper selector:@selector(willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
	// The web page must keep answering while the app is not on screen.
	[center addObserver:keeper selector:@selector(webAccessChanged:) name:AGWebAccessChangedNotification object:nil];
}

- (id)init {
	self = [super init];
	if (self) _task = UIBackgroundTaskInvalid;
	return self;
}

#pragma mark - Events (all on the main thread)

- (void)statusChanged:(NSNotification *)note {
	_running = [[note object] boolValue];
	[self refreshInBackground:([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)];
}

- (void)didEnterBackground:(NSNotification *)note { [self refreshInBackground:YES]; }
- (void)webAccessChanged:(NSNotification *)note { [self refreshInBackground:([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)]; }
- (void)willEnterForeground:(NSNotification *)note { [self refreshInBackground:NO]; }

- (void)refreshInBackground:(BOOL)inBackground {
	BOOL keep = (_running || [AGWebAccess isRunning]) && [AGBackgroundKeeper enabled];
	if (keep) [self beginTask]; else [self endTask];
	if (keep && inBackground) {
		// Diagnostic: a huge number means iOS is not limiting the process (continuous/unbounded worked).
		NSTimeInterval left = [UIApplication sharedApplication].backgroundTimeRemaining;
		[AGDebugLogger logDebug:[NSString stringWithFormat:@"Background keeper: task running in background, backgroundTimeRemaining=%@",
			(left > 100000.0) ? @"unlimited" : [NSString stringWithFormat:@"%.0fs", left]]];
	}
}

#pragma mark - Background task assertion

- (void)beginTask {
	if (_task != UIBackgroundTaskInvalid) return;
	_task = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
		// Time is up. Ending the task is mandatory (otherwise iOS kills the app); the silent
		// audio, if it is playing, keeps the process alive after this.
		[self endTask];
	}];
}

- (void)endTask {
	if (_task == UIBackgroundTaskInvalid) return;
	UIBackgroundTaskIdentifier task = _task;
	_task = UIBackgroundTaskInvalid;
	[[UIApplication sharedApplication] endBackgroundTask:task];
}

@end
