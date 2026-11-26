#import <Foundation/Foundation.h>

/// Who may use the web page. There is no password: a device asks to connect, the question is
/// shown ON THE PHONE (see AGApprovalPresenter), and only a tap on Allow gives that device a
/// random token. The token is kept by the browser and sent with every request.
///
/// Foundation-only. With no UI hooked up in -setAsk:cancel: every request is denied (fail safe).

typedef enum {
	AGPairAnswerDeny = 0,
	AGPairAnswerAllow = 1,
	AGPairAnswerTimedOut = 2    // nobody answered, or the question was taken away
} AGPairAnswer;

/// Shows a question on the phone. `answer` may be called from any thread, once. Returns an opaque
/// handle for the cancel block. Called on any thread.
typedef id (^AGPairAsk)(NSString *title, NSString *detail, NSTimeInterval timeout, void (^answer)(AGPairAnswer answer));
/// Takes a question that is still showing off the screen (no answer is delivered for it).
typedef void (^AGPairCancel)(id handle);

extern NSString * const AGWebDevicesChangedNotification;

@interface AGWebPairing : NSObject {
@private
	AGPairAsk _ask;
	AGPairCancel _cancel;
	NSMutableDictionary *_pending;        // requestID -> pending request
	NSMutableDictionary *_addresses;      // ip -> history (cooldowns, blocks)
	NSMutableArray *_devices;             // of NSMutableDictionary (with "token")
	NSMutableDictionary *_tokenIndex;     // token -> device dictionary
	NSTimeInterval _lastPersist;
}

+ (AGWebPairing *)sharedPairing;

- (void)setAsk:(AGPairAsk)ask cancel:(AGPairCancel)cancel;

/// Seconds a pairing question waits for a tap (default 120).
+ (NSTimeInterval)requestTimeout;
/// Days of not being used after which a device must ask again (default 30).
+ (NSTimeInterval)deviceIdleLifetime;

#pragma mark - Web side

/// Starts (or restarts) a connection request from `address`. Returns the JSON for the web page:
///   {"id", "code", "status":"pending"}  or  {"error":"..."} with *httpStatus set (429 when asking too often).
- (NSDictionary *)beginRequestFromAddress:(NSString *)address clientName:(NSString *)clientName userAgent:(NSString *)userAgent httpStatus:(int *)httpStatus;
/// {"status":"pending"|"approved"|"denied"|"expired"|"unknown", "token":(only once, on approved)}.
- (NSDictionary *)pollRequestWithID:(NSString *)requestID;

/// The device record for a token (nil if the token is unknown or has expired). Counts as use.
- (NSDictionary *)deviceForToken:(NSString *)token;

#pragma mark - Phone side (settings screen)

/// [{id, name, address, created (NSNumber, unix), lastSeen (NSNumber)}], newest use first. Never contains tokens.
- (NSArray *)devices;
- (void)revokeDeviceWithID:(NSString *)deviceID;
- (void)revokeToken:(NSString *)token;
- (void)revokeAllDevices;
/// Withdraws everything still waiting for a tap (the web server was switched off).
- (void)cancelPendingRequests;

#pragma mark - Helpers (exposed for the tests)

+ (NSString *)deviceNameForUserAgent:(NSString *)userAgent;
+ (NSString *)sanitizedLabel:(NSString *)text maxLength:(NSUInteger)maxLength;
+ (NSString *)randomHexOfLength:(NSUInteger)length;

@end
