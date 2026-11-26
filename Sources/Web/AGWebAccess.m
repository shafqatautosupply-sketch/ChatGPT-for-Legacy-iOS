#import "AGWebAccess.h"
#import "AGHTTPServer.h"
#import "AGWebAPI.h"
#import "AGWebPairing.h"
#include <sys/socket.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <string.h>

NSString * const AGWebAccessChangedNotification = @"AGWebAccessChangedNotification";

static NSString * const AGEnabledKey = @"web_access_enabled";
static NSString * const AGPortKey = @"web_access_port";
static const NSUInteger AGDefaultPort = 8080;

@interface AGWebAccess ()
+ (void)startServer;
+ (void)stopServer;
+ (void)postChange;
@end

static AGHTTPServer *g_server = nil;
static AGWebAPI *g_api = nil;
static id<AGWebBridge> g_bridge = nil;      // not retained: the chat screen lives for the whole process
static NSString *g_lastError = nil;
static NSString *g_pagePath = nil;

@implementation AGWebAccess

+ (void)postChange {
	dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:AGWebAccessChangedNotification object:nil]; });
}

+ (BOOL)isEnabled {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:AGEnabledKey];
	return (value != nil && [value respondsToSelector:@selector(boolValue)]) ? [value boolValue] : NO;
}

+ (NSUInteger)port {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:AGPortKey];
	NSInteger port = (value != nil && [value respondsToSelector:@selector(integerValue)]) ? [value integerValue] : (NSInteger)AGDefaultPort;
	return (port >= 1024 && port <= 65535) ? (NSUInteger)port : AGDefaultPort;
}

+ (BOOL)setPort:(NSUInteger)port {
	if (port < 1024 || port > 65535) return NO;
	if (port == [self port]) return YES;
	[[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)port forKey:AGPortKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	if ([self isEnabled]) { [self stopServer]; [self startServer]; } else [self postChange];
	return YES;
}

+ (void)setEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:AGEnabledKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	if (enabled) [self startServer]; else [self stopServer];
}

+ (void)setBridge:(id<AGWebBridge>)bridge {
	@synchronized(self) { g_bridge = bridge; if (g_api != nil) g_api.bridge = bridge; }
}

+ (void)setPagePathForTesting:(NSString *)path {
	@synchronized(self) { [g_pagePath release]; g_pagePath = [path copy]; }
}

+ (void)startIfEnabled { if ([self isEnabled]) [self startServer]; }

+ (BOOL)isRunning { @synchronized(self) { return g_server != nil && [g_server isRunning]; } }
+ (NSString *)lastError { @synchronized(self) { return [[g_lastError retain] autorelease]; } }

#pragma mark - Start / stop

+ (void)startServer {
	@synchronized(self) {
		if (g_server != nil && [g_server isRunning]) return;
		[g_lastError release]; g_lastError = nil;

		AGWebAPI *api = [[[AGWebAPI alloc] init] autorelease];
		api.bridge = g_bridge;
		api.pagePath = g_pagePath ?: [[NSBundle mainBundle] pathForResource:@"agentic-web" ofType:@"html"];
		AGHTTPServer *server = [[[AGHTTPServer alloc] init] autorelease];
		// The block reads the current API object instead of capturing it, so a restart never leaves a stale pointer behind.
		[server setHandler:^AGHTTPResponse *(AGHTTPRequest *request) {
			AGWebAPI *current = nil;
			@synchronized([AGWebAccess class]) { current = [[g_api retain] autorelease]; }
			return current != nil ? [current handleRequest:request] : [AGHTTPResponse responseWithStatus:503 text:@"Web Access is off."];
		}];

		NSString *error = nil;
		if ([server startOnPort:(uint16_t)[self port] error:&error]) {
			[g_server release]; g_server = [server retain];
			[g_api release]; g_api = [api retain];
		} else {
			g_lastError = [(error ?: @"The web server could not start.") copy];
		}
	}
	[self postChange];
}

+ (void)stopServer {
	@synchronized(self) {
		[g_server stop];
		[g_api shutdown];
		[g_server release]; g_server = nil;
		[g_api release]; g_api = nil;
		[g_lastError release]; g_lastError = nil;
	}
	[[AGWebPairing sharedPairing] cancelPendingRequests];   // nobody can be waiting for a tap any more
	[self postChange];
}

#pragma mark - Addresses

+ (NSArray *)addressURLs {
	NSMutableArray *wifi = [NSMutableArray array], *other = [NSMutableArray array];
	struct ifaddrs *list = NULL;
	if (getifaddrs(&list) != 0) return [NSArray array];
	NSUInteger port = [self port];
	for (struct ifaddrs *entry = list; entry != NULL; entry = entry->ifa_next) {
		if (entry->ifa_addr == NULL || entry->ifa_addr->sa_family != AF_INET) continue;
		if (!(entry->ifa_flags & IFF_UP) || (entry->ifa_flags & IFF_LOOPBACK)) continue;
		char text[INET_ADDRSTRLEN] = "";
		inet_ntop(AF_INET, &((struct sockaddr_in *)entry->ifa_addr)->sin_addr, text, sizeof(text));
		if (strncmp(text, "169.254.", 8) == 0) continue;   // self-assigned: no network
		NSString *name = [NSString stringWithUTF8String:entry->ifa_name] ?: @"";
		NSString *url = [NSString stringWithFormat:@"http://%s:%lu", text, (unsigned long)port];
		if ([name hasPrefix:@"en"]) [wifi addObject:url]; else [other addObject:url];   // en0 is Wi-Fi on iOS
	}
	freeifaddrs(list);
	[wifi addObjectsFromArray:other];
	return wifi;
}

@end
