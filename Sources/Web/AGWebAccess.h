#import <Foundation/Foundation.h>
#import "AGWebBridge.h"

/// Posted (main thread) when the web server starts, stops, fails or changes port.
extern NSString * const AGWebAccessChangedNotification;

/// Owns the web server: the on/off switch in Settings, the port, and the list of addresses to type
/// into the other device's browser. Foundation-only.
@interface AGWebAccess : NSObject

/// `web_access_enabled`, default NO. Setting it starts or stops the server.
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;

/// `web_access_port`, default 8080 (1024...65535).
+ (NSUInteger)port;
+ (BOOL)setPort:(NSUInteger)port;   // NO if out of range

+ (BOOL)isRunning;
/// Why the server is not running although it is switched on (port in use...), else nil.
+ (NSString *)lastError;
/// "http://192.168.1.20:8080" for every active network interface (Wi-Fi first), empty when offline.
+ (NSArray *)addressURLs;

/// The chat screen that the web page talks to. Set once at launch.
+ (void)setBridge:(id<AGWebBridge>)bridge;
/// Call at launch: starts the server if it was left on.
+ (void)startIfEnabled;

/// Where the page lives inside the app (Resources/agentic-web.html); tests override it.
+ (void)setPagePathForTesting:(NSString *)path;

@end
