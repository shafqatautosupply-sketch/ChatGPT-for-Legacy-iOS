#import "AGWebPairing.h"
#include <stdio.h>
#include <stdlib.h>
#include <Block.h>

NSString * const AGWebDevicesChangedNotification = @"AGWebDevicesChangedNotification";

static NSString * const AGDevicesKey = @"web_devices";
static const NSUInteger AGMaxPending = 4;
static const NSUInteger AGMaxDevices = 12;
static const NSTimeInterval AGMinGapBetweenRequests = 2.0;
static const NSTimeInterval AGDenyCooldown = 30.0;
static const NSUInteger AGDeniesBeforeBlock = 3;
static const NSTimeInterval AGBlockTime = 600.0;
static const NSTimeInterval AGTouchPersistInterval = 600.0;

#pragma mark - Pending request / address history

@interface AGPendingPairing : NSObject {
@public
	NSString *requestID, *code, *name, *address;
	NSString *state;            // pending | approved | denied | expired
	NSString *token;            // set once approved, handed out once
	NSTimeInterval createdAt;
	id askHandle;
}
@end
@implementation AGPendingPairing
- (void)dealloc { [requestID release]; [code release]; [name release]; [address release]; [state release]; [token release]; [askHandle release]; [super dealloc]; }
@end

@interface AGAddressRecord : NSObject {
@public
	NSTimeInterval lastRequest, cooldownUntil, blockedUntil;
	NSUInteger denies;
}
@end
@implementation AGAddressRecord @end

@implementation AGWebPairing

+ (AGWebPairing *)sharedPairing {
	static AGWebPairing *shared = nil; static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[AGWebPairing alloc] init]; });
	return shared;
}

+ (NSTimeInterval)requestTimeout { return 120.0; }
+ (NSTimeInterval)deviceIdleLifetime { return 30.0 * 24.0 * 3600.0; }

- (id)init {
	self = [super init];
	if (self) {
		_pending = [[NSMutableDictionary alloc] init];
		_addresses = [[NSMutableDictionary alloc] init];
		_devices = [[NSMutableArray alloc] init];
		_tokenIndex = [[NSMutableDictionary alloc] init];
		[self loadDevices];
	}
	return self;
}

- (void)setAsk:(AGPairAsk)ask cancel:(AGPairCancel)cancel {
	@synchronized(self) {
		AGPairAsk oldAsk = _ask; AGPairCancel oldCancel = _cancel;
		_ask = (ask != NULL) ? Block_copy(ask) : NULL;
		_cancel = (cancel != NULL) ? Block_copy(cancel) : NULL;
		if (oldAsk != NULL) Block_release(oldAsk);
		if (oldCancel != NULL) Block_release(oldCancel);
	}
}

#pragma mark - Helpers

+ (NSString *)randomHexOfLength:(NSUInteger)length {
	NSUInteger bytes = (length + 1) / 2;
	uint8_t buffer[64];
	if (bytes > sizeof(buffer)) bytes = sizeof(buffer);
	BOOL ok = NO;
	FILE *file = fopen("/dev/urandom", "rb");
	if (file != NULL) { ok = (fread(buffer, 1, bytes, file) == bytes); fclose(file); }
	if (!ok) { for (NSUInteger i = 0; i < bytes; i++) buffer[i] = (uint8_t)(arc4random() & 0xff); }
	NSMutableString *hex = [NSMutableString stringWithCapacity:bytes * 2];
	for (NSUInteger i = 0; i < bytes; i++) [hex appendFormat:@"%02x", buffer[i]];
	return [hex substringToIndex:MIN(length, [hex length])];
}

/// Text that came from the network is shown in a phone dialog: no control characters, no long lines.
+ (NSString *)sanitizedLabel:(NSString *)text maxLength:(NSUInteger)maxLength {
	if (![text isKindOfClass:[NSString class]]) return @"";
	NSMutableString *out = [NSMutableString string];
	BOOL lastSpace = YES;
	for (NSUInteger i = 0; i < [text length] && [out length] < maxLength; i++) {
		unichar c = [text characterAtIndex:i];
		BOOL control = (c < 0x20 || (c >= 0x7f && c < 0xa0) || c == 0x2028 || c == 0x2029 || (c >= 0x202a && c <= 0x202e) || (c >= 0x2066 && c <= 0x2069));  // incl. bidi overrides
		if (control || c == ' ') { if (!lastSpace) [out appendString:@" "]; lastSpace = YES; continue; }
		[out appendFormat:@"%C", c];
		lastSpace = NO;
	}
	return [out stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+ (NSString *)deviceNameForUserAgent:(NSString *)ua {
	if (![ua isKindOfClass:[NSString class]] || [ua length] == 0) return @"Unknown device";
	NSString *lower = [ua lowercaseString];
	NSString *os = nil;
	if ([lower rangeOfString:@"android"].location != NSNotFound) os = ([lower rangeOfString:@"tv"].location != NSNotFound || [lower rangeOfString:@"aft"].location != NSNotFound || [lower rangeOfString:@"bravia"].location != NSNotFound) ? @"Android TV" : @"Android";
	else if ([lower rangeOfString:@"iphone"].location != NSNotFound) os = @"iPhone";
	else if ([lower rangeOfString:@"ipad"].location != NSNotFound) os = @"iPad";
	else if ([lower rangeOfString:@"smart-tv"].location != NSNotFound || [lower rangeOfString:@"smarttv"].location != NSNotFound || [lower rangeOfString:@"tizen"].location != NSNotFound || [lower rangeOfString:@"webos"].location != NSNotFound) os = @"Smart TV";
	else if ([lower rangeOfString:@"windows"].location != NSNotFound) os = @"Windows";
	else if ([lower rangeOfString:@"mac os"].location != NSNotFound) os = @"Mac";
	else if ([lower rangeOfString:@"cros"].location != NSNotFound) os = @"Chromebook";
	else if ([lower rangeOfString:@"linux"].location != NSNotFound) os = @"Linux";
	NSString *browser = nil;
	if ([lower rangeOfString:@"edg"].location != NSNotFound) browser = @"Edge";
	else if ([lower rangeOfString:@"firefox"].location != NSNotFound) browser = @"Firefox";
	else if ([lower rangeOfString:@"opr/"].location != NSNotFound || [lower rangeOfString:@"opera"].location != NSNotFound) browser = @"Opera";
	else if ([lower rangeOfString:@"chrome"].location != NSNotFound || [lower rangeOfString:@"crios"].location != NSNotFound) browser = @"Chrome";
	else if ([lower rangeOfString:@"safari"].location != NSNotFound) browser = @"Safari";
	if (os != nil && browser != nil) return [NSString stringWithFormat:@"%@ (%@)", os, browser];
	return os ?: browser ?: @"Unknown device";
}

#pragma mark - Persistence

- (void)loadDevices {
	id stored = [[NSUserDefaults standardUserDefaults] objectForKey:AGDevicesKey];
	if (![stored isKindOfClass:[NSArray class]]) return;
	for (id entry in stored) {
		if (![entry isKindOfClass:[NSDictionary class]]) continue;
		NSString *token = [entry objectForKey:@"token"], *deviceID = [entry objectForKey:@"id"];
		if (![token isKindOfClass:[NSString class]] || [token length] < 32 || ![deviceID isKindOfClass:[NSString class]]) continue;
		NSMutableDictionary *device = [NSMutableDictionary dictionaryWithDictionary:entry];
		[_devices addObject:device];
		[_tokenIndex setObject:device forKey:token];
	}
}

/// Caller holds the lock.
- (void)persistLocked {
	[[NSUserDefaults standardUserDefaults] setObject:[NSArray arrayWithArray:_devices] forKey:AGDevicesKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
	_lastPersist = [NSDate timeIntervalSinceReferenceDate];
}

- (void)postChange {
	dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:AGWebDevicesChangedNotification object:nil]; });
}

#pragma mark - Web side

/// Caller holds the lock. Moves a pending request past its deadline to "expired" and takes its question off the phone.
- (void)expireIfNeeded:(AGPendingPairing *)pairing {
	if (![pairing->state isEqualToString:@"pending"]) return;
	if ([NSDate timeIntervalSinceReferenceDate] - pairing->createdAt <= [AGWebPairing requestTimeout] + 5.0) return;
	[pairing->state release]; pairing->state = [@"expired" retain];
	[self withdrawQuestionOfLocked:pairing];
}

- (void)withdrawQuestionOfLocked:(AGPendingPairing *)pairing {
	id handle = [[pairing->askHandle retain] autorelease];
	if (handle == nil) return;
	[pairing->askHandle release]; pairing->askHandle = nil;
	if (_cancel != NULL) {
		AGPairCancel cancel = Block_copy(_cancel);
		cancel(handle);   // the UI only schedules the removal; it never calls back into us from here
		Block_release(cancel);
	}
}

- (NSDictionary *)beginRequestFromAddress:(NSString *)address clientName:(NSString *)clientName userAgent:(NSString *)userAgent httpStatus:(int *)httpStatus {
	if (httpStatus) *httpStatus = 200;
	if (address == nil) address = @"?";
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSString *name = [AGWebPairing sanitizedLabel:clientName maxLength:40];
	NSString *guess = [AGWebPairing deviceNameForUserAgent:userAgent];
	if ([name length] == 0) name = guess;
	else if (![name isEqualToString:guess] && ![guess isEqualToString:@"Unknown device"]) name = [NSString stringWithFormat:@"%@ [%@]", name, guess];
	name = [AGWebPairing sanitizedLabel:name maxLength:64];

	AGPendingPairing *pairing = nil;
	AGPairAsk ask = NULL;
	@synchronized(self) {
		AGAddressRecord *record = [_addresses objectForKey:address];
		if (record == nil) { record = [[[AGAddressRecord alloc] init] autorelease]; [_addresses setObject:record forKey:address]; }
		if (record->blockedUntil > now) {
			if (httpStatus) *httpStatus = 429;
			return [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Too many refused requests. Try again in %d minutes.", (int)((record->blockedUntil - now) / 60.0) + 1] forKey:@"error"];
		}
		if (record->cooldownUntil > now) {
			if (httpStatus) *httpStatus = 429;
			return [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The request was refused. Wait %d seconds before asking again.", (int)(record->cooldownUntil - now) + 1] forKey:@"error"];
		}
		if (now - record->lastRequest < AGMinGapBetweenRequests) {
			if (httpStatus) *httpStatus = 429;
			return [NSDictionary dictionaryWithObject:@"Please wait a moment before asking again." forKey:@"error"];
		}
		record->lastRequest = now;

		// A new request from the same address replaces its old one (page reload).
		NSMutableArray *replaced = [NSMutableArray array];
		for (NSString *key in _pending) { AGPendingPairing *old = [_pending objectForKey:key]; if ([old->address isEqualToString:address]) [replaced addObject:key]; }
		for (NSString *key in replaced) { AGPendingPairing *old = [_pending objectForKey:key]; [self withdrawQuestionOfLocked:old]; [_pending removeObjectForKey:key]; }

		// Housekeeping: finished requests nobody collected, and expired ones.
		NSMutableArray *drop = [NSMutableArray array];
		for (NSString *key in _pending) {
			AGPendingPairing *other = [_pending objectForKey:key];
			[self expireIfNeeded:other];
			if (![other->state isEqualToString:@"pending"] && now - other->createdAt > [AGWebPairing requestTimeout] + 60.0) [drop addObject:key];
		}
		[_pending removeObjectsForKeys:drop];

		NSUInteger waiting = 0;
		for (NSString *key in _pending) { AGPendingPairing *other = [_pending objectForKey:key]; if ([other->state isEqualToString:@"pending"]) waiting++; }
		if (waiting >= AGMaxPending) {
			if (httpStatus) *httpStatus = 429;
			return [NSDictionary dictionaryWithObject:@"Too many devices are asking at once. Try again shortly." forKey:@"error"];
		}

		pairing = [[[AGPendingPairing alloc] init] autorelease];
		pairing->requestID = [[AGWebPairing randomHexOfLength:24] retain];
		pairing->code = [[NSString stringWithFormat:@"%04u", (unsigned)(arc4random() % 10000)] retain];
		pairing->name = [name retain];
		pairing->address = [address retain];
		pairing->state = [@"pending" retain];
		pairing->createdAt = now;
		[_pending setObject:pairing forKey:pairing->requestID];
		if (_ask != NULL) ask = Block_copy(_ask);
	}

	if (ask == NULL) {   // no screen to ask on: deny, never allow
		@synchronized(self) { [pairing->state release]; pairing->state = [@"denied" retain]; }
		return [NSDictionary dictionaryWithObjectsAndKeys:pairing->requestID, @"id", pairing->code, @"code", @"pending", @"status", nil];
	}

	NSString *detail = [NSString stringWithFormat:@"%@\nAddress: %@\nCode: %@\n\nCheck that the web page shows the same code. Allowing lets this device chat with the model and use the agent in your workspace. make, python and deleting files still ask you here.",
		pairing->name, pairing->address, pairing->code];
	NSString *requestID = [[pairing->requestID copy] autorelease];
	AGWebPairing *me = self;
	id handle = ask(@"Allow web access?", detail, [AGWebPairing requestTimeout], ^(AGPairAnswer answer) {
		[me finishRequestID:requestID withAnswer:answer];
	});
	Block_release(ask);
	@synchronized(self) {
		if ([pairing->state isEqualToString:@"pending"]) pairing->askHandle = [handle retain];
	}
	return [NSDictionary dictionaryWithObjectsAndKeys:pairing->requestID, @"id", pairing->code, @"code", @"pending", @"status", nil];
}

/// The phone answered (any thread).
- (void)finishRequestID:(NSString *)requestID withAnswer:(AGPairAnswer)answer {
	BOOL changed = NO;
	@synchronized(self) {
		AGPendingPairing *pairing = [_pending objectForKey:requestID];
		if (pairing == nil || ![pairing->state isEqualToString:@"pending"]) return;
		[pairing->askHandle release]; pairing->askHandle = nil;   // already gone from the screen
		NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

		if (answer == AGPairAnswerAllow) {
			NSString *token = [AGWebPairing randomHexOfLength:40];
			NSMutableDictionary *device = [NSMutableDictionary dictionaryWithObjectsAndKeys:
				[AGWebPairing randomHexOfLength:8], @"id", token, @"token", pairing->name, @"name", pairing->address, @"address",
				[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]], @"created",
				[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]], @"lastSeen", nil];
			[_devices addObject:device];
			[_tokenIndex setObject:device forKey:token];
			while ([_devices count] > AGMaxDevices) {   // oldest-used device falls off
				NSMutableDictionary *oldest = [_devices objectAtIndex:0];
				for (NSMutableDictionary *candidate in _devices) if ([[candidate objectForKey:@"lastSeen"] doubleValue] < [[oldest objectForKey:@"lastSeen"] doubleValue]) oldest = candidate;
				[_tokenIndex removeObjectForKey:[oldest objectForKey:@"token"]];
				[_devices removeObject:oldest];
			}
			[self persistLocked];
			pairing->token = [token retain];
			[pairing->state release]; pairing->state = [@"approved" retain];
			AGAddressRecord *record = [_addresses objectForKey:pairing->address];
			if (record != nil) { record->denies = 0; record->cooldownUntil = 0; }
			changed = YES;
		} else if (answer == AGPairAnswerDeny) {
			[pairing->state release]; pairing->state = [@"denied" retain];
			AGAddressRecord *record = [_addresses objectForKey:pairing->address];
			if (record != nil) {
				record->denies++;
				record->cooldownUntil = now + AGDenyCooldown;
				if (record->denies >= AGDeniesBeforeBlock) { record->blockedUntil = now + AGBlockTime; record->denies = 0; }
			}
		} else {
			[pairing->state release]; pairing->state = [@"expired" retain];
		}
	}
	if (changed) [self postChange];
}

- (NSDictionary *)pollRequestWithID:(NSString *)requestID {
	@synchronized(self) {
		AGPendingPairing *pairing = [requestID isKindOfClass:[NSString class]] ? [_pending objectForKey:requestID] : nil;
		if (pairing == nil) return [NSDictionary dictionaryWithObject:@"unknown" forKey:@"status"];
		[self expireIfNeeded:pairing];
		NSString *state = [[pairing->state copy] autorelease];
		if ([state isEqualToString:@"approved"]) {
			NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:@"approved", @"status", pairing->token ?: @"", @"token", nil];
			[_pending removeObjectForKey:requestID];   // the token leaves this object exactly once
			return result;
		}
		if (![state isEqualToString:@"pending"]) [_pending removeObjectForKey:requestID];
		return [NSDictionary dictionaryWithObject:state forKey:@"status"];
	}
}

- (NSDictionary *)deviceForToken:(NSString *)token {
	if (![token isKindOfClass:[NSString class]] || [token length] < 32 || [token length] > 128) return nil;
	@synchronized(self) {
		NSMutableDictionary *device = [_tokenIndex objectForKey:token];
		if (device == nil) return nil;
		double now = [[NSDate date] timeIntervalSince1970];
		if (now - [[device objectForKey:@"lastSeen"] doubleValue] > [AGWebPairing deviceIdleLifetime]) {
			[_tokenIndex removeObjectForKey:token];
			[_devices removeObject:device];
			[self persistLocked];
			[self postChange];
			return nil;
		}
		BOOL persistDue = ([NSDate timeIntervalSinceReferenceDate] - _lastPersist) > AGTouchPersistInterval;
		[device setObject:[NSNumber numberWithDouble:now] forKey:@"lastSeen"];
		if (persistDue) [self persistLocked];
		return [NSDictionary dictionaryWithObjectsAndKeys:[device objectForKey:@"id"], @"id", [device objectForKey:@"name"] ?: @"Device", @"name", nil];
	}
}

#pragma mark - Phone side

- (NSArray *)devices {
	@synchronized(self) {
		NSMutableArray *list = [NSMutableArray array];
		for (NSDictionary *device in _devices) {
			[list addObject:[NSDictionary dictionaryWithObjectsAndKeys:
				[device objectForKey:@"id"], @"id", [device objectForKey:@"name"] ?: @"Device", @"name", [device objectForKey:@"address"] ?: @"", @"address",
				[device objectForKey:@"created"] ?: [NSNumber numberWithInt:0], @"created", [device objectForKey:@"lastSeen"] ?: [NSNumber numberWithInt:0], @"lastSeen", nil]];
		}
		[list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			return [[b objectForKey:@"lastSeen"] compare:[a objectForKey:@"lastSeen"]];
		}];
		return list;
	}
}

- (void)revokeDeviceWithID:(NSString *)deviceID {
	@synchronized(self) {
		NSMutableDictionary *found = nil;
		for (NSMutableDictionary *device in _devices) if ([[device objectForKey:@"id"] isEqualToString:deviceID]) { found = device; break; }
		if (found == nil) return;
		[_tokenIndex removeObjectForKey:[found objectForKey:@"token"]];
		[_devices removeObject:found];
		[self persistLocked];
	}
	[self postChange];
}

- (void)revokeToken:(NSString *)token {
	NSString *deviceID = nil;
	@synchronized(self) { deviceID = [[_tokenIndex objectForKey:token] objectForKey:@"id"]; }
	if (deviceID != nil) [self revokeDeviceWithID:deviceID];
}

- (void)revokeAllDevices {
	@synchronized(self) {
		[_devices removeAllObjects];
		[_tokenIndex removeAllObjects];
		[self persistLocked];
	}
	[self postChange];
}

- (void)cancelPendingRequests {
	@synchronized(self) {
		for (NSString *key in [_pending allKeys]) { [self withdrawQuestionOfLocked:[_pending objectForKey:key]]; }
		[_pending removeAllObjects];
	}
}

- (void)dealloc {
	[self setAsk:NULL cancel:NULL];
	[_pending release]; [_addresses release]; [_devices release]; [_tokenIndex release];
	[super dealloc];
}

@end
