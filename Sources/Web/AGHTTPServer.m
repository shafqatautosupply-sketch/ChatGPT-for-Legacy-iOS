#import "AGHTTPServer.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <Block.h>

static const NSUInteger AGMaxHeaderBytes = 16 * 1024;
static const NSUInteger AGMaxBodyBytes = 256 * 1024;
static const NSUInteger AGMaxConnections = 16;
static const NSTimeInterval AGReadDeadline = 15.0;   // whole request must arrive within this

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#pragma mark - Request / response

@implementation AGHTTPRequest
@synthesize method = _method;
@synthesize path = _path;
@synthesize query = _query;
@synthesize headers = _headers;
@synthesize body = _body;
@synthesize remoteAddress = _remoteAddress;

- (NSString *)headerNamed:(NSString *)name { return [_headers objectForKey:[name lowercaseString]]; }

- (NSDictionary *)jsonBody {
	if ([_body length] == 0) return nil;
	id object = [NSJSONSerialization JSONObjectWithData:_body options:0 error:nil];
	return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

- (void)dealloc {
	[_method release]; [_path release]; [_query release]; [_headers release]; [_body release]; [_remoteAddress release];
	[super dealloc];
}
@end

@implementation AGHTTPResponse
@synthesize status = _status;
@synthesize headers = _headers;
@synthesize body = _body;

- (id)init {
	self = [super init];
	if (self) { _status = 200; _headers = [[NSMutableDictionary alloc] init]; }
	return self;
}

+ (AGHTTPResponse *)responseWithStatus:(int)status contentType:(NSString *)type body:(NSData *)body {
	AGHTTPResponse *response = [[[AGHTTPResponse alloc] init] autorelease];
	response.status = status;
	response.body = body ?: [NSData data];
	if (type != nil) [response.headers setObject:type forKey:@"Content-Type"];
	return response;
}

+ (AGHTTPResponse *)responseWithStatus:(int)status json:(id)object {
	NSData *data = nil;
	if (object != nil && [NSJSONSerialization isValidJSONObject:object]) data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
	if (data == nil) data = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
	return [self responseWithStatus:status contentType:@"application/json; charset=utf-8" body:data];
}

+ (AGHTTPResponse *)responseWithStatus:(int)status text:(NSString *)text {
	return [self responseWithStatus:status contentType:@"text/plain; charset=utf-8" body:[(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)dealloc { [_headers release]; [_body release]; [super dealloc]; }
@end

#pragma mark - Server

@implementation AGHTTPServer

+ (NSUInteger)maxHeaderBytes { return AGMaxHeaderBytes; }
+ (NSUInteger)maxBodyBytes { return AGMaxBodyBytes; }
+ (NSUInteger)maxConnections { return AGMaxConnections; }

- (id)init {
	self = [super init];
	if (self) _listenFD = -1;
	return self;
}

- (void)setHandler:(AGHTTPHandler)handler {
	@synchronized(self) {
		AGHTTPHandler old = _handler;
		_handler = (handler != NULL) ? Block_copy(handler) : NULL;
		if (old != NULL) Block_release(old);
	}
}

- (BOOL)isRunning { @synchronized(self) { return _running; } }
- (uint16_t)port { @synchronized(self) { return _port; } }

#pragma mark Start / stop

- (BOOL)startOnPort:(uint16_t)port error:(NSString **)error {
	@synchronized(self) {
		if (_running) return YES;

		int fd = socket(AF_INET, SOCK_STREAM, 0);
		if (fd < 0) { if (error) *error = [NSString stringWithFormat:@"Could not create a socket (%s).", strerror(errno)]; return NO; }

		int yes = 1;
		setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
#ifdef SO_NOSIGPIPE
		setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
		struct sockaddr_in addr;
		memset(&addr, 0, sizeof(addr));
		addr.sin_family = AF_INET;
		addr.sin_addr.s_addr = htonl(INADDR_ANY);
		addr.sin_port = htons(port);
		if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
			int code = errno;
			close(fd);
			if (error) *error = (code == EADDRINUSE) ? [NSString stringWithFormat:@"Port %u is already in use. Pick another port.", (unsigned)port]
				: [NSString stringWithFormat:@"Could not listen on port %u (%s).", (unsigned)port, strerror(code)];
			return NO;
		}
		if (listen(fd, 16) != 0) {
			int code = errno;
			close(fd);
			if (error) *error = [NSString stringWithFormat:@"listen failed (%s).", strerror(code)];
			return NO;
		}
		if (port == 0) {   // ephemeral port (tests)
			socklen_t len = sizeof(addr);
			if (getsockname(fd, (struct sockaddr *)&addr, &len) == 0) port = ntohs(addr.sin_port);
		}
		_listenFD = fd;
		_port = port;
		_running = YES;
		_generation++;
		NSUInteger generation = _generation;
		[NSThread detachNewThreadSelector:@selector(acceptLoop:) toTarget:self withObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:fd], [NSNumber numberWithUnsignedInteger:generation], nil]];
	}
	return YES;
}

- (void)stop {
	@synchronized(self) {
		if (!_running) return;
		_running = NO;
		_generation++;
		if (_listenFD >= 0) { int fd = _listenFD; _listenFD = -1; shutdown(fd, SHUT_RDWR); close(fd); }
	}
}

- (BOOL)stillCurrent:(NSUInteger)generation {
	@synchronized(self) { return _running && generation == _generation; }
}

#pragma mark Accept loop

- (void)acceptLoop:(NSArray *)info {
	@autoreleasepool {
		int listenFD = [[info objectAtIndex:0] intValue];
		NSUInteger generation = [[info objectAtIndex:1] unsignedIntegerValue];
		while ([self stillCurrent:generation]) {
			fd_set readSet;
			FD_ZERO(&readSet);
			FD_SET(listenFD, &readSet);
			struct timeval timeout = { 0, 300000 };   // wake up to notice stop()
			int ready = select(listenFD + 1, &readSet, NULL, NULL, &timeout);
			if (ready <= 0) { if (ready < 0 && errno != EINTR && ![self stillCurrent:generation]) break; continue; }

			struct sockaddr_in peer;
			socklen_t peerLen = sizeof(peer);
			int client = accept(listenFD, (struct sockaddr *)&peer, &peerLen);
			if (client < 0) continue;

			char text[INET_ADDRSTRLEN] = "";
			inet_ntop(AF_INET, &peer.sin_addr, text, sizeof(text));
			NSString *address = [NSString stringWithUTF8String:text] ?: @"?";

			BOOL accepted = NO;
			@synchronized(self) { if (_activeConnections < AGMaxConnections) { _activeConnections++; accepted = YES; } }
			if (!accepted) {
				[AGHTTPServer writeResponse:[AGHTTPResponse responseWithStatus:503 text:@"Too many connections."] toFD:client];
				close(client);
				continue;
			}
			[NSThread detachNewThreadSelector:@selector(serveConnection:) toTarget:self
				withObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:client], address, nil]];
		}
	}
}

#pragma mark One connection

- (void)serveConnection:(NSArray *)info {
	@autoreleasepool {
		int fd = [[info objectAtIndex:0] intValue];
		NSString *address = [info objectAtIndex:1];
		@try {
#ifdef SO_NOSIGPIPE
			int yes = 1;
			setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
			struct timeval receiveTimeout = { 5, 0 };
			setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, sizeof(receiveTimeout));
			struct timeval sendTimeout = { 15, 0 };
			setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, sizeof(sendTimeout));

			int failure = 0;
			AGHTTPRequest *request = [AGHTTPServer readRequestFromFD:fd address:address failure:&failure];
			AGHTTPResponse *response = nil;
			if (request == nil) {
				if (failure != 0) response = [AGHTTPResponse responseWithStatus:failure text:(failure == 413 ? @"Request too large." : failure == 408 ? @"Request timed out." : @"Bad request.")];
			} else {
				AGHTTPHandler handler = NULL;
				@synchronized(self) { if (_handler != NULL) handler = Block_copy(_handler); }
				if (handler == NULL) {
					response = [AGHTTPResponse responseWithStatus:503 text:@"Not ready."];
				} else {
					@try { response = handler(request); }
					@catch (NSException *exception) { response = [AGHTTPResponse responseWithStatus:500 text:@"Internal error."]; }
					Block_release(handler);
					if (response == nil) response = [AGHTTPResponse responseWithStatus:404 text:@"Not found."];
				}
			}
			if (response != nil) {   // nil = the client went away without sending anything
				[AGHTTPServer writeResponse:response toFD:fd];
				shutdown(fd, SHUT_WR);
				// Drain briefly so the client reads the whole answer before the socket closes.
				char sink[256];
				struct timeval drain = { 0, 200000 };
				setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &drain, sizeof(drain));
				while (recv(fd, sink, sizeof(sink), 0) > 0) {}
			}
		} @catch (NSException *exception) {
			// fall through to close
		}
		close(fd);
		@synchronized(self) { if (_activeConnections > 0) _activeConnections--; }
	}
}

#pragma mark Reading

/// failure: 0 = connection closed/idle (say nothing), else the HTTP status to answer with.
+ (AGHTTPRequest *)readRequestFromFD:(int)fd address:(NSString *)address failure:(int *)failure {
	NSMutableData *buffer = [NSMutableData data];
	NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + AGReadDeadline;
	NSRange headerEnd = NSMakeRange(NSNotFound, 0);
	NSData *terminator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];

	uint8_t chunk[4096];
	while (headerEnd.location == NSNotFound) {
		if ([NSDate timeIntervalSinceReferenceDate] > deadline) { *failure = [buffer length] > 0 ? 408 : 0; return nil; }
		ssize_t got = recv(fd, chunk, sizeof(chunk), 0);
		if (got == 0) { *failure = 0; return nil; }
		if (got < 0) {
			if (errno == EINTR) continue;
			if (errno == EAGAIN || errno == EWOULDBLOCK) continue;   // receive timeout slice: the deadline above decides
			*failure = 0; return nil;
		}
		[buffer appendBytes:chunk length:(NSUInteger)got];
		headerEnd = [buffer rangeOfData:terminator options:0 range:NSMakeRange(0, [buffer length])];
		if (headerEnd.location == NSNotFound && [buffer length] > AGMaxHeaderBytes) { *failure = 431; return nil; }
		if (headerEnd.location != NSNotFound && headerEnd.location > AGMaxHeaderBytes) { *failure = 431; return nil; }
	}

	NSData *headData = [buffer subdataWithRange:NSMakeRange(0, headerEnd.location)];
	NSString *head = [[[NSString alloc] initWithData:headData encoding:NSUTF8StringEncoding] autorelease];
	if (head == nil) head = [[[NSString alloc] initWithData:headData encoding:NSISOLatin1StringEncoding] autorelease];
	if (head == nil) { *failure = 400; return nil; }

	NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
	NSArray *requestLine = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
	if ([requestLine count] != 3 || ![[requestLine objectAtIndex:2] hasPrefix:@"HTTP/1."]) { *failure = 400; return nil; }

	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	for (NSUInteger i = 1; i < [lines count]; i++) {
		NSString *line = [lines objectAtIndex:i];
		NSRange colon = [line rangeOfString:@":"];
		if (colon.location == NSNotFound || colon.location == 0) { *failure = 400; return nil; }
		NSString *name = [[[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
		NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([headers objectForKey:name] != nil && [name isEqualToString:@"content-length"]) { *failure = 400; return nil; }   // ambiguous framing
		[headers setObject:value forKey:name];
	}
	if ([headers objectForKey:@"transfer-encoding"] != nil) { *failure = 400; return nil; }   // chunked requests are not supported

	NSUInteger contentLength = 0;
	NSString *lengthText = [headers objectForKey:@"content-length"];
	if (lengthText != nil) {
		NSScanner *scanner = [NSScanner scannerWithString:lengthText];
		long long value = -1;
		if (![scanner scanLongLong:&value] || ![scanner isAtEnd] || value < 0) { *failure = 400; return nil; }
		if ((unsigned long long)value > AGMaxBodyBytes) { *failure = 413; return nil; }
		contentLength = (NSUInteger)value;
	}

	NSUInteger bodyStart = headerEnd.location + 4;
	NSMutableData *body = [NSMutableData data];
	if ([buffer length] > bodyStart) [body appendData:[buffer subdataWithRange:NSMakeRange(bodyStart, MIN([buffer length] - bodyStart, contentLength))]];
	while ([body length] < contentLength) {
		if ([NSDate timeIntervalSinceReferenceDate] > deadline) { *failure = 408; return nil; }
		ssize_t got = recv(fd, chunk, sizeof(chunk), 0);
		if (got == 0) { *failure = 400; return nil; }
		if (got < 0) {
			if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
			*failure = 0; return nil;
		}
		NSUInteger need = contentLength - [body length];
		[body appendBytes:chunk length:MIN((NSUInteger)got, need)];
	}

	NSString *target = [requestLine objectAtIndex:1];
	NSString *rawPath = target, *rawQuery = nil;
	NSRange question = [target rangeOfString:@"?"];
	if (question.location != NSNotFound) { rawPath = [target substringToIndex:question.location]; rawQuery = [target substringFromIndex:question.location + 1]; }
	if ([rawPath rangeOfString:@"#"].location != NSNotFound) rawPath = [rawPath substringToIndex:[rawPath rangeOfString:@"#"].location];
	if (![rawPath hasPrefix:@"/"]) { *failure = 400; return nil; }

	AGHTTPRequest *request = [[[AGHTTPRequest alloc] init] autorelease];
	request.method = [[requestLine objectAtIndex:0] uppercaseString];
	request.path = [self percentDecode:rawPath] ?: rawPath;
	request.query = [self parseQueryString:rawQuery];
	request.headers = headers;
	request.body = body;
	request.remoteAddress = address;
	return request;
}

+ (NSString *)percentDecode:(NSString *)string {
	if (string == nil) return nil;
	NSString *plus = [string stringByReplacingOccurrencesOfString:@"+" withString:@" "];
	return [plus stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

+ (NSDictionary *)parseQueryString:(NSString *)query {
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	if ([query length] == 0) return result;
	for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
		if ([pair length] == 0) continue;
		NSRange equals = [pair rangeOfString:@"="];
		NSString *key = (equals.location == NSNotFound) ? pair : [pair substringToIndex:equals.location];
		NSString *value = (equals.location == NSNotFound) ? @"" : [pair substringFromIndex:equals.location + 1];
		key = [self percentDecode:key]; value = [self percentDecode:value];
		if ([key length] > 0 && value != nil && [result objectForKey:key] == nil) [result setObject:value forKey:key];
	}
	return result;
}

#pragma mark Writing

+ (NSString *)reasonForStatus:(int)status {
	switch (status) {
		case 200: return @"OK"; case 204: return @"No Content"; case 400: return @"Bad Request"; case 401: return @"Unauthorized";
		case 403: return @"Forbidden"; case 404: return @"Not Found"; case 405: return @"Method Not Allowed"; case 408: return @"Request Timeout";
		case 409: return @"Conflict"; case 413: return @"Payload Too Large"; case 429: return @"Too Many Requests";
		case 431: return @"Request Header Fields Too Large"; case 500: return @"Internal Server Error"; case 503: return @"Service Unavailable";
		default: return @"Status";
	}
}

+ (void)writeResponse:(AGHTTPResponse *)response toFD:(int)fd {
	NSMutableString *head = [NSMutableString string];
	[head appendFormat:@"HTTP/1.1 %d %@\r\n", response.status, [self reasonForStatus:response.status]];
	NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:response.headers];
	[headers setObject:[NSString stringWithFormat:@"%lu", (unsigned long)[response.body length]] forKey:@"Content-Length"];
	[headers setObject:@"close" forKey:@"Connection"];
	if ([headers objectForKey:@"Cache-Control"] == nil) [headers setObject:@"no-store" forKey:@"Cache-Control"];
	[headers setObject:@"nosniff" forKey:@"X-Content-Type-Options"];
	[headers setObject:@"no-referrer" forKey:@"Referrer-Policy"];
	[headers setObject:@"DENY" forKey:@"X-Frame-Options"];
	for (NSString *name in headers) {
		// Header values come from our own code, but never let a CR/LF through.
		NSString *value = [[[headers objectForKey:name] description] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
		value = [value stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
		[head appendFormat:@"%@: %@\r\n", name, value];
	}
	[head appendString:@"\r\n"];

	NSMutableData *out = [NSMutableData dataWithData:[head dataUsingEncoding:NSUTF8StringEncoding]];
	if (response.body != nil) [out appendData:response.body];
	const uint8_t *bytes = [out bytes];
	NSUInteger sent = 0, total = [out length];
	while (sent < total) {
		ssize_t n = send(fd, bytes + sent, total - sent, MSG_NOSIGNAL);
		if (n < 0) { if (errno == EINTR) continue; break; }
		if (n == 0) break;
		sent += (NSUInteger)n;
	}
}

- (void)dealloc {
	[self stop];
	if (_handler != NULL) Block_release(_handler);
	[super dealloc];
}

@end
