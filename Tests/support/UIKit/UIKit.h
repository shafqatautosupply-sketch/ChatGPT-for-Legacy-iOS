// Tiny UIKit stand-in: only what AGGeminiClient needs, so the agent loop can be tested on a dev machine.
#import <Foundation/Foundation.h>
@interface UIApplication : NSObject { BOOL _indicator; } + (UIApplication *)sharedApplication; @property BOOL networkActivityIndicatorVisible; @end
@implementation UIApplication + (UIApplication *)sharedApplication { static UIApplication *a; if (!a) a = [[UIApplication alloc] init]; return a; } @synthesize networkActivityIndicatorVisible = _indicator; @end
