#import <Foundation/Foundation.h>
#import "AGHTTPServer.h"
#import "AGWebBridge.h"

@class AGMessage;

/// What the URLs mean. Foundation-only (the chat screen is reached through AGWebBridge), so the
/// host tests drive it with a fake bridge.
///
///   GET  /                    the web page (no login needed: it contains nothing private)
///   POST /api/pair            ask to connect; the question appears on the phone
///   GET  /api/pair/<id>       poll for the answer; the token is handed out once, on Allow
///   -- everything below needs the header  X-AG-Token: <token>  --
///   GET  /api/state           long poll: ?rev=&conv=&from=
///   GET  /api/chats           chat list
///   POST /api/send {text}     POST /api/stop   POST /api/new   POST /api/open {id}   POST /api/signout
@interface AGWebAPI : NSObject {
@private
	id<AGWebBridge> _bridge;
	NSString *_pagePath;
	NSCondition *_condition;
	NSUInteger _revision;         // bumped by every notification that may change what the page shows
	BOOL _shutdown;
	NSData *_pageData;
	NSString *_pageDataPath;
	NSTimeInterval _pageDataTime;
}

@property (nonatomic, assign) id<AGWebBridge> bridge;       // not retained
/// File served at "/" (Resources/agentic-web.html).
@property (nonatomic, retain) NSString *pagePath;

- (AGHTTPResponse *)handleRequest:(AGHTTPRequest *)request;

/// Releases every waiting long poll (server stopping).
- (void)shutdown;

/// How long a long poll waits for news (seconds, default 25).
+ (NSTimeInterval)longPollTimeout;
+ (void)setLongPollTimeout:(NSTimeInterval)seconds;   // tests

/// JSON for one message. `displayText` is the cleaned text from the renderer.
+ (NSDictionary *)dictionaryForMessage:(AGMessage *)message index:(NSUInteger)index displayText:(NSString *)displayText;

/// Host header allow-list against DNS rebinding (IP addresses, localhost, *.local, `agent_web_allowed_hosts`).
+ (BOOL)isAcceptableHost:(NSString *)hostHeader;

@end
