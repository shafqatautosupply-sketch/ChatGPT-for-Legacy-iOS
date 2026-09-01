#import "LCAppDelegate.h"
#import "CGAPIHelper.h"
#import "LCChatViewController.h"
#import "LCDebugLogger.h"

@implementation LCAppDelegate

@synthesize window = _window;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	[LCDebugLogger setupCrashHandler];
	[LCDebugLogger logDebug:@"Application didFinishLaunchingWithOptions started"];

	[CGAPIHelper registerProviderDefaults];

	self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];

	LCChatViewController *rootViewController = [[[LCChatViewController alloc] init] autorelease];
	UINavigationController *navigationController = [[[UINavigationController alloc] initWithRootViewController:rootViewController] autorelease];
	
	// iOS 6 Native Classic Gradient/Blue tint color for navigation bars
	if ([navigationController.navigationBar respondsToSelector:@selector(setTintColor:)]) {
		[navigationController.navigationBar setTintColor:[UIColor colorWithRed:0.298f green:0.396f blue:0.514f alpha:1.0f]];
	}

	if ([navigationController.navigationBar respondsToSelector:@selector(setTitleTextAttributes:)]) {
		NSDictionary *titleAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIColor whiteColor], UITextAttributeTextColor,
			[UIColor colorWithWhite:0.0f alpha:0.5f], UITextAttributeTextShadowColor,
			[NSValue valueWithUIOffset:UIOffsetMake(0.0f, -1.0f)], UITextAttributeTextShadowOffset,
			[UIFont boldSystemFontOfSize:20.0f], UITextAttributeFont,
			nil];
		[navigationController.navigationBar setTitleTextAttributes:titleAttributes];
	}

	self.window.rootViewController = navigationController;
	[self.window makeKeyAndVisible];
	[LCDebugLogger logDebug:@"Application didFinishLaunchingWithOptions completed successfully"];
	return YES;
}

- (void)dealloc {
	[_window release];
	[super dealloc];
}

@end
