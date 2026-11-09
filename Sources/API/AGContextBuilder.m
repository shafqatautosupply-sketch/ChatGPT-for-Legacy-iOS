#import "AGContextBuilder.h"
#import "AGMessage.h"

static NSString * const AGSyntheticToolPrefix = @"Tool Call: ";

@implementation AGContextBuilder

#pragma mark - Estimation

+ (NSUInteger)estimateTokensForText:(NSString *)text {
	// ~3.5 characters per token is a good average for mixed prose and code.
	return ([text length] * 2 + 6) / 7;
}

#pragma mark - Helpers

/// Text of a message as the model should see it ("" for call-only/synthetic).
static NSString *AGVisibleText(AGMessage *m) {
	NSString *text = [m.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([m.toolCalls count] > 0 && [text hasPrefix:AGSyntheticToolPrefix]) return @""; // legacy display text
	return text ?: @"";
}

static BOOL AGIsUserText(AGMessage *m) {
	return [m.role isEqualToString:@"user"];
}

static NSDictionary *AGFunctionOf(NSDictionary *toolCall) {
	NSDictionary *fn = [toolCall isKindOfClass:[NSDictionary class]] ? [toolCall objectForKey:@"function"] : nil;
	return [fn isKindOfClass:[NSDictionary class]] ? fn : nil;
}

static NSDictionary *AGParsedArgs(NSDictionary *fn) {
	NSString *json = [fn objectForKey:@"arguments"];
	if (![json isKindOfClass:[NSString class]]) return [NSDictionary dictionary];
	id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
	return [parsed isKindOfClass:[NSDictionary class]] ? parsed : [NSDictionary dictionary];
}

/// Replaces bulky string args (file contents, edit text) with a stub. The files
/// are on disk and readable again, so nothing the model needs is lost.
static NSDictionary *AGShrunkArgs(NSDictionary *args) {
	NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:args];
	for (NSString *key in [NSArray arrayWithObjects:@"content", @"old_text", @"new_text", nil]) {
		NSString *value = [out objectForKey:key];
		if ([value isKindOfClass:[NSString class]] && [value length] > 240) {
			[out setObject:[NSString stringWithFormat:@"[%lu chars omitted to save tokens]", (unsigned long)[value length]] forKey:key];
		}
	}
	return out;
}

static NSString *AGShrunkToolOutput(NSString *text) {
	if ([text length] <= 420) return text;
	NSString *head = [text substringToIndex:260];
	NSString *tail = [text substringFromIndex:[text length] - 120];
	return [NSString stringWithFormat:@"%@\n[... %lu chars of old tool output omitted to save tokens; re-run the command or readFile if you need it ...]\n%@",
		head, (unsigned long)([text length] - 380), tail];
}

static NSString *AGToolOutputForModel(AGMessage *m) {
	NSString *text = [m.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return m.compacted ? AGShrunkToolOutput(text) : text;
}

#pragma mark - Step 1: repair

/// Returns a structurally valid message list. Never mutates the inputs; missing
/// tool responses are filled with transient synthetic messages.
+ (NSArray *)repairedMessages:(NSArray *)messages pureChat:(BOOL)pureChat systemTexts:(NSMutableArray *)systemTexts {
	NSMutableArray *out = [NSMutableArray array];
	NSUInteger count = [messages count];
	NSUInteger i = 0;
	while (i < count) {
		id raw = [messages objectAtIndex:i];
		i++;
		if (![raw isKindOfClass:[AGMessage class]]) continue;
		AGMessage *m = raw;
		if (m.localOnly) continue;

		if ([m.role isEqualToString:@"system"]) {
			if ([m.content length] > 0) [systemTexts addObject:m.content];
			continue;
		}
		if ([m.role isEqualToString:@"tool"]) continue; // orphan: valid ones are consumed with their call below

		NSMutableArray *validCalls = [NSMutableArray array];
		for (id call in m.toolCalls) {
			NSString *name = [AGFunctionOf(call) objectForKey:@"name"];
			if ([name isKindOfClass:[NSString class]] && [name length] > 0) [validCalls addObject:call];
		}

		if ([m.role isEqualToString:@"assistant"] && [validCalls count] > 0) {
			// Collect the responses that follow this call.
			NSMutableArray *responses = [NSMutableArray array];
			while (i < count) {
				id next = [messages objectAtIndex:i];
				if (![next isKindOfClass:[AGMessage class]]) { i++; continue; }
				AGMessage *nm = next;
				if (nm.localOnly) { i++; continue; }
				if (![nm.role isEqualToString:@"tool"]) break;
				[responses addObject:nm];
				i++;
			}
			if (pureChat) {
				// Tool exchanges cannot be replayed without tools; keep only prose.
				if ([AGVisibleText(m) length] > 0) [out addObject:m];
				continue;
			}
			if (m.omitted) { [out addObject:m]; for (AGMessage *r in responses) [out addObject:r]; continue; }
			[out addObject:m];
			for (NSUInteger k = 0; k < [validCalls count]; k++) {
				if (k < [responses count]) {
					[out addObject:[responses objectAtIndex:k]];
				} else {
					AGMessage *filler = [AGMessage messageWithRole:@"tool" content:@"Cancelled: this tool call was not executed."];
					filler.toolName = [AGFunctionOf([validCalls objectAtIndex:k]) objectForKey:@"name"];
					filler.omitted = m.omitted;
					[out addObject:filler];
				}
			}
			continue;
		}

		if ([AGVisibleText(m) length] == 0) continue;
		[out addObject:m];
	}
	return out;
}

#pragma mark - Step 2: size accounting

+ (NSUInteger)tokensForMessage:(AGMessage *)m {
	if ([m.role isEqualToString:@"tool"]) return [self estimateTokensForText:AGToolOutputForModel(m)] + 8;
	NSUInteger total = [self estimateTokensForText:AGVisibleText(m)] + 4;
	for (NSDictionary *call in m.toolCalls) {
		NSDictionary *fn = AGFunctionOf(call);
		NSDictionary *args = AGParsedArgs(fn);
		if (m.compacted) args = AGShrunkArgs(args);
		NSData *json = [NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
		NSString *text = json ? [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease] : @"";
		total += [self estimateTokensForText:text] + 12;
	}
	return total;
}

+ (NSUInteger)totalTokensOf:(NSArray *)list {
	NSUInteger total = 0;
	for (AGMessage *m in list) if (!m.omitted) total += [self tokensForMessage:m];
	return total;
}

#pragma mark - Step 3: compaction (persistent, stepwise)

+ (BOOL)isBulky:(AGMessage *)m {
	if (m.compacted) return NO;
	if ([m.role isEqualToString:@"tool"]) return [m.content length] > 420;
	for (NSDictionary *call in m.toolCalls) {
		NSDictionary *args = AGParsedArgs(AGFunctionOf(call));
		for (NSString *key in [NSArray arrayWithObjects:@"content", @"old_text", @"new_text", nil]) {
			if ([[args objectForKey:key] isKindOfClass:[NSString class]] && [[args objectForKey:key] length] > 240) return YES;
		}
	}
	return NO;
}

+ (void)enforceBudget:(NSUInteger)budget overhead:(NSUInteger)overhead on:(NSArray *)list {
	if (budget == 0) return;
	NSUInteger total = overhead + [self totalTokensOf:list];
	if (total <= budget) return; // between steps nothing changes: cache-friendly

	NSUInteger target = (NSUInteger)(budget * 0.6);
	NSUInteger count = [list count];
	NSUInteger keepRecent = 6;
	NSUInteger limit = (count > keepRecent) ? count - keepRecent : 0;

	// Phase 1: shrink old bulky payloads, oldest first.
	for (NSUInteger i = 0; i < limit && total > target; i++) {
		AGMessage *m = [list objectAtIndex:i];
		if (m.omitted || ![self isBulky:m]) continue;
		NSUInteger before = [self tokensForMessage:m];
		m.compacted = YES;
		NSUInteger after = [self tokensForMessage:m];
		total -= MIN(total, before - MIN(before, after));
	}
	if (total <= target) return;

	// Phase 2: drop whole old turns (never the first user message, never the current turn).
	NSMutableArray *userIndexes = [NSMutableArray array];
	for (NSUInteger i = 0; i < count; i++) {
		AGMessage *m = [list objectAtIndex:i];
		if (AGIsUserText(m) && !m.omitted) [userIndexes addObject:[NSNumber numberWithUnsignedInteger:i]];
	}
	if ([userIndexes count] < 2) return;

	NSUInteger lastTurnStart = [[userIndexes lastObject] unsignedIntegerValue];
	NSUInteger blockStart = [[userIndexes objectAtIndex:0] unsignedIntegerValue] + 1; // keep the pinned task message
	for (NSUInteger u = 1; u < [userIndexes count] && total > target; u++) {
		NSUInteger blockEnd = [[userIndexes objectAtIndex:u] unsignedIntegerValue]; // exclusive
		if (blockEnd > lastTurnStart) break;
		// Omit [blockStart, blockEnd) and, after the first block, the user message that opened it.
		NSUInteger from = (u == 1) ? blockStart : [[userIndexes objectAtIndex:u - 1] unsignedIntegerValue];
		for (NSUInteger i = from; i < blockEnd; i++) {
			AGMessage *m = [list objectAtIndex:i];
			if (m.omitted) continue;
			total -= MIN(total, [self tokensForMessage:m]);
			m.omitted = YES;
		}
	}
}

#pragma mark - Step 4: payload

+ (NSDictionary *)functionCallPartFor:(NSDictionary *)call compacted:(BOOL)compacted {
	NSDictionary *fn = AGFunctionOf(call);
	NSDictionary *args = AGParsedArgs(fn);
	if (compacted) args = AGShrunkArgs(args);
	NSMutableDictionary *fc = [NSMutableDictionary dictionaryWithObjectsAndKeys:[fn objectForKey:@"name"], @"name", args, @"args", nil];
	NSMutableDictionary *part = [NSMutableDictionary dictionaryWithObject:fc forKey:@"functionCall"];
	id signature = [call objectForKey:@"thoughtSignature"] ?: [call objectForKey:@"thought_signature"] ?: [call objectForKey:@"extra_content"];
	if (signature != nil) [part setObject:signature forKey:@"thoughtSignature"];
	return part;
}

+ (NSDictionary *)payloadForMessages:(NSArray *)messages
                            pureChat:(BOOL)pureChat
                        systemPrompt:(NSString *)systemPrompt
                      toolDeclarations:(NSArray *)toolDeclarations
                         tokenBudget:(NSUInteger)tokenBudget
                    generationConfig:(NSDictionary *)generationConfig {

	NSMutableArray *systemTexts = [NSMutableArray array];
	if ([systemPrompt length] > 0) [systemTexts addObject:systemPrompt];
	NSArray *clean = [self repairedMessages:messages pureChat:pureChat systemTexts:systemTexts];

	NSString *systemJoined = [systemTexts componentsJoinedByString:@"\n\n"];
	NSUInteger overhead = [self estimateTokensForText:systemJoined];
	if (!pureChat && [toolDeclarations count] > 0) {
		NSData *toolJSON = [NSJSONSerialization dataWithJSONObject:toolDeclarations options:0 error:nil];
		overhead += [toolJSON length] / 4;
	}
	[self enforceBudget:tokenBudget overhead:overhead on:clean];

	NSUInteger omittedCount = 0;
	for (AGMessage *m in clean) if (m.omitted) omittedCount++;

	NSMutableArray *contents = [NSMutableArray array];
	NSMutableArray *pendingResponses = [NSMutableArray array];
	BOOL noteInserted = NO;

	for (AGMessage *m in clean) {
		if (m.omitted) continue;

		if ([m.role isEqualToString:@"tool"]) {
			NSDictionary *response = [NSDictionary dictionaryWithObject:AGToolOutputForModel(m) forKey:@"output"];
			NSDictionary *fr = [NSDictionary dictionaryWithObjectsAndKeys:(m.toolName ?: @"tool"), @"name", response, @"response", nil];
			[pendingResponses addObject:[NSDictionary dictionaryWithObject:fr forKey:@"functionResponse"]];
			continue;
		}
		if ([pendingResponses count] > 0) {
			[contents addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", [NSArray arrayWithArray:pendingResponses], @"parts", nil]];
			[pendingResponses removeAllObjects];
		}

		NSMutableArray *parts = [NSMutableArray array];
		NSString *text = AGVisibleText(m);
		BOOL isModel = [m.role isEqualToString:@"assistant"];

		if ([text length] > 0) [parts addObject:[NSDictionary dictionaryWithObject:text forKey:@"text"]];
		if (isModel && !pureChat) {
			for (NSDictionary *call in m.toolCalls) {
				if ([[AGFunctionOf(call) objectForKey:@"name"] length] == 0) continue;
				[parts addObject:[self functionCallPartFor:call compacted:m.compacted]];
			}
		}
		if (!isModel && !noteInserted && omittedCount > 0) {
			[parts addObject:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:
				@"[Note: %lu earlier messages were left out of this context to save tokens. Re-read files or re-run commands if you need earlier details.]",
				(unsigned long)omittedCount] forKey:@"text"]];
			noteInserted = YES;
		}
		if ([parts count] == 0) continue;
		[contents addObject:[NSDictionary dictionaryWithObjectsAndKeys:(isModel ? @"model" : @"user"), @"role", parts, @"parts", nil]];
	}
	if ([pendingResponses count] > 0) {
		[contents addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", [NSArray arrayWithArray:pendingResponses], @"parts", nil]];
	}

	// The API requires the conversation to open with a user turn.
	if ([contents count] > 0 && ![[[contents objectAtIndex:0] objectForKey:@"role"] isEqualToString:@"user"]) {
		NSDictionary *opener = [NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role",
			[NSArray arrayWithObject:[NSDictionary dictionaryWithObject:@"[Conversation continues]" forKey:@"text"]], @"parts", nil];
		[contents insertObject:opener atIndex:0];
	}

	NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:contents forKey:@"contents"];
	if ([systemJoined length] > 0) {
		[payload setObject:[NSDictionary dictionaryWithObject:[NSArray arrayWithObject:[NSDictionary dictionaryWithObject:systemJoined forKey:@"text"]] forKey:@"parts"]
					forKey:@"system_instruction"];
	}
	if (!pureChat && [toolDeclarations count] > 0) [payload setObject:toolDeclarations forKey:@"tools"];
	if ([generationConfig count] > 0) [payload setObject:generationConfig forKey:@"generationConfig"];
	return payload;
}

@end
