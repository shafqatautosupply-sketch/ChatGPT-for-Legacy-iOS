#import "AGGeminiClient.h"
#import "AGProviderConfig.h"
#import "AGMessage.h"
#import "AGGuardrails.h"
#import "AGAgentTools.h"
#import "AGHTTPClient.h"
#import "AGContextBuilder.h"
#import "AGConversationStore.h"
#import <UIKit/UIKit.h>

NSString * const AGAPIResponseNotification = @"AGAPIResponseNotification";
NSString * const AGAPIMessageDidUpdateNotification = @"AGAPIMessageDidUpdateNotification";
NSString * const AGAPIStatusDidChangeNotification = @"AGAPIStatusDidChangeNotification";
NSString * const AGPureChatModeChangedNotification = @"AGPureChatModeChangedNotification";
NSString * const AGAgentModeChangedNotification = @"AGAgentModeChangedNotification";
NSString * const AGTerminalModeChangedNotification = @"AGTerminalModeChangedNotification";
NSString * const AGMarkdownModeChangedNotification = @"AGMarkdownModeChangedNotification";
NSString * const AGAPIRunUserInfoKey = @"run";

static NSString * const AGPureChatModeKey = @"lc_pure_chat_mode_enabled";
static NSString * const AGAgentModeKey = @"lc_agent_mode_enabled";
static NSString * const AGTerminalModeKey = @"lc_terminal_mode_enabled";
static NSString * const AGMarkdownModeKey = @"lc_markdown_mode_enabled";
static NSString * const AGRequestIntervalKey = @"agent_min_request_interval";
static NSString * const AGLastUsageKey = @"ag_last_usage";

/// Identifies the live run. Starting or cancelling a run bumps it, and every loop
/// compares its own number against it. (The old single BOOL "cancelled" flag was
/// reset by the next send, which revived the old loop: two agents wrote into the
/// same chat.)
static volatile NSUInteger g_currentRun = 0;

@implementation AGGeminiClient

#pragma mark - Modes

+ (BOOL)isAgentModeEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:AGAgentModeKey] == nil) {
		if ([defaults objectForKey:AGPureChatModeKey] != nil) return ![defaults boolForKey:AGPureChatModeKey];
		return YES;
	}
	return [defaults boolForKey:AGAgentModeKey];
}

+ (void)setAgentModeEnabled:(BOOL)enabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:enabled forKey:AGAgentModeKey];
	[defaults setBool:!enabled forKey:AGPureChatModeKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:AGAgentModeChangedNotification object:[NSNumber numberWithBool:enabled]];
	[[NSNotificationCenter defaultCenter] postNotificationName:AGPureChatModeChangedNotification object:[NSNumber numberWithBool:!enabled]];
}

+ (BOOL)isPureChatModeEnabled { return ![self isAgentModeEnabled]; }
+ (void)setPureChatModeEnabled:(BOOL)enabled { [self setAgentModeEnabled:!enabled]; }

+ (BOOL)isTerminalModeEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:AGTerminalModeKey] == nil ? NO : [defaults boolForKey:AGTerminalModeKey];
}
+ (void)setTerminalModeEnabled:(BOOL)enabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:enabled forKey:AGTerminalModeKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:AGTerminalModeChangedNotification object:[NSNumber numberWithBool:enabled]];
}

+ (BOOL)isMarkdownEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:AGMarkdownModeKey] == nil ? YES : [defaults boolForKey:AGMarkdownModeKey];
}
+ (void)setMarkdownEnabled:(BOOL)enabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:enabled forKey:AGMarkdownModeKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:AGMarkdownModeChangedNotification object:[NSNumber numberWithBool:enabled]];
}

#pragma mark - Run bookkeeping

+ (NSUInteger)currentRunID { return g_currentRun; }

+ (NSUInteger)beginRun {
	@synchronized(self) { return ++g_currentRun; }
}

+ (void)cancelCurrentAgentTask {
	@synchronized(self) { g_currentRun++; }
	[self postStatus:NO forRun:NSNotFound];
}

+ (NSDictionary *)lastUsage {
	return [[NSUserDefaults standardUserDefaults] dictionaryForKey:AGLastUsageKey];
}

#pragma mark - UI notifications (always on the main thread, always tagged with the run)

+ (void)postStatus:(BOOL)isSending forRun:(NSUInteger)run {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (run != NSNotFound && run != g_currentRun) return; // a newer run owns the UI now
		NSDictionary *info = (run == NSNotFound) ? nil : [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:run] forKey:AGAPIRunUserInfoKey];
		[[NSNotificationCenter defaultCenter] postNotificationName:AGAPIStatusDidChangeNotification object:[NSNumber numberWithBool:isSending] userInfo:info];
		[UIApplication sharedApplication].networkActivityIndicatorVisible = isSending;
	});
}

+ (void)postMessage:(AGMessage *)message forRun:(NSUInteger)run {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (run != g_currentRun) return;
		[[NSNotificationCenter defaultCenter] postNotificationName:AGAPIResponseNotification object:message
			userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:run] forKey:AGAPIRunUserInfoKey]];
	});
}

+ (void)postNotice:(NSString *)text forRun:(NSUInteger)run {
	[self postMessage:[AGProviderConfig localNoticeWithText:text] forRun:run];
}

#pragma mark - Settings

+ (NSTimeInterval)doubleSetting:(NSString *)key fallback:(NSTimeInterval)fallback {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	return (value != nil && [value respondsToSelector:@selector(doubleValue)]) ? [value doubleValue] : fallback;
}

+ (NSUInteger)maxAgentSteps {
	NSInteger steps = (NSInteger)[self doubleSetting:@"agent_max_steps" fallback:40];
	return (NSUInteger)MAX(1, MIN(steps, 200));
}

/// Sleeps in short slices so Stop is honoured within ~0.2s. Returns NO if cancelled.
+ (BOOL)sleep:(NSTimeInterval)seconds run:(NSUInteger)run {
	NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate] + seconds;
	while ([NSDate timeIntervalSinceReferenceDate] < end) {
		if (run != g_currentRun) return NO;
		[NSThread sleepForTimeInterval:0.2];
	}
	return run == g_currentRun;
}

#pragma mark - Network with retry

+ (BOOL)isRetryableStatus:(NSInteger)status { return status == 429 || status == 500 || status == 502 || status == 503 || status == 504; }

+ (BOOL)isRetryableTransportCode:(NSInteger)code { return code == 6 || code == 7 || code == 28 || code == 35 || code == 52 || code == 55 || code == 56; }

/// POSTs `body`, retrying transient failures (429/5xx/timeouts) up to 3 times
/// with backoff. Without this a single "overloaded" answer ended a 20-step task.
+ (NSData *)postBody:(NSData *)body apiKey:(NSString *)apiKey run:(NSUInteger)run status:(NSInteger *)statusOut error:(NSError **)errorOut {
	NSTimeInterval timeout = [self doubleSetting:@"agent_request_timeout" fallback:120.0];
	NSData *data = nil;
	for (NSUInteger attempt = 0; attempt < 4; attempt++) {
		if (run != g_currentRun) return nil;

		NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] initWithURL:[AGProviderConfig configuredChatCompletionURL]] autorelease];
		[request setHTTPMethod:@"POST"];
		[request setHTTPBody:body];
		[request setTimeoutInterval:timeout];
		[AGProviderConfig applyAuthorizationHeadersToRequest:request withAPIKey:apiKey];

		NSHTTPURLResponse *response = nil;
		NSError *error = nil;
		data = [AGHTTPClient sendSynchronousRequest:request returningResponse:(NSURLResponse **)&response error:&error
			isCancelled:^BOOL{ return run != g_currentRun; }];
		if (run != g_currentRun) return nil;

		NSInteger status = [response statusCode];
		BOOL retry = NO;
		NSTimeInterval delay = 2.0 * (1 << attempt);
		if (data == nil) {
			retry = [self isRetryableTransportCode:[error code]];
		} else if ([self isRetryableStatus:status]) {
			retry = YES;
			NSString *retryAfter = [[response allHeaderFields] objectForKey:@"Retry-After"];
			if ([retryAfter doubleValue] > 0) delay = MIN([retryAfter doubleValue], 60.0);
		}

		if (!retry || attempt == 3) {
			if (statusOut) *statusOut = status;
			if (errorOut) *errorOut = error;
			return data;
		}
		if (![self sleep:delay run:run]) return nil;
	}
	return data;
}

#pragma mark - Response parsing

+ (void)recordUsage:(NSDictionary *)usage {
	if (![usage isKindOfClass:[NSDictionary class]]) return;
	NSDictionary *summary = [NSDictionary dictionaryWithObjectsAndKeys:
		[usage objectForKey:@"promptTokenCount"] ?: [NSNumber numberWithInt:0], @"prompt",
		[usage objectForKey:@"cachedContentTokenCount"] ?: [NSNumber numberWithInt:0], @"cached",
		[usage objectForKey:@"candidatesTokenCount"] ?: [NSNumber numberWithInt:0], @"output",
		[usage objectForKey:@"thoughtsTokenCount"] ?: [NSNumber numberWithInt:0], @"thoughts",
		nil];
	[[NSUserDefaults standardUserDefaults] setObject:summary forKey:AGLastUsageKey];
}

/// Builds the assistant message from the first candidate. Returns nil (and a
/// notice text) when there is nothing usable.
+ (AGMessage *)assistantMessageFromCandidate:(NSDictionary *)candidate notice:(NSString **)notice {
	NSArray *parts = [[candidate objectForKey:@"content"] objectForKey:@"parts"];
	NSMutableString *text = [NSMutableString string];
	NSMutableArray *toolCalls = [NSMutableArray array];

	if ([parts isKindOfClass:[NSArray class]]) {
		for (NSDictionary *part in parts) {
			if (![part isKindOfClass:[NSDictionary class]]) continue;

			id textValue = [part objectForKey:@"text"];
			BOOL isThought = [[part objectForKey:@"thought"] isKindOfClass:[NSNumber class]] && [[part objectForKey:@"thought"] boolValue];
			if ([textValue isKindOfClass:[NSString class]] && !isThought) [text appendString:textValue];

			NSDictionary *call = [part objectForKey:@"functionCall"] ?: [part objectForKey:@"function_call"];
			if (![call isKindOfClass:[NSDictionary class]]) continue;
			NSString *name = [call objectForKey:@"name"];
			if (![name isKindOfClass:[NSString class]] || [name length] == 0) continue;
			id args = [call objectForKey:@"args"] ?: [call objectForKey:@"arguments"];
			if (![args isKindOfClass:[NSDictionary class]]) args = [NSDictionary dictionary];
			NSData *argsData = [NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
			NSString *argsString = argsData ? [[[NSString alloc] initWithData:argsData encoding:NSUTF8StringEncoding] autorelease] : @"{}";

			NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
				[call objectForKey:@"id"] ?: [NSString stringWithFormat:@"call_%08x", arc4random()], @"id",
				@"function", @"type",
				[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", argsString, @"arguments", nil], @"function", nil];
			id signature = [part objectForKey:@"thoughtSignature"] ?: [part objectForKey:@"thought_signature"] ?: [call objectForKey:@"thoughtSignature"] ?: [call objectForKey:@"thought_signature"];
			if (signature != nil) [entry setObject:signature forKey:@"thoughtSignature"];
			[toolCalls addObject:entry];
		}
	}

	if ([text length] == 0 && [toolCalls count] == 0) {
		NSString *reason = [candidate objectForKey:@"finishReason"];
		if (notice) *notice = [NSString stringWithFormat:@"The model returned no content%@.", [reason length] > 0 ? [NSString stringWithFormat:@" (finish reason: %@)", reason] : @""];
		return nil;
	}

	AGMessage *message = [AGProviderConfig assistantMessageWithText:text];
	message.toolCalls = toolCalls; // no synthetic "Tool Call:" text: the UI renders calls from toolCalls
	return message;
}

#pragma mark - The agent loop

+ (void)createChatCompletionWithMessages:(NSArray *)messages {
	NSUInteger run = [self beginRun];
	[self postStatus:YES forRun:run];

	BOOL isPureChat = [self isPureChatModeEnabled];
	// Snapshot on the calling (main) thread: the UI keeps mutating its own array.
	NSArray *snapshot = [NSArray arrayWithArray:messages];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSMutableArray *history = [NSMutableArray arrayWithArray:snapshot];
		NSUInteger maxSteps = [self maxAgentSteps];
		// Loop guard state lives across iterations, i.e. across @autoreleasepool boundaries, so it must
		// be plain numbers. (It used to be an autoreleased NSString created inside the pool: the pool
		// freed it, and the next iteration messaged a dangling pointer = SIGSEGV on the 2nd tool call.)
		NSUInteger lastCallHash = 0;
		BOOL haveLastCall = NO;
		NSUInteger repeatedCalls = 0;
		BOOL finished = NO;
		static NSTimeInterval lastRequestTime = 0;

		for (NSUInteger step = 0; step < maxSteps && !finished; step++) {
			@autoreleasepool { // a long agent run must not pile up temporaries until the very end
				if (run != g_currentRun) return;

				// Politeness delay between requests (free-tier rate limits).
				NSTimeInterval minInterval = [self doubleSetting:AGRequestIntervalKey fallback:5.0];
				NSTimeInterval wait = minInterval - ([[NSDate date] timeIntervalSince1970] - lastRequestTime);
				if (minInterval > 0 && wait > 0 && wait < 60 && ![self sleep:wait run:run]) return;
				lastRequestTime = [[NSDate date] timeIntervalSince1970];

				NSString *apiKey = [AGProviderConfig currentAPIKey];
				if ([apiKey length] == 0) {
					[self postNotice:@"API key is missing. Add one under Settings > Provider Profiles." forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}

				NSArray *tools = isPureChat ? nil : [AGAgentTools toolDeclarations];
				NSDictionary *payload = [AGContextBuilder payloadForMessages:history
					pureChat:isPureChat
					systemPrompt:[AGProviderConfig configuredSystemPrompt]
					toolDeclarations:tools
					tokenBudget:[AGConversationStore contextTokenBudget]
					generationConfig:isPureChat ? nil : [AGProviderConfig generationConfigForCurrentModel]];
				NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
				if (body == nil) {
					[self postNotice:@"Failed to encode the request." forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}

				NSInteger status = 0;
				NSError *netError = nil;
				NSData *responseData = [self postBody:body apiKey:apiKey run:run status:&status error:&netError];
				if (run != g_currentRun) return;

				if (responseData == nil) {
					[self postNotice:[netError localizedDescription] ?: @"Network connection error." forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}
				if (status != 200) {
					NSString *detail = [AGProviderConfig extractErrorMessageFromResponseData:responseData fallback:@"Request failed."];
					[self postNotice:[NSString stringWithFormat:@"HTTP %ld: %@", (long)status, detail] forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}

				id parsed = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
				if (![parsed isKindOfClass:[NSDictionary class]]) {
					[self postNotice:@"The server returned an invalid response." forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}
				[self recordUsage:[parsed objectForKey:@"usageMetadata"]];

				NSArray *candidates = [parsed objectForKey:@"candidates"];
				if (![candidates isKindOfClass:[NSArray class]] || [candidates count] == 0) {
					NSString *block = [[parsed objectForKey:@"promptFeedback"] objectForKey:@"blockReason"];
					[self postNotice:[block length] > 0 ? [NSString stringWithFormat:@"The request was blocked (%@).", block] : @"The model returned no candidates." forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}

				NSString *notice = nil;
				AGMessage *assistant = [self assistantMessageFromCandidate:[candidates objectAtIndex:0] notice:&notice];
				if (assistant == nil) {
					[self postNotice:notice forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}
				[history addObject:assistant];
				[self postMessage:assistant forRun:run];

				if (isPureChat || [assistant.toolCalls count] == 0) { finished = YES; continue; }

				// Execute the tool calls in order. Anything not run before a Stop gets a
				// "Cancelled" filler from AGContextBuilder, so history stays valid.
				for (NSDictionary *call in assistant.toolCalls) {
					if (run != g_currentRun) return;
					NSDictionary *fn = [call objectForKey:@"function"];
					NSString *name = [fn objectForKey:@"name"];
					NSString *argsJSON = [fn objectForKey:@"arguments"];
					id args = [argsJSON isKindOfClass:[NSString class]] ? [NSJSONSerialization JSONObjectWithData:[argsJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;

					NSString *output = [AGAgentTools executeToolNamed:name arguments:args workspace:[AGGuardrails workspaceDirectory]
						isCancelled:^BOOL{ return run != g_currentRun; }];
					if (run != g_currentRun) return;

					AGMessage *toolMessage = [AGMessage messageWithRole:@"tool" content:output ?: @""];
					toolMessage.author = @"Tool Output";
					toolMessage.toolCallID = [call objectForKey:@"id"];
					toolMessage.toolName = name;
					[history addObject:toolMessage];
					[self postMessage:toolMessage forRun:run];

					// Loop guard: the same call with the same result three times in a row is a stuck model.
					NSUInteger callHash = [[NSString stringWithFormat:@"%@|%@", name, argsJSON] hash] ^ ([output hash] * 31u);
					repeatedCalls = (haveLastCall && callHash == lastCallHash) ? repeatedCalls + 1 : 1;
					lastCallHash = callHash;
					haveLastCall = YES;
				}
				if (repeatedCalls >= 3) {
					[self postNotice:@"Stopped: the model repeated the same tool call with the same result three times. Send a message to give it new direction." forRun:run];
					[self postStatus:NO forRun:run];
					return;
				}
			}
		}

		if (!finished) {
			[self postNotice:[NSString stringWithFormat:@"Stopped after %lu steps (limit in Settings > Agent). Send a message to continue.", (unsigned long)maxSteps] forRun:run];
		}
		[self postStatus:NO forRun:run];
	});
}

@end
