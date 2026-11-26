#import "AGWebAPI.h"
#import "AGWebPairing.h"
#import "AGChatClient.h"
#import "AGApproval.h"
#import "AGMessage.h"
#import "AGConversation.h"
#import "AGConversationStore.h"

NSString * const AGWebConversationChangedNotification = @"AGWebConversationChangedNotification";

static const NSUInteger AGMaxSendChars = 20000;
static NSTimeInterval g_longPollSeconds = 25.0;

/// Runs `block` on the main thread and hands its result back to the calling thread.
/// The result is retained on the main thread and autoreleased on THIS thread: the main thread's
/// autorelease pool may drain before the caller looks at it.
static id AGOnMain(id (^block)(void)) {
	if ([NSThread isMainThread]) return block();
	__block id result = nil;
	dispatch_sync(dispatch_get_main_queue(), ^{ result = [block() retain]; });
	return [result autorelease];
}

static AGHTTPResponse *AGJSON(int status, id object) { return [AGHTTPResponse responseWithStatus:status json:object]; }
static AGHTTPResponse *AGError(int status, NSString *message) { return AGJSON(status, [NSDictionary dictionaryWithObject:message ?: @"Error" forKey:@"error"]); }

static BOOL AGSafeIdentifier(NSString *identifier) {
	if (![identifier isKindOfClass:[NSString class]] || [identifier length] == 0 || [identifier length] > 64) return NO;
	static NSCharacterSet *bad = nil; static dispatch_once_t once;
	dispatch_once(&once, ^{
		bad = [[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet] retain];
	});
	return [identifier rangeOfCharacterFromSet:bad].location == NSNotFound;
}

@implementation AGWebAPI

@synthesize bridge = _bridge;
@synthesize pagePath = _pagePath;

+ (NSTimeInterval)longPollTimeout { return g_longPollSeconds; }
+ (void)setLongPollTimeout:(NSTimeInterval)seconds { g_longPollSeconds = MAX(0.05, seconds); }

- (id)init {
	self = [super init];
	if (self) {
		_condition = [[NSCondition alloc] init];
		_revision = 1;
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		NSArray *names = [NSArray arrayWithObjects:AGAPIResponseNotification, AGAPIStatusDidChangeNotification, AGWebConversationChangedNotification,
			AGApprovalPendingChangedNotification, AGAgentModeChangedNotification, nil];
		for (NSString *name in names) [center addObserver:self selector:@selector(somethingChanged:) name:name object:nil];
	}
	return self;
}

- (void)somethingChanged:(NSNotification *)note {
	[_condition lock];
	_revision++;
	[_condition broadcast];
	[_condition unlock];
}

- (NSUInteger)currentRevision {
	[_condition lock]; NSUInteger revision = _revision; [_condition unlock];
	return revision;
}

/// Blocks until the revision differs from `known` (or the timeout, or shutdown). Returns the revision.
- (NSUInteger)waitForRevisionOtherThan:(NSUInteger)known timeout:(NSTimeInterval)timeout {
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	[_condition lock];
	while (_revision == known && !_shutdown) { if (![_condition waitUntilDate:deadline]) break; }
	NSUInteger revision = _revision;
	[_condition unlock];
	return revision;
}

- (void)shutdown {
	[_condition lock]; _shutdown = YES; [_condition broadcast]; [_condition unlock];
}

#pragma mark - Messages as JSON

+ (NSDictionary *)dictionaryForMessage:(AGMessage *)message index:(NSUInteger)index displayText:(NSString *)displayText {
	NSMutableDictionary *entry = [NSMutableDictionary dictionary];
	[entry setObject:[NSNumber numberWithUnsignedInteger:index] forKey:@"i"];
	[entry setObject:(message.role ?: @"assistant") forKey:@"role"];
	if ([message.author length] > 0) [entry setObject:message.author forKey:@"author"];
	if (message.localOnly) [entry setObject:[NSNumber numberWithBool:YES] forKey:@"local"];
	if ([message.toolName length] > 0) [entry setObject:message.toolName forKey:@"tool"];

	NSMutableArray *tools = [NSMutableArray array];
	for (NSDictionary *call in message.toolCalls) {
		NSDictionary *fn = [call isKindOfClass:[NSDictionary class]] ? [call objectForKey:@"function"] : nil;
		if (![fn isKindOfClass:[NSDictionary class]]) continue;
		NSString *name = [fn objectForKey:@"name"];
		if (![name isKindOfClass:[NSString class]]) name = @"tool";
		NSString *json = [fn objectForKey:@"arguments"];
		NSDictionary *args = nil;
		if ([json isKindOfClass:[NSString class]]) {
			id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
			if ([parsed isKindOfClass:[NSDictionary class]]) args = parsed;
		}
		NSString *detail = nil;
		if ([name isEqualToString:@"runShellCommand"]) detail = [args objectForKey:@"command"];
		else if ([name isEqualToString:@"writeFile"]) detail = [NSString stringWithFormat:@"%@ (%lu chars)", [args objectForKey:@"filepath"] ?: @"?", (unsigned long)[[args objectForKey:@"content"] length]];
		else detail = [args objectForKey:@"filepath"];
		if (![detail isKindOfClass:[NSString class]]) detail = @"";
		if ([detail length] > 400) detail = [[detail substringToIndex:400] stringByAppendingString:@"..."];
		[tools addObject:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", detail, @"detail", nil]];
	}
	if ([tools count] > 0) [entry setObject:tools forKey:@"tools"];

	// A turn that only calls tools has no text of its own (the renderer would answer with a call summary).
	NSString *raw = [(message.content ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	BOOL callOnly = [tools count] > 0 && ([raw length] == 0 || [raw hasPrefix:@"Tool Call: "]);
	[entry setObject:(callOnly ? @"" : (displayText ?: @"")) forKey:@"text"];
	return entry;
}

#pragma mark - Host header (DNS rebinding)

/// A web page on another site can only talk to this server "as itself" if its own name is made to
/// resolve to the phone (DNS rebinding); the browser then sends THAT name in Host. So only names
/// that cannot be the attacker's are accepted: IP addresses, localhost, *.local, and names the user
/// listed in the `agent_web_allowed_hosts` default (for example a router name such as "phone.lan").
+ (BOOL)isAcceptableHost:(NSString *)hostHeader {
	NSString *host = [hostHeader lowercaseString];
	if ([host length] == 0 || [host length] > 255) return NO;
	NSString *name = host;
	if ([host hasPrefix:@"["]) {                       // [ipv6] or [ipv6]:port
		NSRange close = [host rangeOfString:@"]"];
		if (close.location == NSNotFound) return NO;
		NSString *inside = [host substringWithRange:NSMakeRange(1, close.location - 1)];
		NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef:.%"];
		return [inside length] > 0 && [inside rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
	}
	NSRange colon = [host rangeOfString:@":" options:NSBackwardsSearch];
	if (colon.location != NSNotFound) {
		NSString *port = [host substringFromIndex:colon.location + 1];
		NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
		if ([port length] == 0 || [port length] > 5 || [port rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound) return NO;
		name = [host substringToIndex:colon.location];
	}
	if ([name length] == 0) return NO;
	if ([name isEqualToString:@"localhost"] || [name hasSuffix:@".local"]) return YES;
	NSArray *parts = [name componentsSeparatedByString:@"."];
	if ([parts count] == 4) {                          // dotted IPv4
		BOOL numeric = YES;
		for (NSString *part in parts) {
			if ([part length] == 0 || [part length] > 3 || [part rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound || [part intValue] > 255) { numeric = NO; break; }
		}
		if (numeric) return YES;
	}
	id extra = [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_web_allowed_hosts"];
	if ([extra isKindOfClass:[NSArray class]]) {
		for (id entry in extra) if ([entry isKindOfClass:[NSString class]] && [[entry lowercaseString] isEqualToString:name]) return YES;
	}
	return NO;
}

#pragma mark - Routing

- (AGHTTPResponse *)handleRequest:(AGHTTPRequest *)request {
	NSString *path = request.path;
	NSString *method = request.method;

	if (![AGWebAPI isAcceptableHost:[request headerNamed:@"host"]]) {
		return AGError(403, @"Open this page by the phone's IP address (for example http://192.168.1.20:8080).");
	}

	if ([path isEqualToString:@"/"] || [path isEqualToString:@"/index.html"]) {
		if (![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"]) return AGError(405, @"Method not allowed");
		return [self pageResponse];
	}
	if ([path isEqualToString:@"/favicon.ico"]) return [AGHTTPResponse responseWithStatus:204 contentType:nil body:nil];

	if (![path hasPrefix:@"/api/"]) return AGError(404, @"Not found");

	// ---- pairing (no token yet) ----
	if ([path isEqualToString:@"/api/pair"]) {
		if (![method isEqualToString:@"POST"]) return AGError(405, @"Method not allowed");
		if (![self originMatchesHost:request]) return AGError(403, @"Cross-site request refused");
		NSDictionary *body = [request jsonBody];
		NSString *name = [[body objectForKey:@"name"] isKindOfClass:[NSString class]] ? [body objectForKey:@"name"] : nil;
		int status = 200;
		NSDictionary *result = [[AGWebPairing sharedPairing] beginRequestFromAddress:request.remoteAddress clientName:name userAgent:[request headerNamed:@"user-agent"] httpStatus:&status];
		return AGJSON(status, result);
	}
	if ([path hasPrefix:@"/api/pair/"]) {
		if (![method isEqualToString:@"GET"]) return AGError(405, @"Method not allowed");
		return AGJSON(200, [[AGWebPairing sharedPairing] pollRequestWithID:[path substringFromIndex:[@"/api/pair/" length]]]);
	}

	// ---- everything else needs an approved device ----
	NSString *token = [request headerNamed:@"x-ag-token"];
	NSDictionary *device = [[AGWebPairing sharedPairing] deviceForToken:token];
	if (device == nil) return AGError(401, @"Not connected");

	if ([path isEqualToString:@"/api/state"]) {
		if (![method isEqualToString:@"GET"]) return AGError(405, @"Method not allowed");
		return [self stateResponseForRequest:request device:device];
	}
	if ([path isEqualToString:@"/api/chats"]) {
		if (![method isEqualToString:@"GET"]) return AGError(405, @"Method not allowed");
		return [self chatsResponse];
	}

	// Everything below changes something.
	if (![method isEqualToString:@"POST"]) return AGError(405, @"Method not allowed");
	if (![self originMatchesHost:request]) return AGError(403, @"Cross-site request refused");
	id<AGWebBridge> bridge = self.bridge;
	if (bridge == nil) return AGError(503, @"The app is not ready");

	if ([path isEqualToString:@"/api/send"]) {
		NSString *text = [[request jsonBody] objectForKey:@"text"];
		if (![text isKindOfClass:[NSString class]]) return AGError(400, @"Missing text");
		text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([text length] == 0) return AGError(400, @"Empty message");
		if ([text length] > AGMaxSendChars) return AGError(413, @"Message too long");
		NSArray *outcome = AGOnMain(^id{
			NSString *reason = nil;
			BOOL sent = [bridge webSendText:text error:&reason];
			return [NSArray arrayWithObjects:[NSNumber numberWithBool:sent], reason ?: @"", nil];
		});
		if (![[outcome objectAtIndex:0] boolValue]) return AGError(409, [[outcome objectAtIndex:1] length] > 0 ? [outcome objectAtIndex:1] : @"Could not send");
		return AGJSON(200, [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"ok"]);
	}
	if ([path isEqualToString:@"/api/stop"]) {
		AGOnMain(^id{ [bridge webStop]; return [NSNull null]; });
		return AGJSON(200, [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"ok"]);
	}
	if ([path isEqualToString:@"/api/new"]) {
		AGOnMain(^id{ [bridge webStartNewConversation]; return [NSNull null]; });
		return AGJSON(200, [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"ok"]);
	}
	if ([path isEqualToString:@"/api/open"]) {
		NSString *identifier = [[request jsonBody] objectForKey:@"id"];
		if (!AGSafeIdentifier(identifier)) return AGError(400, @"Bad chat id");
		NSNumber *opened = AGOnMain(^id{ return [NSNumber numberWithBool:[bridge webOpenConversation:identifier]]; });
		if (![opened boolValue]) return AGError(404, @"Chat not found");
		return AGJSON(200, [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"ok"]);
	}
	if ([path isEqualToString:@"/api/signout"]) {
		[[AGWebPairing sharedPairing] revokeToken:token];
		return AGJSON(200, [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"ok"]);
	}
	return AGError(404, @"Not found");
}

/// Browsers add an Origin header to cross-site POSTs. If it names another host than the one asked, refuse.
- (BOOL)originMatchesHost:(AGHTTPRequest *)request {
	NSString *origin = [request headerNamed:@"origin"];
	if ([origin length] == 0 || [origin isEqualToString:@"null"]) return [origin length] == 0;
	NSString *host = [request headerNamed:@"host"];
	if ([host length] == 0) return NO;
	NSRange scheme = [origin rangeOfString:@"://"];
	NSString *originHost = (scheme.location == NSNotFound) ? origin : [origin substringFromIndex:scheme.location + 3];
	return [originHost caseInsensitiveCompare:host] == NSOrderedSame;
}

#pragma mark - Page

- (AGHTTPResponse *)pageResponse {
	NSData *data = nil;
	@synchronized(self) {
		NSString *path = self.pagePath;
		if (path != nil) {
			NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
			NSTimeInterval modified = [[attributes fileModificationDate] timeIntervalSinceReferenceDate];
			if (_pageData == nil || ![path isEqualToString:_pageDataPath] || modified != _pageDataTime) {
				[_pageData release]; _pageData = [[NSData dataWithContentsOfFile:path] retain];
				[_pageDataPath release]; _pageDataPath = [path copy];
				_pageDataTime = modified;
			}
		}
		data = [[_pageData retain] autorelease];
	}
	if (data == nil) return [AGHTTPResponse responseWithStatus:500 text:@"The web page is missing from the app (Resources/agentic-web.html)."];
	AGHTTPResponse *response = [AGHTTPResponse responseWithStatus:200 contentType:@"text/html; charset=utf-8" body:data];
	[response.headers setObject:@"no-cache" forKey:@"Cache-Control"];
	[response.headers setObject:@"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" forKey:@"Content-Security-Policy"];
	return response;
}

#pragma mark - State (long poll)

- (AGHTTPResponse *)stateResponseForRequest:(AGHTTPRequest *)request device:(NSDictionary *)device {
	id<AGWebBridge> bridge = self.bridge;
	if (bridge == nil) return AGError(503, @"The app is not ready");

	NSString *revText = [request.query objectForKey:@"rev"];
	NSString *known = [request.query objectForKey:@"conv"];
	NSUInteger from = (NSUInteger)MAX(0, [[request.query objectForKey:@"from"] integerValue]);
	NSUInteger revision = [self currentRevision];
	if (revText != nil && [revText length] > 0 && (NSUInteger)[revText longLongValue] == revision) {
		revision = [self waitForRevisionOtherThan:revision timeout:[AGWebAPI longPollTimeout]];
	}

	NSDictionary *snapshot = AGOnMain(^id{ return [bridge webSnapshotKnownConversation:known fromIndex:from]; });
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:snapshot ?: [NSDictionary dictionary]];
	[out setObject:[NSNumber numberWithUnsignedInteger:revision] forKey:@"rev"];
	NSString *pending = [AGApproval pendingTitle];
	[out setObject:(pending ?: [NSNull null]) forKey:@"approval"];
	[out setObject:[device objectForKey:@"name"] ?: @"" forKey:@"device"];
	return AGJSON(200, out);
}

#pragma mark - Chat list

- (AGHTTPResponse *)chatsResponse {
	NSArray *conversations = [AGConversationStore loadConversations];
	NSMutableArray *list = [NSMutableArray array];
	for (AGConversation *conversation in conversations) {
		if ([list count] >= 100) break;
		if (!AGSafeIdentifier(conversation.uuid)) continue;
		[list addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			conversation.uuid, @"id", conversation.title ?: @"Chat", @"title",
			[NSNumber numberWithInt:conversation.messageCount], @"count",
			conversation.lastTimeEdited ?: @"", @"edited", nil]];
	}
	return AGJSON(200, [NSDictionary dictionaryWithObject:list forKey:@"chats"]);
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_condition release]; [_pageData release]; [_pageDataPath release]; [_pagePath release];
	[super dealloc];
}

@end
