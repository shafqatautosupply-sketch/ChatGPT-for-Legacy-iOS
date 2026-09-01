#import "CGAPICommunicator.h"
#import "CGAPIHelper.h"
#import "CGMessage.h"
#import "CGAgentGuardrails.h"
#import "CGAgentTools.h"
#import "NSURLConnection+FoundationCompletions.h"
#import <UIKit/UIKit.h>

NSString * const LCAPIResponseNotification = @"LCAPIResponseNotification";
NSString * const LCAPIMessageDidUpdateNotification = @"LCAPIMessageDidUpdateNotification";
NSString * const LCAPIStatusDidChangeNotification = @"LCAPIStatusDidChangeNotification";
NSString * const LCPureChatModeChangedNotification = @"LCPureChatModeChangedNotification";
NSString * const LCAgentModeChangedNotification = @"LCAgentModeChangedNotification";
NSString * const LCTerminalModeChangedNotification = @"LCTerminalModeChangedNotification";
NSString * const LCMarkdownModeChangedNotification = @"LCMarkdownModeChangedNotification";

static NSString * const LCPureChatModeKey = @"lc_pure_chat_mode_enabled";
static NSString * const LCAgentModeKey = @"lc_agent_mode_enabled";
static NSString * const LCTerminalModeKey = @"lc_terminal_mode_enabled";
static NSString * const LCMarkdownModeKey = @"lc_markdown_mode_enabled";
static NSString * const LCRequestIntervalKey = @"agent_min_request_interval";
static BOOL g_isAgentCancelled = NO;

@implementation CGAPICommunicator

+ (BOOL)isAgentModeEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:LCAgentModeKey] == nil) {
		if ([defaults objectForKey:LCPureChatModeKey] != nil) {
			return ![defaults boolForKey:LCPureChatModeKey];
		}
		return YES;
	}
	return [defaults boolForKey:LCAgentModeKey];
}

+ (void)setAgentModeEnabled:(BOOL)enabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:enabled forKey:LCAgentModeKey];
	[defaults setBool:!enabled forKey:LCPureChatModeKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:LCAgentModeChangedNotification object:[NSNumber numberWithBool:enabled]];
	[[NSNotificationCenter defaultCenter] postNotificationName:LCPureChatModeChangedNotification object:[NSNumber numberWithBool:!enabled]];
}

+ (BOOL)isPureChatModeEnabled { return ![self isAgentModeEnabled]; }
+ (void)setPureChatModeEnabled:(BOOL)enabled { [self setAgentModeEnabled:!enabled]; }

+ (BOOL)isTerminalModeEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:LCTerminalModeKey] == nil ? NO : [defaults boolForKey:LCTerminalModeKey];
}
+ (void)setTerminalModeEnabled:(BOOL)enabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:enabled forKey:LCTerminalModeKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:LCTerminalModeChangedNotification object:[NSNumber numberWithBool:enabled]];
}

+ (BOOL)isMarkdownEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:LCMarkdownModeKey] == nil ? YES : [defaults boolForKey:LCMarkdownModeKey];
}
+ (void)setMarkdownEnabled:(BOOL)enabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:enabled forKey:LCMarkdownModeKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:LCMarkdownModeChangedNotification object:[NSNumber numberWithBool:enabled]];
}

+ (void)postStatus:(BOOL)isSending {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:LCAPIStatusDidChangeNotification object:[NSNumber numberWithBool:isSending]];
		[UIApplication sharedApplication].networkActivityIndicatorVisible = isSending;
	});
}

+ (void)cancelCurrentAgentTask { g_isAgentCancelled = YES; [self postStatus:NO]; }

+ (NSArray *)agentToolsDefinition {
	NSDictionary *runShellCommandTool = [NSDictionary dictionaryWithObjectsAndKeys:
		@"runShellCommand", @"name",
		@"Execute a terminal shell command locally within the workspace or Theos directory. Strictly protected by Whitelist Guardrails. ALLOWED BINARIES: make, git, clang, cc, c++, dpkg-deb, ldid, echo, cat, ls, cp, mv, mkdir, rm (within workspace/theos only, no wildcards/symlinks), grep, find, tar, zip, unzip, date. Shell chaining (&&, ;, |) and unlisted commands are strictly blocked.", @"description",
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"OBJECT", @"type",
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSDictionary dictionaryWithObjectsAndKeys:
					@"STRING", @"type",
					@"The allowed single shell command to execute", @"description",
					nil], @"command",
				nil], @"properties",
			[NSArray arrayWithObject:@"command"], @"required",
			nil], @"parameters",
		nil];

	NSDictionary *writeFileTool = [NSDictionary dictionaryWithObjectsAndKeys:
		@"writeFile", @"name",
		@"Write text content directly to a file within the workspace securely.", @"description",
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"OBJECT", @"type",
			[NSDictionary dictionaryWithObjectsAndKeys:
				[NSDictionary dictionaryWithObjectsAndKeys:
					@"STRING", @"type",
					@"The relative file path inside the workspace", @"description",
					nil], @"filepath",
				[NSDictionary dictionaryWithObjectsAndKeys:
					@"STRING", @"type",
					@"The exact text content to write into the file", @"description",
					nil], @"content",
				nil], @"properties",
			[NSArray arrayWithObjects:@"filepath", @"content", nil], @"required",
			nil], @"parameters",
		nil];

	NSArray *declarations = [NSArray arrayWithObjects:runShellCommandTool, writeFileTool, nil];
	return [NSArray arrayWithObject:[NSDictionary dictionaryWithObject:declarations forKey:@"functionDeclarations"]];
}

+ (NSDictionary *)payloadDictionaryForMessages:(NSArray *)messages pureChatMode:(BOOL)isPureChat {
	NSMutableArray *contents = [NSMutableArray array];
	NSMutableArray *pendingFunctionResponses = [NSMutableArray array];

	for (id message in messages) {
		if ([message isKindOfClass:[NSDictionary class]]) {
			if ([pendingFunctionResponses count] > 0) {
				[contents addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					@"user", @"role",
					[NSArray arrayWithArray:pendingFunctionResponses], @"parts",
					nil]];
				[pendingFunctionResponses removeAllObjects];
			}
			[contents addObject:message];
		} else if ([message isKindOfClass:[CGMessage class]]) {
			CGMessage *msg = (CGMessage *)message;
			NSString *role = msg.role;
			NSString *content = [msg.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

			if ([role isEqualToString:@"system"]) continue;

			if ([role isEqualToString:@"tool"]) {
				NSDictionary *responseDict = [NSDictionary dictionaryWithObject:(content ?: @"") forKey:@"output"];
				NSDictionary *funcResponse = [NSDictionary dictionaryWithObjectsAndKeys:
					(msg.toolName ?: @"tool"), @"name",
					responseDict, @"response",
					nil];
				[pendingFunctionResponses addObject:[NSDictionary dictionaryWithObject:funcResponse forKey:@"functionResponse"]];
				continue;
			}

			if ([pendingFunctionResponses count] > 0) {
				[contents addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					@"user", @"role",
					[NSArray arrayWithArray:pendingFunctionResponses], @"parts",
					nil]];
				[pendingFunctionResponses removeAllObjects];
			}

			NSString *geminiRole = @"user";
			if ([role isEqualToString:@"assistant"]) {
				geminiRole = @"model";
			}

			NSMutableArray *parts = [NSMutableArray array];

			if ([msg.toolCalls count] > 0 && !isPureChat) {
				for (NSDictionary *tc in msg.toolCalls) {
					NSDictionary *fn = [tc objectForKey:@"function"];
					NSString *fnName = [fn objectForKey:@"name"];
					NSString *argsStr = [fn objectForKey:@"arguments"];
					NSDictionary *argsDict = nil;
					if ([argsStr isKindOfClass:[NSString class]]) {
						argsDict = [NSJSONSerialization JSONObjectWithData:[argsStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
					}
					
					NSMutableDictionary *fcDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
						(fnName ?: @""), @"name",
						(argsDict ?: [NSDictionary dictionary]), @"args",
						nil];

					id thoughtSig = [tc objectForKey:@"thoughtSignature"] ?: [tc objectForKey:@"thought_signature"] ?: [tc objectForKey:@"extra_content"];
					NSMutableDictionary *partDict = [NSMutableDictionary dictionaryWithObject:fcDict forKey:@"functionCall"];
					if (thoughtSig != nil) {
						[partDict setObject:thoughtSig forKey:@"thoughtSignature"];
					}
					[parts addObject:partDict];
				}
			}

			if ([content length] > 0) {
				[parts addObject:[NSDictionary dictionaryWithObject:content forKey:@"text"]];
			}

			if ([parts count] > 0) {
				[contents addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					geminiRole, @"role",
					parts, @"parts",
					nil]];
			}
		}
	}

	if ([pendingFunctionResponses count] > 0) {
		[contents addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			@"user", @"role",
			[NSArray arrayWithArray:pendingFunctionResponses], @"parts",
			nil]];
		[pendingFunctionResponses removeAllObjects];
	}

	NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		contents, @"contents",
		nil];

	NSString *systemPrompt = [CGAPIHelper configuredSystemPrompt];
	if ([systemPrompt length] > 0) {
		NSDictionary *sysInst = [NSDictionary dictionaryWithObject:
			[NSArray arrayWithObject:[NSDictionary dictionaryWithObject:systemPrompt forKey:@"text"]]
			forKey:@"parts"];
		[payload setObject:sysInst forKey:@"system_instruction"];
	}

	if (!isPureChat) {
		[payload setObject:[self agentToolsDefinition] forKey:@"tools"];
		NSDictionary *thinkingConfig = [NSDictionary dictionaryWithObject:@"HIGH" forKey:@"thinkingLevel"];
		NSDictionary *genConfig = [NSDictionary dictionaryWithObject:thinkingConfig forKey:@"thinkingConfig"];
		[payload setObject:genConfig forKey:@"generationConfig"];
	}

	return payload;
}

+ (void)postMessageText:(NSString *__nullable)text assistantRole:(NSString *)role {
	CGMessage *message = [role isEqualToString:@"assistant"] ? [CGAPIHelper assistantMessageWithText:text] : [CGMessage localMessageWithText:text];
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:LCAPIResponseNotification object:message];
	});
}

+ (NSString *)workspaceDirectory {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *savedWorkspace = [defaults stringForKey:@"agent_workspace_dir"];
	if ([savedWorkspace length] > 0) {
		NSFileManager *fm = [NSFileManager defaultManager];
		if (![fm fileExistsAtPath:savedWorkspace]) {
			[fm createDirectoryAtPath:savedWorkspace withIntermediateDirectories:YES attributes:nil error:nil];
		}
		return savedWorkspace;
	}
	NSString *sandboxPath = @"/var/mobile/Documents/SandBox";
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:sandboxPath]) {
		[fm createDirectoryAtPath:sandboxPath withIntermediateDirectories:YES attributes:nil error:nil];
	}
	return sandboxPath;
}

+ (void)createChatCompletionWithMessages:(NSArray *)messages {
	g_isAgentCancelled = NO;
	[self postStatus:YES];

	BOOL isPureChat = [self isPureChatModeEnabled];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		__block NSMutableArray *currentMessages = [NSMutableArray arrayWithArray:messages];
		static NSTimeInterval lastRequestTime = 0;

		while (!g_isAgentCancelled) {
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			NSTimeInterval minInterval = 5.0;
			id intervalObj = [defaults objectForKey:LCRequestIntervalKey];
			if (intervalObj != nil) minInterval = [intervalObj doubleValue];

			if (minInterval > 0) {
				NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
				NSTimeInterval elapsed = now - lastRequestTime;
				if (elapsed < minInterval) {
					NSTimeInterval sleepDuration = minInterval - elapsed;
					if (sleepDuration > 0 && sleepDuration < 60) [NSThread sleepForTimeInterval:sleepDuration];
				}
			}

			if (g_isAgentCancelled) { [self postStatus:NO]; return; }
			lastRequestTime = [[NSDate date] timeIntervalSince1970];

			NSString *apiKey = [CGAPIHelper currentAPIKey];
			if ([apiKey length] == 0) {
				[self postMessageText:@"API key is missing." assistantRole:@"assistant"];
				[self postStatus:NO];
				return;
			}

			NSDictionary *payload = [self payloadDictionaryForMessages:currentMessages pureChatMode:isPureChat];
			NSError *jsonError = nil;
			NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
			if (jsonError != nil || bodyData == nil) {
				[self postMessageText:@"Failed to encode request payload." assistantRole:@"assistant"];
				[self postStatus:NO];
				return;
			}

			NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] initWithURL:[CGAPIHelper configuredChatCompletionURL]] autorelease];
			[request setHTTPMethod:@"POST"];
			[request setHTTPBody:bodyData];
			[request setTimeoutInterval:60.0];
			[CGAPIHelper applyAuthorizationHeadersToRequest:request withAPIKey:apiKey];

			NSURLResponse *response = nil;
			NSError *requestError = nil;
			NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&requestError];
			if (g_isAgentCancelled) { [self postStatus:NO]; return; }

			if (responseData == nil || requestError != nil) {
				NSString *rawError = [CGAPIHelper extractErrorMessageFromResponseData:responseData fallback:[requestError localizedDescription] ?: @"Network connection error"];
				[self postMessageText:rawError assistantRole:@"assistant"];
				[self postStatus:NO];
				return;
			}

			NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
			if ([httpResponse respondsToSelector:@selector(statusCode)] && [httpResponse statusCode] != 200) {
				NSString *cleanError = [CGAPIHelper extractErrorMessageFromResponseData:responseData fallback:@"HTTP error encountered"];
				[self postMessageText:cleanError assistantRole:@"assistant"];
				[self postStatus:NO];
				return;
			}

			NSDictionary *parsedResponse = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&jsonError];
			if (jsonError != nil || ![parsedResponse isKindOfClass:[NSDictionary class]]) {
				[self postMessageText:@"Invalid JSON response" assistantRole:@"assistant"];
				[self postStatus:NO];
				return;
			}

			NSDictionary *errorDictionary = [parsedResponse objectForKey:@"error"];
			if ([errorDictionary isKindOfClass:[NSDictionary class]]) {
				NSString *errMsg = [errorDictionary objectForKey:@"message"] ?: @"API Error encountered";
				[self postMessageText:errMsg assistantRole:@"assistant"];
				[self postStatus:NO];
				return;
			}

			NSArray *candidates = [parsedResponse objectForKey:@"candidates"];
			if (![candidates isKindOfClass:[NSArray class]] || [candidates count] == 0) {
				NSDictionary *promptFeedback = [parsedResponse objectForKey:@"promptFeedback"];
				NSString *errDescription = promptFeedback ? [NSString stringWithFormat:@"Prompt Feedback: %@", promptFeedback] : [NSString stringWithFormat:@"No candidates returned. Raw response: %@", parsedResponse];
				[self postMessageText:errDescription assistantRole:@"assistant"];
				[self postStatus:NO];
				return;
			}

			NSDictionary *firstCandidate = [candidates objectAtIndex:0];
			NSDictionary *contentDict = [firstCandidate objectForKey:@"content"];
			NSArray *parts = [contentDict objectForKey:@"parts"];

			NSString *responseText = @"";
			NSMutableArray *toolCalls = [NSMutableArray array];

			for (NSDictionary *part in parts) {
				id textObj = [part objectForKey:@"text"];
				if ([textObj isKindOfClass:[NSString class]]) {
					responseText = [responseText length] > 0 ? [responseText stringByAppendingString:textObj] : textObj;
				}

				id thoughtObj = [part objectForKey:@"thought"];
				if ([thoughtObj isKindOfClass:[NSString class]]) {
					responseText = [responseText length] > 0 ? [responseText stringByAppendingFormat:@"\n[Thought: %@]", thoughtObj] : [NSString stringWithFormat:@"[Thought: %@]", thoughtObj];
				}

				NSDictionary *fc = [part objectForKey:@"functionCall"] ?: [part objectForKey:@"function_call"];
				if ([fc isKindOfClass:[NSDictionary class]]) {
					NSString *fnName = [fc objectForKey:@"name"];
					NSDictionary *args = [fc objectForKey:@"args"] ?: [fc objectForKey:@"arguments"];
					NSData *argsData = [NSJSONSerialization dataWithJSONObject:(args ?: [NSDictionary dictionary]) options:0 error:nil];
					NSString *argsString = [[[NSString alloc] initWithData:argsData encoding:NSUTF8StringEncoding] autorelease];

					NSString *callID = [fc objectForKey:@"id"] ?: [NSString stringWithFormat:@"call_%u", arc4random() % 100000];

					NSMutableDictionary *toolCallEntry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
						callID, @"id",
						@"function", @"type",
						[NSDictionary dictionaryWithObjectsAndKeys:
							fnName, @"name",
							argsString, @"arguments",
							nil], @"function",
						nil];

					id thoughtSig = [part objectForKey:@"thoughtSignature"] ?: [part objectForKey:@"thought_signature"] ?: [fc objectForKey:@"thoughtSignature"] ?: [fc objectForKey:@"thought_signature"];
					if (thoughtSig != nil) {
						[toolCallEntry setObject:thoughtSig forKey:@"thoughtSignature"];
					}

					[toolCalls addObject:toolCallEntry];
				}
			}

			CGMessage *assistantMessage = [[[CGMessage alloc] init] autorelease];
			assistantMessage.author = [CGAPIHelper providerDisplayName];
			assistantMessage.role = @"assistant";
			assistantMessage.type = 2;
			
			if ([responseText length] > 0) {
				assistantMessage.content = responseText;
			} else if ([toolCalls count] > 0) {
				NSMutableArray *callDescs = [NSMutableArray array];
				for (NSDictionary *tc in toolCalls) {
					NSDictionary *fn = [tc objectForKey:@"function"];
					NSString *name = [fn objectForKey:@"name"] ?: @"tool";
					NSString *args = [fn objectForKey:@"arguments"] ?: @"";
					[callDescs addObject:[NSString stringWithFormat:@"Tool Call: %@\nArguments: %@", name, args]];
				}
				assistantMessage.content = [callDescs componentsJoinedByString:@"\n\n"];
			} else {
				assistantMessage.content = [NSString stringWithFormat:@"[Received empty response parts. Raw candidate: %@]", firstCandidate];
			}

            assistantMessage.toolCalls = toolCalls;
			assistantMessage.indestructible = YES;
			assistantMessage.avatar = [UIImage imageNamed:@"Images/defaultAssistantAvatar.png"];

			[currentMessages addObject:assistantMessage];

			dispatch_async(dispatch_get_main_queue(), ^{
				if (!g_isAgentCancelled) {
					[[NSNotificationCenter defaultCenter] postNotificationName:LCAPIResponseNotification object:assistantMessage];
				}
			});

			if (isPureChat || [toolCalls count] == 0) {
				[self postStatus:NO];
				break;
			} else {
				if (g_isAgentCancelled) { [self postStatus:NO]; return; }

				for (NSDictionary *toolCall in toolCalls) {
					if (g_isAgentCancelled) break;

					NSString *toolCallID = [toolCall objectForKey:@"id"];
					NSDictionary *functionDict = [toolCall objectForKey:@"function"];
					NSString *funcName = [functionDict objectForKey:@"name"];
					NSString *argumentsString = [functionDict objectForKey:@"arguments"];

					NSDictionary *arguments = nil;
					if ([argumentsString isKindOfClass:[NSString class]]) {
						arguments = [NSJSONSerialization JSONObjectWithData:[argumentsString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
					}

					NSString *toolOutput = @"";
					NSString *workspaceDir = [self workspaceDirectory];

					if ([funcName isEqualToString:@"runShellCommand"]) {
						NSString *command = [arguments objectForKey:@"command"];
						toolOutput = [CGAgentTools executeShellCommand:command workspaceDirectory:workspaceDir];
					} else if ([funcName isEqualToString:@"writeFile"]) {
						NSString *filepath = [arguments objectForKey:@"filepath"];
						NSString *content = [arguments objectForKey:@"content"];
						toolOutput = [CGAgentTools writeFileAtPath:filepath content:content workspaceDirectory:workspaceDir];
					} else {
						toolOutput = [NSString stringWithFormat:@"Error: Unknown tool function '%@'", funcName];
					}

					if ([toolOutput length] > 4000) {
						toolOutput = [NSString stringWithFormat:@"%@\n[Output truncated]", [toolOutput substringToIndex:4000]];
					}

					CGMessage *toolMessage = [[[CGMessage alloc] init] autorelease];
					toolMessage.author = @"Tool Output";
					toolMessage.role = @"tool";
					toolMessage.toolCallID = toolCallID;
					toolMessage.toolName = funcName;
					toolMessage.content = (toolOutput ?: @"") ;
					toolMessage.indestructible = YES;
					toolMessage.avatar = [UIImage imageNamed:@"Images/defaultAssistantAvatar.png"];
					[currentMessages addObject:toolMessage];

					dispatch_async(dispatch_get_main_queue(), ^{
						if (!g_isAgentCancelled) {
							[[NSNotificationCenter defaultCenter] postNotificationName:LCAPIResponseNotification object:toolMessage];
						}
					});

					[NSThread sleepForTimeInterval:0.04];
				}

				if (g_isAgentCancelled) { [self postStatus:NO]; return; }
				continue;
			}
		}

		[self postStatus:NO];
	});
}

@end
