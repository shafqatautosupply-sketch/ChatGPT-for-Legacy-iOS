#import "AGConversationStore.h"
#import "AGConversation.h"
#import "AGMessage.h"

static NSString * const AGSavedMessageLimitKey = @"lc_saved_message_limit";
static NSString * const AGLoadedMessageLimitKey = @"lc_loaded_message_limit";
static NSString * const AGTokenSaverKey = @"lc_auto_compression_enabled"; // key kept: same switch, new meaning
static NSString * const AGContextBudgetKey = @"ag_context_budget";
static const NSInteger AGDefaultContextBudget = 24000;
static NSString * const AGIndexFileName = @"index.plist";

static dispatch_queue_t AGStoreQueue(void) {
	static dispatch_queue_t queue = NULL; static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.creative.agentic.store", DISPATCH_QUEUE_SERIAL); });
	return queue;
}

// Pending async saves, keyed by conversation id; only touched on the store queue
// (and under the lock when enqueuing).
static NSMutableDictionary *AGPendingSaves(void) {
	static NSMutableDictionary *pending = nil; static dispatch_once_t once;
	dispatch_once(&once, ^{ pending = [[NSMutableDictionary alloc] init]; });
	return pending;
}

@interface AGConversationStore ()
+ (void)performSaveMessages:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title;
@end

@implementation AGConversationStore

#pragma mark - Settings

+ (NSInteger)savedMessageLimit {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return ([defaults objectForKey:AGSavedMessageLimitKey] == nil) ? 0 : [defaults integerForKey:AGSavedMessageLimitKey];
}
+ (void)setSavedMessageLimit:(NSInteger)limit {
	[[NSUserDefaults standardUserDefaults] setInteger:limit forKey:AGSavedMessageLimitKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}
+ (NSInteger)loadedMessageLimit {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return ([defaults objectForKey:AGLoadedMessageLimitKey] == nil) ? 30 : [defaults integerForKey:AGLoadedMessageLimitKey];
}
+ (void)setLoadedMessageLimit:(NSInteger)limit {
	[[NSUserDefaults standardUserDefaults] setInteger:limit forKey:AGLoadedMessageLimitKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)isTokenSaverEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return ([defaults objectForKey:AGTokenSaverKey] == nil) ? YES : [defaults boolForKey:AGTokenSaverKey];
}
+ (void)setTokenSaverEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:AGTokenSaverKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}
+ (NSInteger)configuredContextTokenBudget {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return ([defaults objectForKey:AGContextBudgetKey] == nil) ? AGDefaultContextBudget : [defaults integerForKey:AGContextBudgetKey];
}
+ (void)setConfiguredContextTokenBudget:(NSInteger)budget {
	[[NSUserDefaults standardUserDefaults] setInteger:MAX(0, budget) forKey:AGContextBudgetKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}
+ (NSUInteger)contextTokenBudget {
	if (![self isTokenSaverEnabled]) return 0;
	NSInteger budget = [self configuredContextTokenBudget];
	return (budget < 4000) ? (budget <= 0 ? 0 : 4000) : (NSUInteger)budget;
}

#pragma mark - Paths and identifiers

+ (NSDateFormatter *)dateFormatter {
	static NSDateFormatter *formatter = nil; static dispatch_once_t once;
	dispatch_once(&once, ^{ formatter = [[NSDateFormatter alloc] init]; [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"]; });
	return formatter;
}

+ (NSString *)conversationsDirectory {
	NSString *library = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *path = [library stringByAppendingPathComponent:@"LegacyChatApp/Conversations"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
	}
	return path;
}

+ (NSString *)pathForConversationIdentifier:(NSString *)identifier {
	return [[self conversationsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", identifier]];
}

+ (NSString *)indexPath { return [[self conversationsDirectory] stringByAppendingPathComponent:AGIndexFileName]; }

+ (NSString *)nextConversationIdentifier {
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	NSString *string = (NSString *)CFUUIDCreateString(NULL, uuid);
	CFRelease(uuid);
	return [string autorelease];
}

+ (NSString *)currentConversationIdentifier {
	return [[NSUserDefaults standardUserDefaults] objectForKey:@"currentConversationIdentifier"];
}

+ (void)setCurrentConversationIdentifier:(NSString *)identifier {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([identifier length] > 0) [defaults setObject:identifier forKey:@"currentConversationIdentifier"];
	else [defaults removeObjectForKey:@"currentConversationIdentifier"];
	[defaults synchronize];
}

#pragma mark - (De)serialisation

+ (BOOL)messageShouldBePersisted:(AGMessage *)message {
	if (![message isKindOfClass:[AGMessage class]]) return NO;
	NSString *role = message.role;
	if (![role isEqualToString:@"user"] && ![role isEqualToString:@"assistant"] && ![role isEqualToString:@"tool"] && ![role isEqualToString:@"system"]) return NO;
	return [[message.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0 || [message.toolCalls count] > 0;
}

+ (BOOL)hasMeaningfulMessages:(NSArray *)messages {
	for (AGMessage *message in messages) {
		if ([message isKindOfClass:[AGMessage class]] && !message.localOnly && ([message.role isEqualToString:@"user"] || [message.role isEqualToString:@"assistant"])) return YES;
	}
	return NO;
}

+ (NSString *)derivedTitleForMessages:(NSArray *)messages fallback:(NSString *)fallback {
	for (AGMessage *message in messages) {
		if ([message isKindOfClass:[AGMessage class]] && [message.role isEqualToString:@"user"] && [message.content length] > 0) {
			NSString *title = [message.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([title length] > 28) title = [[title substringToIndex:28] stringByAppendingString:@"…"];
			return title;
		}
	}
	return fallback;
}

+ (NSDictionary *)dictionaryForMessage:(AGMessage *)message {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	[d setObject:([message.role length] > 0 ? message.role : @"assistant") forKey:@"role"];
	[d setObject:(message.content ?: @"") forKey:@"content"];
	if ([message.toolCallID length] > 0) [d setObject:message.toolCallID forKey:@"tool_call_id"];
	if ([message.toolCalls count] > 0) [d setObject:message.toolCalls forKey:@"tool_calls"];
	if ([message.toolName length] > 0) [d setObject:message.toolName forKey:@"tool_name"];
	if ([message.author length] > 0 && [message.role isEqualToString:@"assistant"]) [d setObject:message.author forKey:@"name"];
	if (message.localOnly) [d setObject:[NSNumber numberWithBool:YES] forKey:@"local_only"];
	if (message.compacted) [d setObject:[NSNumber numberWithBool:YES] forKey:@"compacted"];
	if (message.omitted) [d setObject:[NSNumber numberWithBool:YES] forKey:@"omitted"];
	return d;
}

+ (AGMessage *)messageFromDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	AGMessage *message = [[[AGMessage alloc] init] autorelease];
	message.role = [dictionary objectForKey:@"role"] ?: @"assistant";
	message.content = [dictionary objectForKey:@"content"] ?: [dictionary objectForKey:@"message"] ?: @"";
	message.author = [dictionary objectForKey:@"name"] ?: ([message.role isEqualToString:@"tool"] ? @"Tool Output" : @"AI Assistant");

	NSString *toolCallID = [dictionary objectForKey:@"tool_call_id"] ?: [dictionary objectForKey:@"toolCallID"];
	if ([toolCallID length] > 0) message.toolCallID = toolCallID;
	NSArray *toolCalls = [dictionary objectForKey:@"tool_calls"] ?: [dictionary objectForKey:@"toolCalls"];
	if ([toolCalls isKindOfClass:[NSArray class]]) message.toolCalls = toolCalls;
	NSString *toolName = [dictionary objectForKey:@"tool_name"] ?: [dictionary objectForKey:@"toolName"];
	if ([toolName length] > 0) message.toolName = toolName;

	message.localOnly = [[dictionary objectForKey:@"local_only"] boolValue];
	message.compacted = [[dictionary objectForKey:@"compacted"] boolValue];
	message.omitted = [[dictionary objectForKey:@"omitted"] boolValue];
	return message;
}

#pragma mark - Loading

+ (NSDictionary *)readJSONFileAtPath:(NSString *)path {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (data == nil) return nil;
	id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	return [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
}

+ (AGConversation *)conversationWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) return nil;
	NSDictionary *dictionary = [self readJSONFileAtPath:[self pathForConversationIdentifier:identifier]];
	if (dictionary == nil) return nil;

	AGConversation *conversation = [[[AGConversation alloc] init] autorelease];
	conversation.uuid = [dictionary objectForKey:@"conversationID"];
	conversation.title = [dictionary objectForKey:@"title"];
	conversation.creationDate = [dictionary objectForKey:@"createdAt"];
	conversation.lastTimeEdited = [dictionary objectForKey:@"updatedAt"];
	conversation.messages = [NSMutableArray array];
	NSArray *messages = [dictionary objectForKey:@"messages"];
	// ALL messages are loaded so saving never drops older ones; the chat screen limits what it displays.
	for (NSDictionary *item in messages) {
		AGMessage *message = [self messageFromDictionary:item];
		if (message != nil) [conversation.messages addObject:message];
	}
	conversation.messageCount = (int)[messages count];
	return conversation;
}

+ (AGConversation *)summaryFromIndexEntry:(NSDictionary *)entry uuid:(NSString *)uuid {
	AGConversation *conversation = [[[AGConversation alloc] init] autorelease];
	conversation.uuid = uuid;
	conversation.title = [entry objectForKey:@"title"];
	conversation.creationDate = [entry objectForKey:@"createdAt"];
	conversation.lastTimeEdited = [entry objectForKey:@"updatedAt"];
	conversation.messageCount = [[entry objectForKey:@"count"] intValue];
	conversation.messages = [NSMutableArray array];
	return conversation;
}

+ (NSArray *)conversationFileIdentifiers {
	NSMutableArray *ids = [NSMutableArray array];
	for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self conversationsDirectory] error:nil]) {
		if ([name hasSuffix:@".json"]) [ids addObject:[name stringByDeletingPathExtension]];
	}
	return ids;
}

/// Must run on the store queue.
+ (NSMutableDictionary *)loadOrRebuildIndex {
	NSMutableDictionary *index = [NSMutableDictionary dictionaryWithContentsOfFile:[self indexPath]];
	NSArray *onDisk = [self conversationFileIdentifiers];
	BOOL consistent = (index != nil && [index count] == [onDisk count]);
	if (consistent) { for (NSString *identifier in onDisk) if ([index objectForKey:identifier] == nil) { consistent = NO; break; } }
	if (consistent) return index;

	index = [NSMutableDictionary dictionary]; // first run after upgrade, or files added/removed outside the app
	for (NSString *identifier in onDisk) {
		NSDictionary *dictionary = [self readJSONFileAtPath:[self pathForConversationIdentifier:identifier]];
		if (dictionary == nil) continue;
		[index setObject:[NSDictionary dictionaryWithObjectsAndKeys:
			[dictionary objectForKey:@"title"] ?: @"New Chat", @"title",
			[dictionary objectForKey:@"createdAt"] ?: @"", @"createdAt",
			[dictionary objectForKey:@"updatedAt"] ?: @"", @"updatedAt",
			[NSNumber numberWithInt:(int)[[dictionary objectForKey:@"messages"] count]], @"count", nil] forKey:identifier];
	}
	[index writeToFile:[self indexPath] atomically:YES];
	return index;
}

+ (NSArray *)loadConversations {
	__block NSArray *result = nil;
	dispatch_sync(AGStoreQueue(), ^{
		NSDictionary *index = [self loadOrRebuildIndex];
		NSMutableArray *list = [NSMutableArray array];
		for (NSString *identifier in index) [list addObject:[self summaryFromIndexEntry:[index objectForKey:identifier] uuid:identifier]];
		[list sortUsingComparator:^NSComparisonResult(AGConversation *a, AGConversation *b) {
			// "yyyy-MM-dd HH:mm:ss" sorts correctly as plain text, newest first.
			return [b.lastTimeEdited ?: @"" compare:a.lastTimeEdited ?: @""];
		}];
		result = [list retain];
	});
	return [result autorelease];
}

+ (NSArray *)allConversations { return [self loadConversations]; }

#pragma mark - Saving

+ (void)performSaveMessages:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title {
	if ([conversationID length] == 0) return;
	if (![self hasMeaningfulMessages:messages]) { [self deleteConversationWithIdentifier:conversationID]; return; }

	NSArray *toSave = messages;
	NSInteger limit = [self savedMessageLimit];
	if (limit > 0 && (NSInteger)[messages count] > limit) toSave = [messages subarrayWithRange:NSMakeRange([messages count] - (NSUInteger)limit, (NSUInteger)limit)];

	NSMutableArray *serialized = [NSMutableArray array];
	for (AGMessage *message in toSave) {
		if ([self messageShouldBePersisted:message]) [serialized addObject:[self dictionaryForMessage:message]];
	}

	NSString *now = [[self dateFormatter] stringFromDate:[NSDate date]];
	NSString *path = [self pathForConversationIdentifier:conversationID];
	// (The old code read this JSON file with dictionaryWithContentsOfFile:, which only
	// understands plists, so "createdAt" was reset to "now" on every save.)
	NSDictionary *existing = [self readJSONFileAtPath:path];
	NSString *createdAt = [existing objectForKey:@"createdAt"];
	if ([createdAt length] == 0) createdAt = now;

	NSString *resolvedTitle = [self derivedTitleForMessages:messages fallback:title] ?: @"New Chat";
	NSDictionary *conversation = [NSDictionary dictionaryWithObjectsAndKeys:
		conversationID, @"conversationID", resolvedTitle, @"title", createdAt, @"createdAt", now, @"updatedAt", serialized, @"messages", nil];
	NSData *json = [NSJSONSerialization dataWithJSONObject:conversation options:0 error:nil];
	if (json == nil || ![json writeToFile:path atomically:YES]) return;

	NSMutableDictionary *index = [self loadOrRebuildIndex];
	[index setObject:[NSDictionary dictionaryWithObjectsAndKeys:resolvedTitle, @"title", createdAt, @"createdAt", now, @"updatedAt",
		[NSNumber numberWithInt:(int)[serialized count]], @"count", nil] forKey:conversationID];
	[index writeToFile:[self indexPath] atomically:YES];
	[self setCurrentConversationIdentifier:conversationID];
}

+ (void)saveMessages:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title {
	NSArray *snapshot = [[messages copy] autorelease];
	dispatch_sync(AGStoreQueue(), ^{ [self performSaveMessages:snapshot conversationID:conversationID title:title]; });
}

+ (void)saveMessagesAsync:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title {
	if ([conversationID length] == 0) return;
	NSArray *snapshot = [[messages copy] autorelease];
	NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:snapshot, @"messages", title ?: [NSNull null], @"title", nil];
	@synchronized(AGPendingSaves()) { [AGPendingSaves() setObject:job forKey:conversationID]; }
	dispatch_async(AGStoreQueue(), ^{
		NSDictionary *latest = nil;
		@synchronized(AGPendingSaves()) { latest = [[[AGPendingSaves() objectForKey:conversationID] retain] autorelease]; [AGPendingSaves() removeObjectForKey:conversationID]; }
		if (latest == nil) return; // an earlier queued task already saved the newest snapshot
		id savedTitle = [latest objectForKey:@"title"];
		[self performSaveMessages:[latest objectForKey:@"messages"] conversationID:conversationID title:[savedTitle isKindOfClass:[NSString class]] ? savedTitle : nil];
	});
}

+ (BOOL)deleteConversationWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) return NO;
	NSString *path = [self pathForConversationIdentifier:identifier];
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	// The queue may already be the caller (performSave -> delete), so touch the index directly.
	NSMutableDictionary *index = [NSMutableDictionary dictionaryWithContentsOfFile:[self indexPath]];
	if ([index objectForKey:identifier] != nil) { [index removeObjectForKey:identifier]; [index writeToFile:[self indexPath] atomically:YES]; }
	if ([identifier isEqualToString:[self currentConversationIdentifier]]) [self setCurrentConversationIdentifier:nil];
	return YES;
}

@end
