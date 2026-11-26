#import <Foundation/Foundation.h>

/// A tiny HTTP/1.1 server on BSD sockets. Foundation-only (no UIKit), so it is also built by the
/// host tests. One thread per connection (capped), `Connection: close` on every answer, no TLS,
/// no chunked request bodies. It only knows how to read a request and write a response; what
/// the URLs mean is the handler's business (see AGWebAPI).

@interface AGHTTPRequest : NSObject {
@private
	NSString *_method;
	NSString *_path;
	NSDictionary *_query;
	NSDictionary *_headers;
	NSData *_body;
	NSString *_remoteAddress;
}
@property (nonatomic, retain) NSString *method;          // upper case
@property (nonatomic, retain) NSString *path;            // without the query string, percent-decoded
@property (nonatomic, retain) NSDictionary *query;       // decoded
@property (nonatomic, retain) NSDictionary *headers;     // keys lower case
@property (nonatomic, retain) NSData *body;
@property (nonatomic, retain) NSString *remoteAddress;   // dotted IPv4 of the peer (cannot be faked by the client)
- (NSString *)headerNamed:(NSString *)name;
/// The body parsed as a JSON object, or nil.
- (NSDictionary *)jsonBody;
@end

@interface AGHTTPResponse : NSObject {
@private
	int _status;
	NSMutableDictionary *_headers;
	NSData *_body;
}
@property (nonatomic, assign) int status;
@property (nonatomic, retain) NSMutableDictionary *headers;
@property (nonatomic, retain) NSData *body;
+ (AGHTTPResponse *)responseWithStatus:(int)status contentType:(NSString *)type body:(NSData *)body;
+ (AGHTTPResponse *)responseWithStatus:(int)status json:(id)object;
+ (AGHTTPResponse *)responseWithStatus:(int)status text:(NSString *)text;
@end

typedef AGHTTPResponse *(^AGHTTPHandler)(AGHTTPRequest *request);

@interface AGHTTPServer : NSObject {
@private
	int _listenFD;
	uint16_t _port;
	BOOL _running;
	NSUInteger _generation;       // bumped by every start/stop so an old accept loop notices
	NSUInteger _activeConnections;
	AGHTTPHandler _handler;
}

/// Called on a connection thread, so it may block (long polling). Must be thread-safe.
- (void)setHandler:(AGHTTPHandler)handler;

/// Starts listening on all IPv4 interfaces. NO plus a readable reason when it cannot (port in use...).
- (BOOL)startOnPort:(uint16_t)port error:(NSString **)error;
/// Stops accepting. Requests already being handled run to the end.
- (void)stop;

- (BOOL)isRunning;
- (uint16_t)port;

/// Limits (also used by the tests).
+ (NSUInteger)maxHeaderBytes;
+ (NSUInteger)maxBodyBytes;
+ (NSUInteger)maxConnections;

/// Pure parsing helpers (exposed for the tests).
+ (NSDictionary *)parseQueryString:(NSString *)query;
+ (NSString *)percentDecode:(NSString *)string;

@end
