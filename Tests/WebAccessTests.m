// Host-side tests for the web access layer: HTTP server, phone-approved pairing, API routing.
#import <Foundation/Foundation.h>
#import "AGHTTPServer.h"
#import "AGWebPairing.h"
#import "AGWebAPI.h"
#import "AGWebAccess.h"
#import "AGApproval.h"
#import "AGMessage.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <Block.h>

// AGChatClient.m is not linked into this suite; these are its notification names (the API observes them).
NSString * const AGAPIResponseNotification = @"AGAPIResponseNotification";
NSString * const AGAPIStatusDidChangeNotification = @"AGAPIStatusDidChangeNotification";
NSString * const AGAgentModeChangedNotification = @"AGAgentModeChangedNotification";

static int fails = 0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)

#pragma mark - raw HTTP client

static NSString *Raw(uint16_t port, NSString *request) {
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	struct sockaddr_in a; memset(&a, 0, sizeof a); a.sin_family = AF_INET; a.sin_port = htons(port); inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
	if (connect(fd, (struct sockaddr *)&a, sizeof a) != 0) { close(fd); return nil; }
	NSData *d = [request dataUsingEncoding:NSUTF8StringEncoding];
	send(fd, [d bytes], [d length], 0);
	NSMutableData *out = [NSMutableData data]; char buf[4096]; ssize_t n;
	while ((n = recv(fd, buf, sizeof buf, 0)) > 0) [out appendBytes:buf length:n];
	close(fd);
	return [[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] autorelease];
}
static int StatusOf(NSString *r) { return ([r length] > 12 && [r hasPrefix:@"HTTP/1.1 "]) ? [[r substringWithRange:NSMakeRange(9, 3)] intValue] : -1; }
static NSString *BodyOf(NSString *r) { NSRange x = [r rangeOfString:@"\r\n\r\n"]; return x.location == NSNotFound ? @"" : [r substringFromIndex:x.location + 4]; }
static NSString *Get(uint16_t port, NSString *path, NSString *extra) { return Raw(port, [NSString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: 127.0.0.1\r\n%@\r\n", path, extra ?: @""]); }
static NSString *Post(uint16_t port, NSString *path, NSString *json, NSString *extra) {
	return Raw(port, [NSString stringWithFormat:@"POST %@ HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %lu\r\n%@\r\n%@", path, (unsigned long)[json lengthOfBytesUsingEncoding:NSUTF8StringEncoding], extra ?: @"", json]);
}
static NSDictionary *JSON(NSString *body) { id o = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]; return [o isKindOfClass:[NSDictionary class]] ? o : nil; }

@interface BlockRunner : NSObject { void (^_block)(void); }
+ (void)run:(void (^)(void))block;
@end
@implementation BlockRunner
+ (void)run:(void (^)(void))block { BlockRunner *r = [[BlockRunner alloc] init]; r->_block = Block_copy(block); [NSThread detachNewThreadSelector:@selector(go) toTarget:r withObject:nil]; }
- (void)go { @autoreleasepool { _block(); } }
@end

#pragma mark - fake phone

static int g_asked = 0; static NSString *g_lastDetail = nil, *g_lastTitle = nil; static int g_cancelled = 0; static int g_mode = 1; // 1 allow, 0 deny, -1 never answer, 2 timed out
static void (^g_lastAnswer)(AGPairAnswer) = NULL;
static void InstallPhone(int mode) {
	g_asked = 0; g_cancelled = 0; g_mode = mode;
	[[AGWebPairing sharedPairing] setAsk:^id(NSString *title, NSString *detail, NSTimeInterval timeout, void (^answer)(AGPairAnswer)) {
		g_asked++; g_lastTitle = [title copy]; g_lastDetail = [detail copy];
		if (g_lastAnswer) Block_release(g_lastAnswer); g_lastAnswer = Block_copy(answer);
		if (g_mode == 1) answer(AGPairAnswerAllow); else if (g_mode == 0) answer(AGPairAnswerDeny); else if (g_mode == 2) answer(AGPairAnswerTimedOut);
		return [NSString stringWithFormat:@"h%d", g_asked];
	} cancel:^(id h) { g_cancelled++; }];
}

#pragma mark - fake chat screen

@interface FakeBridge : NSObject <AGWebBridge> { @public BOOL busy; NSMutableArray *sent; BOOL stopped, newChat; NSString *opened; }
@end
@implementation FakeBridge
- (id)init { self = [super init]; sent = [[NSMutableArray alloc] init]; return self; }
- (NSDictionary *)webSnapshotKnownConversation:(NSString *)known fromIndex:(NSUInteger)index {
	BOOL reset = ![known isEqualToString:@"conv1"];
	NSMutableArray *msgs = [NSMutableArray array];
	for (NSUInteger i = reset ? 0 : index; i < [sent count]; i++) {
		AGMessage *m = [AGMessage messageWithRole:@"user" content:[sent objectAtIndex:i]];
		[msgs addObject:[AGWebAPI dictionaryForMessage:m index:i displayText:m.content]];
	}
	return [NSDictionary dictionaryWithObjectsAndKeys:@"conv1", @"conversation", [NSNumber numberWithBool:reset], @"reset", [NSNumber numberWithUnsignedInteger:[sent count]], @"total",
		msgs, @"messages", [NSNumber numberWithBool:busy], @"running", [NSNumber numberWithBool:YES], @"agent", @"TestProvider", @"provider", @"test-model", @"model", nil];
}
- (BOOL)webSendText:(NSString *)text error:(NSString **)error { if (busy) { if (error) *error = @"The agent is busy."; return NO; } [sent addObject:text]; return YES; }
- (void)webStop { stopped = YES; }
- (void)webStartNewConversation { newChat = YES; }
- (BOOL)webOpenConversation:(NSString *)identifier { opened = [identifier copy]; return [identifier isEqualToString:@"known-chat"]; }
@end

// Pairs a device through the real API and returns its token.
static NSString *PairOver(uint16_t port, NSString *name) {
	NSDictionary *begin = JSON(BodyOf(Post(port, @"/api/pair", [NSString stringWithFormat:@"{\"name\":\"%@\"}", name], @"User-Agent: Mozilla/5.0 (Linux; Android 11; BRAVIA 4K TV) Chrome/90\r\n")));
	NSDictionary *poll = JSON(BodyOf(Get(port, [@"/api/pair/" stringByAppendingString:[begin objectForKey:@"id"] ?: @"x"], nil)));
	return [poll objectForKey:@"token"];
}

int main(int argc, char **argv) {
	@autoreleasepool {
		NSString *repo = [NSString stringWithUTF8String:getenv("AG_REPO") ?: "."];
		[AGWebAPI setLongPollTimeout:1.0];

		// ================= HTTP server =================
		AGHTTPServer *server = [[AGHTTPServer alloc] init];
		[server setHandler:^AGHTTPResponse *(AGHTTPRequest *r) {
			if ([r.path isEqualToString:@"/slow"]) { [NSThread sleepForTimeInterval:0.5]; return [AGHTTPResponse responseWithStatus:200 text:@"slow"]; }
			NSDictionary *echo = [NSDictionary dictionaryWithObjectsAndKeys:r.method, @"method", r.path, @"path", r.query, @"query", r.remoteAddress, @"addr",
				[r headerNamed:@"X-Test"] ?: @"", @"x", [[[NSString alloc] initWithData:r.body encoding:NSUTF8StringEncoding] autorelease] ?: @"", @"body", nil];
			return [AGHTTPResponse responseWithStatus:200 json:echo];
		}];
		NSString *err = nil;
		CHECK("server starts on an ephemeral port", [server startOnPort:0 error:&err] && [server port] > 0 && [server isRunning]);
		uint16_t port = [server port];

		NSString *r = Get(port, @"/hello%20there?a=1&b=hello%20world&c=x%26y", @"X-Test: yes\r\n");
		NSDictionary *j = JSON(BodyOf(r));
		CHECK("GET answers 200 with JSON", StatusOf(r) == 200 && j != nil);
		CHECK("path is percent-decoded", [[j objectForKey:@"path"] isEqualToString:@"/hello there"]);
		CHECK("query is parsed and decoded", [[[j objectForKey:@"query"] objectForKey:@"b"] isEqualToString:@"hello world"] && [[[j objectForKey:@"query"] objectForKey:@"c"] isEqualToString:@"x&y"]);
		CHECK("header lookup is case-insensitive", [[j objectForKey:@"x"] isEqualToString:@"yes"]);
		CHECK("remote address is the real peer", [[j objectForKey:@"addr"] isEqualToString:@"127.0.0.1"]);
		CHECK("security headers present", [r rangeOfString:@"X-Content-Type-Options: nosniff"].location != NSNotFound && [r rangeOfString:@"Cache-Control: no-store"].location != NSNotFound
			&& [r rangeOfString:@"Connection: close"].location != NSNotFound && [r rangeOfString:@"X-Frame-Options: DENY"].location != NSNotFound);

		r = Post(port, @"/p", @"{\"k\":\"v\u00e9\"}", nil);
		CHECK("POST body arrives intact (UTF-8)", StatusOf(r) == 200 && [[JSON(BodyOf(r)) objectForKey:@"body"] isEqualToString:@"{\"k\":\"v\u00e9\"}"]);

		CHECK("garbage request line = 400", StatusOf(Raw(port, @"NONSENSE\r\n\r\n")) == 400);
		CHECK("non-HTTP version = 400", StatusOf(Raw(port, @"GET / FTP/9\r\n\r\n")) == 400);
		CHECK("chunked request body refused (400)", StatusOf(Raw(port, @"POST /p HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")) == 400);
		CHECK("duplicate Content-Length refused (400)", StatusOf(Raw(port, @"POST /p HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab")) == 400);
		CHECK("negative Content-Length refused (400)", StatusOf(Raw(port, @"POST /p HTTP/1.1\r\nContent-Length: -5\r\n\r\n")) == 400);
		CHECK("huge Content-Length = 413", StatusOf(Raw(port, @"POST /p HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")) == 413);
		NSMutableString *big = [NSMutableString stringWithString:@"GET / HTTP/1.1\r\n"];
		for (int i = 0; i < 700; i++) [big appendFormat:@"X-Pad-%d: %@\r\n", i, @"aaaaaaaaaaaaaaaaaaaaaaaa"];
		[big appendString:@"\r\n"];
		CHECK("oversized headers = 431", StatusOf(Raw(port, big)) == 431);
		CHECK("path without leading slash = 400", StatusOf(Raw(port, @"GET foo HTTP/1.1\r\n\r\n")) == 400);

		// a client that connects and says nothing must not wedge the accept loop
		int idle = socket(AF_INET, SOCK_STREAM, 0); struct sockaddr_in a; memset(&a, 0, sizeof a); a.sin_family = AF_INET; a.sin_port = htons(port); inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
		connect(idle, (struct sockaddr *)&a, sizeof a);
		CHECK("idle connection does not block other clients", StatusOf(Get(port, @"/ok", nil)) == 200);
		close(idle);

		// parallel clients
		__block int okCount = 0; NSLock *lock = [[NSLock alloc] init];
		for (int i = 0; i < 6; i++) {
			[BlockRunner run:^{ if (StatusOf(Get(port, @"/slow", nil)) == 200) { [lock lock]; okCount++; [lock unlock]; } }];
		}
		[NSThread sleepForTimeInterval:1.5];
		CHECK("6 parallel slow requests all answered", okCount == 6);

		[server stop];
		[NSThread sleepForTimeInterval:0.5];
		CHECK("stopped server refuses connections", Get(port, @"/", nil) == nil && ![server isRunning]);
		AGHTTPServer *a1 = [[AGHTTPServer alloc] init], *a2 = [[AGHTTPServer alloc] init];
		[a1 startOnPort:0 error:nil]; NSString *inUse = nil;
		CHECK("second server on a used port fails with a readable reason", ![a2 startOnPort:[a1 port] error:&inUse] && [inUse rangeOfString:@"already in use"].location != NSNotFound);
		[a1 stop];
		CHECK("percentDecode / parseQueryString edge cases", [[AGHTTPServer parseQueryString:@"a&b=&=c&d=1&d=2"] count] == 3 && [[[AGHTTPServer parseQueryString:@"d=1&d=2"] objectForKey:@"d"] isEqualToString:@"1"]);

		// ================= pairing =================
		AGWebPairing *pairing = [AGWebPairing sharedPairing];
		[pairing setAsk:NULL cancel:NULL];
		int st = 0;
		NSDictionary *res = [pairing beginRequestFromAddress:@"10.0.1.1" clientName:@"TV" userAgent:nil httpStatus:&st];
		CHECK("no phone screen attached: request is denied, never allowed", [[[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"status"] isEqualToString:@"denied"]);

		InstallPhone(1);
		res = [pairing beginRequestFromAddress:@"10.0.2.1" clientName:@"Living room\r\nTV" userAgent:@"Mozilla/5.0 (Linux; Android 11; BRAVIA 4K TV) Chrome/90" httpStatus:&st];
		CHECK("phone is asked once, with title, device, address and code", g_asked == 1 && [g_lastTitle isEqualToString:@"Allow web access?"] && [g_lastDetail rangeOfString:@"10.0.2.1"].location != NSNotFound
			&& [g_lastDetail rangeOfString:[res objectForKey:@"code"]].location != NSNotFound && [[res objectForKey:@"code"] length] == 4);
		CHECK("device name is sanitized and combined with the user agent", [g_lastDetail rangeOfString:@"Living room TV [Android TV (Chrome)]"].location != NSNotFound);
		NSDictionary *polled = [pairing pollRequestWithID:[res objectForKey:@"id"]];
		NSString *token = [polled objectForKey:@"token"];
		CHECK("Allow gives a 40-char random token", [[polled objectForKey:@"status"] isEqualToString:@"approved"] && [token length] == 40);
		CHECK("token is handed out only once", [[[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"status"] isEqualToString:@"unknown"]);
		CHECK("token identifies the device", [[[pairing deviceForToken:token] objectForKey:@"name"] hasPrefix:@"Living room TV"]);
		CHECK("bad tokens are rejected", [pairing deviceForToken:nil] == nil && [pairing deviceForToken:@"short"] == nil && [pairing deviceForToken:[@"" stringByPaddingToLength:40 withString:@"a" startingAtIndex:0]] == nil);
		CHECK("devices list never contains tokens", [[[pairing devices] description] rangeOfString:token].location == NSNotFound && [[pairing devices] count] == 1);

		// persistence
		AGWebPairing *second = [[AGWebPairing alloc] init];
		CHECK("allowed devices survive an app restart", [second deviceForToken:token] != nil);
		// idle expiry
		NSMutableArray *stored = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"web_devices"]];
		NSMutableDictionary *old = [NSMutableDictionary dictionaryWithDictionary:[stored objectAtIndex:0]];
		[old setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] - 31 * 86400.0] forKey:@"lastSeen"];
		[[NSUserDefaults standardUserDefaults] setObject:[NSArray arrayWithObject:old] forKey:@"web_devices"];
		AGWebPairing *third = [[AGWebPairing alloc] init];
		CHECK("device unused for 30+ days must ask again", [third deviceForToken:token] == nil);
		[[NSUserDefaults standardUserDefaults] setObject:stored forKey:@"web_devices"];

		// deny + cooldown
		InstallPhone(0);
		res = [pairing beginRequestFromAddress:@"10.0.3.1" clientName:nil userAgent:nil httpStatus:&st];
		CHECK("Deny is reported as denied", [[[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"status"] isEqualToString:@"denied"]);
		[NSThread sleepForTimeInterval:2.2];
		res = [pairing beginRequestFromAddress:@"10.0.3.1" clientName:nil userAgent:nil httpStatus:&st];
		CHECK("asking again right after a refusal is blocked (429)", st == 429 && [res objectForKey:@"error"] != nil && g_asked == 1);
		InstallPhone(1);
		res = [pairing beginRequestFromAddress:@"10.0.3.2" clientName:nil userAgent:nil httpStatus:&st];
		CHECK("a refusal does not affect other devices", st == 200 && [[[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"status"] isEqualToString:@"approved"]);

		// rate limit: same address twice within 2 s
		InstallPhone(-1);
		res = [pairing beginRequestFromAddress:@"10.0.4.1" clientName:nil userAgent:nil httpStatus:&st];
		NSDictionary *res2 = [pairing beginRequestFromAddress:@"10.0.4.1" clientName:nil userAgent:nil httpStatus:&st];
		CHECK("request spam from one address is rate limited", st == 429 && g_asked == 1);
		[NSThread sleepForTimeInterval:2.2];
		res2 = [pairing beginRequestFromAddress:@"10.0.4.1" clientName:nil userAgent:nil httpStatus:&st];
		CHECK("a reload replaces the old request and takes its question off the phone", st == 200 && g_cancelled == 1 && g_asked == 2
			&& [[[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"status"] isEqualToString:@"unknown"]);
		CHECK("old pending request cannot be approved any more", ({ g_lastAnswer(AGPairAnswerAllow); [[[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"status"] isEqualToString:@"unknown"]; }) );

		// pending cap
		InstallPhone(-1);
		for (int i = 0; i < 4; i++) [pairing beginRequestFromAddress:[NSString stringWithFormat:@"10.0.5.%d", i] clientName:nil userAgent:nil httpStatus:&st];
		[pairing beginRequestFromAddress:@"10.0.5.9" clientName:nil userAgent:nil httpStatus:&st];
		CHECK("at most 4 questions wait on the phone at once", st == 429);
		[pairing cancelPendingRequests];
		CHECK("switching the server off withdraws every waiting question", g_cancelled >= 4);

		// timed out
		InstallPhone(2);
		res = [pairing beginRequestFromAddress:@"10.0.6.1" clientName:nil userAgent:nil httpStatus:&st];
		CHECK("unanswered question ends as expired", [[[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"status"] isEqualToString:@"expired"]);

		// revoke
		InstallPhone(1);
		res = [pairing beginRequestFromAddress:@"10.0.7.1" clientName:@"A" userAgent:nil httpStatus:&st];
		NSString *t1 = [[pairing pollRequestWithID:[res objectForKey:@"id"]] objectForKey:@"token"];
		CHECK("revoking one device invalidates its token", ({ NSString *did = [[pairing deviceForToken:t1] objectForKey:@"id"]; [pairing revokeDeviceWithID:did]; [pairing deviceForToken:t1] == nil; }));
		CHECK("original device still works after another was revoked", [pairing deviceForToken:token] != nil);
		[pairing revokeAllDevices];
		CHECK("disconnect all invalidates everything", [pairing deviceForToken:token] == nil && [[pairing devices] count] == 0);

		// helpers
		CHECK("labels lose control chars and bidi overrides", [[AGWebPairing sanitizedLabel:@"a\nb\t\u202Ec\x01 d" maxLength:40] isEqualToString:@"a b c d"] && [[AGWebPairing sanitizedLabel:@"xxxxxxxxxx" maxLength:4] length] == 4);
		CHECK("user agents map to readable names",
			[[AGWebPairing deviceNameForUserAgent:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) AppleWebKit Version/17 Safari/604"] isEqualToString:@"iPhone (Safari)"] &&
			[[AGWebPairing deviceNameForUserAgent:@"Mozilla/5.0 (Windows NT 10.0) Chrome/120 Edg/120"] isEqualToString:@"Windows (Edge)"] &&
			[[AGWebPairing deviceNameForUserAgent:@"Mozilla/5.0 (Linux; Android 12; SM-T500) Chrome/110 Safari"] isEqualToString:@"Android (Chrome)"] &&
			[[AGWebPairing deviceNameForUserAgent:nil] isEqualToString:@"Unknown device"]);
		CHECK("random hex is the requested length and not repeated", [[AGWebPairing randomHexOfLength:40] length] == 40 && ![[AGWebPairing randomHexOfLength:32] isEqualToString:[AGWebPairing randomHexOfLength:32]]);

		// ================= API (through real sockets) =================
		FakeBridge *bridge = [[FakeBridge alloc] init];
		[AGWebAccess setBridge:bridge];
		[AGWebAccess setPagePathForTesting:[repo stringByAppendingPathComponent:@"Resources/agentic-web.html"]];
		[[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"web_access_port"];
		CHECK("port outside 1024...65535 is refused", ![AGWebAccess setPort:80] && ![AGWebAccess setPort:70000] && [AGWebAccess setPort:18733]);
		InstallPhone(1);
		[AGWebAccess setEnabled:YES];
		CHECK("Web Access switch starts the server", [AGWebAccess isRunning] && [AGWebAccess lastError] == nil);
		uint16_t wp = 18733;

		r = Get(wp, @"/", nil);
		CHECK("page is served without login", StatusOf(r) == 200 && [BodyOf(r) rangeOfString:@"Connect to Agentic"].location != NSNotFound);
		CHECK("page carries a content security policy", [r rangeOfString:@"Content-Security-Policy"].location != NSNotFound && [r rangeOfString:@"connect-src 'self'"].location != NSNotFound);
		CHECK("page has no external resources", [BodyOf(r) rangeOfString:@"http://"].location == NSNotFound || ![[NSRegularExpression regularExpressionWithPattern:@"(src|href)=\"https?://" options:0 error:nil] numberOfMatchesInString:BodyOf(r) options:0 range:NSMakeRange(0, [BodyOf(r) length])]);
		CHECK("viewport meta for small screens", [BodyOf(r) rangeOfString:@"width=device-width"].location != NSNotFound);

		CHECK("API without a token = 401", StatusOf(Get(wp, @"/api/state", nil)) == 401 && StatusOf(Get(wp, @"/api/chats", nil)) == 401 && StatusOf(Post(wp, @"/api/send", @"{\"text\":\"x\"}", nil)) == 401);
		CHECK("API with a made-up token = 401", StatusOf(Get(wp, @"/api/state", @"X-AG-Token: 0123456789012345678901234567890123456789\r\n")) == 401);
		CHECK("unknown path = 404, unknown API = 401", StatusOf(Get(wp, @"/nope", nil)) == 404 && StatusOf(Get(wp, @"/api/nope", nil)) == 401);

		[NSThread sleepForTimeInterval:0.1];
		NSString *tok = PairOver(wp, @"Test TV");
		CHECK("pairing over HTTP: phone asked, token issued", g_asked >= 1 && [tok length] == 40);
		NSString *auth = [NSString stringWithFormat:@"X-AG-Token: %@\r\n", tok];

		r = Get(wp, @"/api/state?rev=0&conv=&from=0", auth);
		j = JSON(BodyOf(r));
		CHECK("state returns snapshot, revision and device", StatusOf(r) == 200 && [[j objectForKey:@"conversation"] isEqualToString:@"conv1"] && [[j objectForKey:@"rev"] intValue] >= 1 && [[j objectForKey:@"model"] isEqualToString:@"test-model"] && [[j objectForKey:@"device"] hasPrefix:@"Test TV"]);
		CHECK("state says no approval is waiting", [[j objectForKey:@"approval"] isKindOfClass:[NSNull class]]);

		r = Post(wp, @"/api/send", @"{\"text\":\"  hello agent  \"}", auth);
		CHECK("send reaches the chat screen, trimmed", StatusOf(r) == 200 && [bridge->sent count] == 1 && [[bridge->sent objectAtIndex:0] isEqualToString:@"hello agent"]);
		CHECK("empty / wrong-typed / huge messages are refused", StatusOf(Post(wp, @"/api/send", @"{\"text\":\"   \"}", auth)) == 400 && StatusOf(Post(wp, @"/api/send", @"{\"text\":5}", auth)) == 400
			&& StatusOf(Post(wp, @"/api/send", @"not json", auth)) == 400);
		NSMutableString *long20k = [NSMutableString string]; for (int i = 0; i < 20001; i++) [long20k appendString:@"a"];
		CHECK("message over 20000 chars = 413", StatusOf(Post(wp, @"/api/send", [NSString stringWithFormat:@"{\"text\":\"%@\"}", long20k], auth)) == 413);
		bridge->busy = YES;
		r = Post(wp, @"/api/send", @"{\"text\":\"again\"}", auth);
		CHECK("send while a task runs = 409 with the reason", StatusOf(r) == 409 && [[JSON(BodyOf(r)) objectForKey:@"error"] rangeOfString:@"busy"].location != NSNotFound && [bridge->sent count] == 1);
		bridge->busy = NO;

		CHECK("stop and new chat are forwarded", StatusOf(Post(wp, @"/api/stop", @"{}", auth)) == 200 && bridge->stopped && StatusOf(Post(wp, @"/api/new", @"{}", auth)) == 200 && bridge->newChat);
		CHECK("open: path traversal ids never reach the store", StatusOf(Post(wp, @"/api/open", @"{\"id\":\"../../etc/passwd\"}", auth)) == 400 && bridge->opened == nil);
		CHECK("open: unknown chat = 404, known chat = 200", StatusOf(Post(wp, @"/api/open", @"{\"id\":\"missing\"}", auth)) == 404 && StatusOf(Post(wp, @"/api/open", @"{\"id\":\"known-chat\"}", auth)) == 200);
		CHECK("state-changing calls must be POST", StatusOf(Get(wp, @"/api/send", auth)) == 405 && StatusOf(Get(wp, @"/api/stop", auth)) == 405);
		CHECK("chat list works for a connected device", StatusOf(Get(wp, @"/api/chats", auth)) == 200 && [JSON(BodyOf(Get(wp, @"/api/chats", auth))) objectForKey:@"chats"] != nil);

		// cross-site protection
		CHECK("cross-site POST is refused", StatusOf(Post(wp, @"/api/send", @"{\"text\":\"x\"}", [auth stringByAppendingString:@"Origin: http://evil.example\r\n"])) == 403
			&& StatusOf(Post(wp, @"/api/pair", @"{}", @"Origin: http://evil.example\r\n")) == 403);
		CHECK("same-origin POST is accepted", StatusOf(Post(wp, @"/api/stop", @"{}", [auth stringByAppendingString:@"Origin: http://127.0.0.1\r\n"])) == 403 ? NO : YES);
		// DNS rebinding: a name chosen by another site's DNS must never be accepted as Host
		CHECK("a foreign Host name is refused (page, pairing, API)",
			StatusOf(Raw(wp, @"GET / HTTP/1.1\r\nHost: attacker.example:8080\r\n\r\n")) == 403
			&& StatusOf(Raw(wp, @"POST /api/pair HTTP/1.1\r\nHost: attacker.example\r\nOrigin: http://attacker.example\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}")) == 403
			&& StatusOf(Raw(wp, [NSString stringWithFormat:@"GET /api/state HTTP/1.1\r\nHost: attacker.example\r\n%@\r\n", auth])) == 403);
		CHECK("IP addresses, localhost and .local names are accepted",
			[AGWebAPI isAcceptableHost:@"192.168.1.20:8080"] && [AGWebAPI isAcceptableHost:@"127.0.0.1"] && [AGWebAPI isAcceptableHost:@"[::1]:8080"]
			&& [AGWebAPI isAcceptableHost:@"localhost:8080"] && [AGWebAPI isAcceptableHost:@"My-iPhone.local"]);
		CHECK("lookalikes and junk are refused",
			![AGWebAPI isAcceptableHost:@"192.168.1.20.evil.example"] && ![AGWebAPI isAcceptableHost:@"999.1.1.1x"] && ![AGWebAPI isAcceptableHost:@""]
			&& ![AGWebAPI isAcceptableHost:@"evil.example:80x"] && ![AGWebAPI isAcceptableHost:@"localhost.evil.example"] && ![AGWebAPI isAcceptableHost:@"[evil]"]);
		[[NSUserDefaults standardUserDefaults] setObject:[NSArray arrayWithObject:@"Phone.LAN"] forKey:@"agent_web_allowed_hosts"];
		CHECK("a name the user listed is accepted", [AGWebAPI isAcceptableHost:@"phone.lan:8080"] && ![AGWebAPI isAcceptableHost:@"other.lan"]);
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"agent_web_allowed_hosts"];
		CHECK("no CORS headers are ever sent", [Get(wp, @"/", @"Origin: http://evil.example\r\n") rangeOfString:@"Access-Control"].location == NSNotFound);

		// long polling
		NSString *revNow = [NSString stringWithFormat:@"%d", [[JSON(BodyOf(Get(wp, @"/api/state?rev=0", auth))) objectForKey:@"rev"] intValue]];
		NSTimeInterval t0 = [NSDate timeIntervalSinceReferenceDate];
		r = Get(wp, [NSString stringWithFormat:@"/api/state?rev=%@&conv=conv1&from=1", revNow], auth);
		NSTimeInterval waited = [NSDate timeIntervalSinceReferenceDate] - t0;
		CHECK("long poll waits for news, then answers (timeout)", StatusOf(r) == 200 && waited >= 0.9 && waited < 3.0);
		__block NSString *lr = nil;
		[AGWebAPI setLongPollTimeout:10.0];
		[BlockRunner run:^{ lr = [Get(wp, [NSString stringWithFormat:@"/api/state?rev=%@&conv=conv1&from=1", revNow], auth) retain]; }];
		[NSThread sleepForTimeInterval:0.4];
		t0 = [NSDate timeIntervalSinceReferenceDate];
		[[NSNotificationCenter defaultCenter] postNotificationName:AGAPIStatusDidChangeNotification object:[NSNumber numberWithBool:YES]];
		while (lr == nil && [NSDate timeIntervalSinceReferenceDate] - t0 < 3.0) [NSThread sleepForTimeInterval:0.02];
		CHECK("long poll wakes immediately when something changes", lr != nil && [NSDate timeIntervalSinceReferenceDate] - t0 < 1.0 && [[JSON(BodyOf(lr)) objectForKey:@"rev"] intValue] > [revNow intValue]);
		[AGWebAPI setLongPollTimeout:1.0];

		// agent approval question is visible to the page by title only
		__block NSString *pendingSeen = nil;
		[AGApproval setHandler:^(NSString *title, NSString *detail, NSString *label, AGApprovalResponder respond) {
			pendingSeen = [[AGApproval pendingTitle] copy];
			NSString *seen = [JSON(BodyOf(Get(wp, @"/api/state?rev=0", auth))) objectForKey:@"approval"];
			CHECK("page learns a question is waiting (title only, never the command)", [seen isEqualToString:@"Run make?"] && [BodyOf(Get(wp, @"/api/state?rev=0", auth)) rangeOfString:@"secret-command"].location == NSNotFound);
			respond(AGApprovalAllowOnce);
		}];
		NSString *denial = nil;
		[AGApproval requestApprovalForKey:nil title:@"Run make?" detail:@"secret-command -rf" taskLabel:nil isCancelled:nil denial:&denial];
		CHECK("pending title is cleared after the answer", [AGApproval pendingTitle] == nil && [pendingSeen isEqualToString:@"Run make?"]);
		CHECK("the page has NO endpoint to answer approvals", StatusOf(Post(wp, @"/api/approve", @"{\"allow\":true}", auth)) == 404 && StatusOf(Post(wp, @"/api/settings", @"{}", auth)) == 404);
		[AGApproval setHandler:NULL];

		// message JSON
		AGMessage *call = [AGMessage messageWithRole:@"assistant" content:@""];
		call.toolCalls = [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"c1", @"id", [NSDictionary dictionaryWithObjectsAndKeys:@"runShellCommand", @"name", @"{\"command\":\"ls -la\"}", @"arguments", nil], @"function", nil]];
		NSDictionary *cj = [AGWebAPI dictionaryForMessage:call index:7 displayText:@"> runShellCommand ls -la"];
		CHECK("call-only turn: no text, tool name and command listed", [[cj objectForKey:@"text"] isEqualToString:@""] && [[[[cj objectForKey:@"tools"] objectAtIndex:0] objectForKey:@"detail"] isEqualToString:@"ls -la"] && [[cj objectForKey:@"i"] intValue] == 7);
		AGMessage *tool = [AGMessage messageWithRole:@"tool" content:@"out"]; tool.toolName = @"readFile";
		AGMessage *note = [AGMessage messageWithRole:@"assistant" content:@"API key missing"]; note.localOnly = YES;
		CHECK("tool output carries the tool name; notices are flagged", [[[AGWebAPI dictionaryForMessage:tool index:0 displayText:@"out"] objectForKey:@"tool"] isEqualToString:@"readFile"] && [[[AGWebAPI dictionaryForMessage:note index:0 displayText:@"API key missing"] objectForKey:@"local"] boolValue]);
		CHECK("message JSON serializes", [NSJSONSerialization isValidJSONObject:[NSArray arrayWithObjects:cj, nil]]);

		// sign out
		CHECK("sign out revokes the token", StatusOf(Post(wp, @"/api/signout", @"{}", auth)) == 200 && StatusOf(Get(wp, @"/api/state", auth)) == 401);

		// port change while running + switch off
		CHECK("changing the port restarts the server", [AGWebAccess setPort:18734] && [AGWebAccess isRunning] && StatusOf(Get(18734, @"/", nil)) == 200);
		[NSThread sleepForTimeInterval:0.5];
		CHECK("old port is closed after a port change", Get(18733, @"/", nil) == nil);
		[AGWebAccess setEnabled:NO];
		[NSThread sleepForTimeInterval:0.5];
		CHECK("switch off: server stops, nothing answers", ![AGWebAccess isRunning] && Get(18734, @"/", nil) == nil);
		CHECK("address list is well-formed", ({ BOOL good = YES; for (NSString *u in [AGWebAccess addressURLs]) if (![u hasPrefix:@"http://"] || [u hasPrefix:@"http://127."] || [u hasPrefix:@"http://169.254."]) good = NO; good; }));

		// page missing
		[AGWebAccess setPagePathForTesting:@"/nonexistent/page.html"];
		[AGWebAccess setPort:18735]; [AGWebAccess setEnabled:YES];
		CHECK("missing page file gives a clear 500, not a crash", StatusOf(Get(18735, @"/", nil)) == 500);
		[AGWebAccess setEnabled:NO];
	}
	printf(fails == 0 ? "ALL PASSED (0 failures)\n" : "SOME FAILED (%d failures)\n", fails);
	return fails == 0 ? 0 : 1;
}
