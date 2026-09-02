#import "LCConversationStore.h"
#import "CGConversation.h"
#import "CGAPIHelper.h"
#import "CGMessage.h"
#import "NSURLConnection+FoundationCompletions.h"

@interface LCConversationStore ()

+ (NSDate *)dateFromString:(NSString *)value;

@end

static NSString * const LCSavedMessageLimitKey = @"lc_saved_message_limit";
static NSString * const LCLoadedMessageLimitKey = @"lc_loaded_message_limit";
static NSString * const LCAutoCompressionKey = @"lc_auto_compression_enabled";

static NSInteger LCConversationSort(id leftValue, id rightValue, void *context) {
	CGConversation *left = (CGConversation *)leftValue;
	CGConversation *right = (CGConversation *)rightValue;
	return [[LCConversationStore dateFromString:right.lastTimeEdited] compare:[LCConversationStore dateFromString:left.lastTimeEdited]];
}

@implementation LCConversationStore

+ (NSInteger)savedMessageLimit {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:LCSavedMessageLimitKey] == nil) {
		return 0; // Default to 0 (unlimited) so history is never truncated or deleted by default
	}
	return [defaults integerForKey:LCSavedMessageLimitKey];
}

+ (void)setSavedMessageLimit:(NSInteger)limit {
	[[NSUserDefaults standardUserDefaults] setInteger:limit forKey:LCSavedMessageLimitKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSInteger)loadedMessageLimit {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:LCLoadedMessageLimitKey] == nil) {
		return 30; // Default
	}
	return [defaults integerForKey:LCLoadedMessageLimitKey];
}

+ (void)setLoadedMessageLimit:(NSInteger)limit {
	[[NSUserDefaults standardUserDefaults] setInteger:limit forKey:LCLoadedMessageLimitKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)isAutoCompressionEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:LCAutoCompressionKey] == nil) {
		return NO; // Default off
	}
	return [defaults boolForKey:LCAutoCompressionKey];
}

+ (void)setAutoCompressionEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:LCAutoCompressionKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSDateFormatter *)sharedDateFormatter {
	static NSDateFormatter *sharedFormatter = nil;
	if (sharedFormatter == nil) {
		sharedFormatter = [[NSDateFormatter alloc] init];
		[sharedFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	}
	return sharedFormatter;
}

+ (NSString *)conversationsDirectory {
	NSString *libraryDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *directoryPath = [libraryDirectory stringByAppendingPathComponent:@"LegacyChatApp/Conversations"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:directoryPath]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
	}
	return directoryPath;
}

+ (NSString *)pathForConversationIdentifier:(NSString *)identifier {
	return [[self conversationsDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", identifier]];
}

+ (NSString *)stringFromDate:(NSDate *)date {
	if (date == nil) {
		return @"";
	}
	return [[self sharedDateFormatter] stringFromDate:date];
}

+ (NSDate *)dateFromString:(NSString *)value {
	if ([value length] == 0) {
		return [NSDate dateWithTimeIntervalSince1970:0];
	}

	NSDate *date = [[self sharedDateFormatter] dateFromString:value];
	return date ?: [NSDate dateWithTimeIntervalSince1970:0];
}

+ (NSString *)nextConversationIdentifier {
	CFUUIDRef uuidRef = CFUUIDCreate(NULL);
	NSString *uuidString = (NSString *)CFUUIDCreateString(NULL, uuidRef);
	CFRelease(uuidRef);
	return [uuidString autorelease];
}

+ (NSString *)currentConversationIdentifier {
	return [[NSUserDefaults standardUserDefaults] objectForKey:@"currentConversationIdentifier"];
}

+ (void)setCurrentConversationIdentifier:(NSString *)identifier {
	if ([identifier length] > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:identifier forKey:@"currentConversationIdentifier"];
	} else {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"currentConversationIdentifier"];
	}
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)messageShouldBePersisted:(CGMessage *)message {
	if (![message isKindOfClass:[CGMessage class]]) {
		return NO;
	}
	if (![message.role isEqualToString:@"user"] &&
		![message.role isEqualToString:@"assistant"] &&
		![message.role isEqualToString:@"system"] &&
		![message.role isEqualToString:@"tool"] &&
		![message.role isEqualToString:@"local"]) {
		return NO;
	}
	return ([message.content length] > 0);
}

+ (BOOL)hasMeaningfulMessages:(NSArray *)messages {
	for (CGMessage *message in messages) {
		if ([message.role isEqualToString:@"user"] || [message.role isEqualToString:@"assistant"]) {
			return YES;
		}
	}
	return NO;
}

+ (NSString *)derivedTitleForMessages:(NSArray *)messages fallback:(NSString *)fallback {
	for (CGMessage *message in messages) {
		if ([message.role isEqualToString:@"user"] && [message.content length] > 0) {
			NSString *title = [message.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([title length] > 28) {
				title = [[title substringToIndex:28] stringByAppendingString:@"…"];
			}
			return title;
		}
	}
	return fallback;
}

+ (NSDictionary *)dictionaryForMessage:(CGMessage *)message {
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	if ([message.role length] > 0) {
		[dictionary setObject:message.role forKey:@"role"];
	} else {
		[dictionary setObject:@"assistant" forKey:@"role"];
	}
	[dictionary setObject:(message.content ?: @"") forKey:@"content"];

	NSString *toolCallID = message.toolCallID;
	if ([toolCallID length] > 0) {
		[dictionary setObject:toolCallID forKey:@"tool_call_id"];
	}

	NSArray *tc = [message.toolCalls isKindOfClass:[NSArray class]] ? message.toolCalls : nil;
	if ([tc count] > 0) {
		[dictionary setObject:tc forKey:@"tool_calls"];
	}

	NSString *toolName = message.toolName;
	if ([toolName length] > 0) {
		[dictionary setObject:toolName forKey:@"tool_name"];
	}

	return dictionary;
}

+ (CGMessage *)messageFromDictionary:(NSDictionary *)dictionary {
	CGMessage *message = [[[CGMessage alloc] init] autorelease];
	message.role = [dictionary objectForKey:@"role"] ?: @"assistant";
	message.content = [dictionary objectForKey:@"content"] ?: [dictionary objectForKey:@"message"] ?: @"";
	message.author = [dictionary objectForKey:@"name"] ?: ([message.role isEqualToString:@"tool"] ? @"Tool Output" : @"AI Assistant");

	NSString *toolCallID = [dictionary objectForKey:@"tool_call_id"] ?: [dictionary objectForKey:@"toolCallID"];
	if ([toolCallID length] > 0) {
		message.toolCallID = toolCallID;
	}

	NSArray *toolCalls = [dictionary objectForKey:@"tool_calls"] ?: [dictionary objectForKey:@"toolCalls"];
	if ([toolCalls isKindOfClass:[NSArray class]]) {
		message.toolCalls = toolCalls;
	}

	NSString *toolName = [dictionary objectForKey:@"tool_name"] ?: [dictionary objectForKey:@"toolName"];
	if ([toolName length] > 0) {
		message.toolName = toolName;
	}

	message.type = [message.role isEqualToString:@"user"] ? 1 : 2;
	message.indestructible = YES;
	message.avatar = [UIImage imageNamed:(message.type == 1 ? @"Images/defaultUserAvatar.png" : @"Images/defaultAssistantAvatar.png")];
	return message;
}

+ (NSArray *)compressedMessagesFromMessages:(NSArray *)messages maxRecentCount:(NSInteger)recentCount {
	if ([messages count] == 0) {
		return messages;
	}

	NSString *apiKey = [CGAPIHelper currentAPIKey];
	if ([apiKey length] == 0) {
		return messages;
	}

	NSInteger keepCount = (recentCount < [messages count]) ? recentCount : 1;
	NSRange recentRange = NSMakeRange([messages count] - keepCount, keepCount);

	// Prevent starting recent range on an orphan tool response message or assistant message with tool calls
	while (recentRange.location < [messages count]) {
		id msgObj = [messages objectAtIndex:recentRange.location];
		NSString *role = nil;
		NSArray *tc = nil;
		if ([msgObj isKindOfClass:[CGMessage class]]) {
			CGMessage *m = (CGMessage *)msgObj;
			role = m.role;
			tc = m.toolCalls;
		} else if ([msgObj isKindOfClass:[NSDictionary class]]) {
			role = [(NSDictionary *)msgObj objectForKey:@"role"];
			tc = [(NSDictionary *)msgObj objectForKey:@"tool_calls"];
		}
		if ([role isEqualToString:@"tool"] || [tc count] > 0) {
			recentRange.location++;
			recentRange.length--;
		} else {
			break;
		}
	}
	if (recentRange.length <= 0) {
		recentRange = NSMakeRange([messages count] - 1, 1);
	}

	NSArray *recentMessages = [messages subarrayWithRange:recentRange];
	NSArray *olderMessages = [messages subarrayWithRange:NSMakeRange(0, recentRange.location)];

	if ([olderMessages count] == 0) {
		return messages;
	}

	NSMutableString *transcript = [NSMutableString string];
	for (id msgObj in olderMessages) {
		NSString *role = nil;
		NSString *content = nil;
		if ([msgObj isKindOfClass:[CGMessage class]]) {
			CGMessage *msg = (CGMessage *)msgObj;
			role = msg.role;
			content = msg.content;
		} else if ([msgObj isKindOfClass:[NSDictionary class]]) {
			NSDictionary *dict = (NSDictionary *)msgObj;
			role = [dict objectForKey:@"role"];
			content = [dict objectForKey:@"content"];
		}
		if ([content length] > 0) {
			NSString *roleName = [role isEqualToString:@"user"] ? @"User" : ([role isEqualToString:@"tool"] ? @"Tool" : @"Assistant");
			[transcript appendFormat:@"%@: %@\n", roleName, content];
		}
	}

	if ([transcript length] == 0) {
		return messages;
	}

	NSString *summaryPrompt = [NSString stringWithFormat:@"Summarize the following previous chat conversation transcript concisely, capturing key facts, decisions, and context. Output only the summary:\n\n%@", transcript];

	NSDictionary *sysInst = [NSDictionary dictionaryWithObject:
		[NSArray arrayWithObject:[NSDictionary dictionaryWithObject:@"You are a helpful assistant." forKey:@"text"]]
		forKey:@"parts"];

	NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSArray arrayWithObject:
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"user", @"role",
				[NSArray arrayWithObject:[NSDictionary dictionaryWithObject:summaryPrompt forKey:@"text"]], @"parts",
				nil]], @"contents",
		sysInst, @"system_instruction",
		nil];

	NSError *jsonError = nil;
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
	if (jsonError != nil || bodyData == nil) {
		return messages;
	}

	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] initWithURL:[CGAPIHelper configuredChatCompletionURL]] autorelease];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:bodyData];
	[request setTimeoutInterval:45.0];
	[CGAPIHelper applyAuthorizationHeadersToRequest:request withAPIKey:apiKey];

	NSURLResponse *response = nil;
	NSError *requestError = nil;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&requestError];

	if (responseData == nil || requestError != nil) {
		return messages;
	}

	NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
	NSString *aiSummary = nil;
	if ([responseDict isKindOfClass:[NSDictionary class]]) {
		NSArray *candidates = [responseDict objectForKey:@"candidates"];
		if ([candidates isKindOfClass:[NSArray class]] && [candidates count] > 0) {
			NSDictionary *firstCandidate = [candidates objectAtIndex:0];
			NSDictionary *contentDict = [firstCandidate objectForKey:@"content"];
			NSArray *parts = [contentDict objectForKey:@"parts"];
			for (NSDictionary *part in parts) {
				id textObj = [part objectForKey:@"text"];
				if ([textObj isKindOfClass:[NSString class]] && [(NSString *)textObj length] > 0) {
					aiSummary = textObj;
					break;
				}
			}
		}
	}

	if ([aiSummary length] == 0) {
		return messages;
	}

	CGMessage *summaryMessage = [[[CGMessage alloc] init] autorelease];
	summaryMessage.role = @"system";
	summaryMessage.content = [NSString stringWithFormat:@"[ARCHIVED AI CONTEXT SUMMARY of %ld previous messages]:\n%@", (long)[olderMessages count], aiSummary];

	NSMutableArray *result = [NSMutableArray array];
	[result addObject:summaryMessage];
	[result addObjectsFromArray:recentMessages];
	return result;
}

+ (CGConversation *)loadConversationWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) {
		return nil;
	}

	NSString *filePath = [self pathForConversationIdentifier:identifier];
	NSData *data = [NSData dataWithContentsOfFile:filePath];
	if (data == nil) {
		return nil;
	}

	NSDictionary *conversationDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![conversationDictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	CGConversation *conversation = [[[CGConversation alloc] init] autorelease];
	conversation.uuid = [conversationDictionary objectForKey:@"conversationID"];
	conversation.title = [conversationDictionary objectForKey:@"title"];
	conversation.creationDate = [conversationDictionary objectForKey:@"createdAt"];
	conversation.lastTimeEdited = [conversationDictionary objectForKey:@"updatedAt"];
	conversation.messages = [NSMutableArray array];

	NSArray *messages = [conversationDictionary objectForKey:@"messages"];
	NSInteger totalCount = [messages count];
	NSInteger limit = [self loadedMessageLimit];
	NSInteger startIndex = (limit > 0 && totalCount > limit) ? totalCount - limit : 0;

	// Prevent starting load window on an orphan tool response message
	while (startIndex < totalCount) {
		NSDictionary *msgDict = [messages objectAtIndex:startIndex];
		NSString *role = [msgDict objectForKey:@"role"];
		if ([role isEqualToString:@"tool"]) {
			startIndex++;
		} else {
			break;
		}
	}

	for (NSInteger i = startIndex; i < totalCount; i++) {
		NSDictionary *messageDictionary = [messages objectAtIndex:i];
		CGMessage *message = [self messageFromDictionary:messageDictionary];
		if (message != nil) {
			[conversation.messages addObject:message];
		}
	}
	conversation.messageCount = (int)[messages count];
	return conversation;
}

+ (CGConversation *)conversationWithIdentifier:(NSString *)identifier {
	CGConversation *conv = [self loadConversationWithIdentifier:identifier];
	return conv;
}

+ (NSArray *)loadConversations {
	NSMutableArray *convs = [NSMutableArray array];
	NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self conversationsDirectory] error:nil];
	for (NSString *fileName in files) {
		if (![fileName hasSuffix:@".json"]) {
			continue;
		}

		NSString *identifier = [fileName stringByDeletingPathExtension];
		CGConversation *conversation = [self loadConversationWithIdentifier:identifier];
		if (conversation != nil) {
			[convs addObject:conversation];
		}
	}

	[convs sortUsingFunction:LCConversationSort context:NULL];

	return convs;
}

+ (NSArray *)allConversations {
	return [self loadConversations];
}

+ (BOOL)compressCurrentConversationInPlace {
	NSString *currentID = [self currentConversationIdentifier];
	if ([currentID length] == 0) {
		return NO;
	}

	CGConversation *conv = [self loadConversationWithIdentifier:currentID];
	if (!conv || [conv.messages count] == 0) {
		return NO;
	}

	NSArray *compressed = [self compressedMessagesFromMessages:conv.messages maxRecentCount:10];
	if (compressed == conv.messages) {
		return NO;
	}

	[self saveMessages:compressed conversationID:currentID title:conv.title];
	return YES;
}

+ (void)saveMessages:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title {
	if (![self hasMeaningfulMessages:messages]) {
		[self deleteConversationWithIdentifier:conversationID];
		return;
	}

	NSArray *messagesToSave = messages;
	if ([self isAutoCompressionEnabled] && [messages count] > 40) {
		NSArray *compressed = [self compressedMessagesFromMessages:messages maxRecentCount:15];
		if (compressed != messages) {
			messagesToSave = compressed;
		} else {
			NSInteger totalCount = [messages count];
			NSInteger limit = [self savedMessageLimit];
			if (limit > 0 && totalCount > limit) {
				messagesToSave = [messages subarrayWithRange:NSMakeRange(totalCount - limit, limit)];
			}
		}
	} else {
		NSInteger totalCount = [messages count];
		NSInteger limit = [self savedMessageLimit];
		if (limit > 0 && totalCount > limit) {
			messagesToSave = [messages subarrayWithRange:NSMakeRange(totalCount - limit, limit)];
		}
	}

	NSMutableArray *serializedMessages = [NSMutableArray array];
	for (id messageObj in messagesToSave) {
		if ([messageObj isKindOfClass:[CGMessage class]]) {
			CGMessage *message = (CGMessage *)messageObj;
			if (![self messageShouldBePersisted:message]) {
				continue;
			}
			[serializedMessages addObject:[self dictionaryForMessage:message]];
		} else if ([messageObj isKindOfClass:[NSDictionary class]]) {
			[serializedMessages addObject:messageObj];
		}
	}

	NSString *nowString = [self stringFromDate:[NSDate date]];
	NSString *filePath = [self pathForConversationIdentifier:conversationID];
	NSDictionary *existingConversation = [NSDictionary dictionaryWithContentsOfFile:filePath];
	NSString *createdAt = [existingConversation objectForKey:@"conversationID"] ? [existingConversation objectForKey:@"createdAt"] : nil;
	if ([createdAt length] == 0) {
		createdAt = nowString;
	}

	NSString *resolvedTitle = [self derivedTitleForMessages:messages fallback:title];
	NSDictionary *conversationDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
		conversationID, @"conversationID",
		(resolvedTitle ?: @"New Chat"), @"title",
		createdAt, @"createdAt",
		nowString, @"updatedAt",
		serializedMessages, @"messages",
		nil];

	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:conversationDictionary options:0 error:nil];
	[jsonData writeToFile:filePath atomically:YES];
	[self setCurrentConversationIdentifier:conversationID];
}

+ (BOOL)deleteConversationWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) {
		return NO;
	}

	NSString *filePath = [self pathForConversationIdentifier:identifier];
	if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		[[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
	}

	if ([[identifier description] isEqualToString:[self currentConversationIdentifier]]) {
		[self setCurrentConversationIdentifier:nil];
	}
	return YES;
}

@end
