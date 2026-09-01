#import "CGAPIHelper.h"
#import "CGMessage.h"
#import "CGAPICommunicator.h"

@interface NSData (CGBase64)
- (NSString *)base64Encoding;
@end

static NSString * const LCProviderProfilesKey = @"providerProfiles";
static NSString * const LCActiveProviderProfileIDKey = @"activeProviderProfileID";
static NSString * const LCSystemPromptKey = @"systemPrompt";

static NSDictionary *cachedActiveProfile = nil;
static NSArray *cachedProfiles = nil;
static NSString *cachedSystemPrompt = nil;

@implementation CGAPIHelper

+ (void)invalidateMemoryCache {
	[cachedActiveProfile release];
	cachedActiveProfile = nil;
	[cachedProfiles release];
	cachedProfiles = nil;
	[cachedSystemPrompt release];
	cachedSystemPrompt = nil;
}

+ (NSString *)defaultSystemPrompt {
	return @"You are a concise, helpful assistant in a legacy iOS app. Prefer clear, direct answers. When searching for or modifying files via shell commands, if a relative path fails or you are unsure of the directory structure, automatically run `find . -name '<filename>'` or `ls` first to locate files before grepping or reading them.";
}

+ (NSString *)stringByStrippingThinkBlocks:(NSString *)value extractedReasoning:(NSString **)reasoningOutput {
	if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
		return @"";
	}

	NSMutableString *visibleText = [NSMutableString stringWithString:value];
	NSMutableArray *reasoningParts = [NSMutableArray array];
	NSRegularExpression *thinkRegex = [NSRegularExpression regularExpressionWithPattern:@"<think>([\\s\\S]*?)</think>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSArray *matches = [thinkRegex matchesInString:value options:0 range:NSMakeRange(0, [value length])];
	for (NSInteger index = [matches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [matches objectAtIndex:index];
		if ([match numberOfRanges] > 1) {
			NSString *reasoningText = [value substringWithRange:[match rangeAtIndex:1]];
			if ([reasoningText length] > 0) {
				[reasoningParts insertObject:reasoningText atIndex:0];
			}
		}
		[visibleText replaceCharactersInRange:match.range withString:@""];
	}

	NSString *trimmedVisibleText = [visibleText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (reasoningOutput != NULL) {
		*reasoningOutput = ([reasoningParts count] > 0 ? [reasoningParts componentsJoinedByString:@"\n\n"] : nil);
	}
	return trimmedVisibleText;
}

+ (NSString *)stringByNormalizingMarkdown:(NSString *)value {
	if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
		return @"";
	}
	NSString *normalized = [value stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
	normalized = [normalized stringByReplacingOccurrencesOfString:@"\\t" withString:@"\t"];
	return [normalized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (void)applyMarkdownAttributesToAttributedString:(NSMutableAttributedString *)attributedString {
	if (![CGAPICommunicator isMarkdownEnabled]) {
		return;
	}

	NSString *fullText = [attributedString string];
	if ([fullText length] == 0) {
		return;
	}

	// 1. Triple-backtick code blocks: ```language ... ```
	NSRegularExpression *codeBlockRegex = [NSRegularExpression regularExpressionWithPattern:@"```[a-zA-Z]*\\n([\\s\\S]*?)```" options:0 error:nil];
	NSArray *codeBlockMatches = [codeBlockRegex matchesInString:fullText options:0 range:NSMakeRange(0, [fullText length])];
	for (NSInteger index = [codeBlockMatches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [codeBlockMatches objectAtIndex:index];
		NSRange contentRange = [match rangeAtIndex:1];
		NSString *matchedText = [fullText substringWithRange:contentRange];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIFont fontWithName:@"Courier" size:13.0f], NSFontAttributeName,
			[UIColor colorWithWhite:0.15f alpha:1.0f], NSForegroundColorAttributeName,
			nil];
		NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:matchedText attributes:attributes] autorelease];
		[attributedString replaceCharactersInRange:match.range withAttributedString:replacement];
	}

	fullText = [attributedString string];

	// 2. Inline code: `code`
	NSRegularExpression *inlineCodeRegex = [NSRegularExpression regularExpressionWithPattern:@"`([^`]+)`" options:0 error:nil];
	NSArray *codeMatches = [inlineCodeRegex matchesInString:fullText options:0 range:NSMakeRange(0, [fullText length])];
	for (NSInteger index = [codeMatches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [codeMatches objectAtIndex:index];
		NSRange contentRange = [match rangeAtIndex:1];
		NSString *matchedText = [fullText substringWithRange:contentRange];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIFont fontWithName:@"Courier" size:14.0f], NSFontAttributeName,
			[UIColor colorWithWhite:0.18f alpha:1.0f], NSForegroundColorAttributeName,
			nil];
		NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:matchedText attributes:attributes] autorelease];
		[attributedString replaceCharactersInRange:match.range withAttributedString:replacement];
	}

	fullText = [attributedString string];

	// 3. Bold text: **text** or __text__
	NSRegularExpression *boldRegex = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*([^*]+)\\*\\*" options:0 error:nil];
	NSArray *boldMatches = [boldRegex matchesInString:fullText options:0 range:NSMakeRange(0, [fullText length])];
	for (NSInteger index = [boldMatches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [boldMatches objectAtIndex:index];
		NSRange contentRange = [match rangeAtIndex:1];
		NSString *matchedText = [fullText substringWithRange:contentRange];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIFont boldSystemFontOfSize:14.0f], NSFontAttributeName,
			nil];
		NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:matchedText attributes:attributes] autorelease];
		[attributedString replaceCharactersInRange:match.range withAttributedString:replacement];
	}

	fullText = [attributedString string];

	// 4. Italic text: *text*
	NSRegularExpression *italicRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\*)\\*([^*]+)\\*(?!\\*)" options:0 error:nil];
	NSArray *italicMatches = [italicRegex matchesInString:fullText options:0 range:NSMakeRange(0, [fullText length])];
	for (NSInteger index = [italicMatches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [italicMatches objectAtIndex:index];
		NSRange contentRange = [match rangeAtIndex:1];
		NSString *matchedText = [fullText substringWithRange:contentRange];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIFont italicSystemFontOfSize:14.0f], NSFontAttributeName,
			nil];
		NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:matchedText attributes:attributes] autorelease];
		[attributedString replaceCharactersInRange:match.range withAttributedString:replacement];
	}

	fullText = [attributedString string];

	// 5. Strikethrough: ~~text~~
	NSRegularExpression *strikeRegex = [NSRegularExpression regularExpressionWithPattern:@"~~([^~]+)~~" options:0 error:nil];
	NSArray *strikeMatches = [strikeRegex matchesInString:fullText options:0 range:NSMakeRange(0, [fullText length])];
	for (NSInteger index = [strikeMatches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [strikeMatches objectAtIndex:index];
		NSRange contentRange = [match rangeAtIndex:1];
		NSString *matchedText = [fullText substringWithRange:contentRange];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:NSUnderlineStyleSingle], NSStrikethroughStyleAttributeName,
			nil];
		NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:matchedText attributes:attributes] autorelease];
		[attributedString replaceCharactersInRange:match.range withAttributedString:replacement];
	}

	fullText = [attributedString string];

	// 6. Links: [text](url)
	NSRegularExpression *linkRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^\\)]+)\\)" options:0 error:nil];
	NSArray *linkMatches = [linkRegex matchesInString:fullText options:0 range:NSMakeRange(0, [fullText length])];
	for (NSInteger index = [linkMatches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [linkMatches objectAtIndex:index];
		NSRange textRange = [match rangeAtIndex:1];
		NSString *linkText = [fullText substringWithRange:textRange];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIColor colorWithRed:0.0f green:0.4f blue:0.8f alpha:1.0f], NSForegroundColorAttributeName,
			[NSNumber numberWithInt:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName,
			nil];
		NSAttributedString *replacement = [[[NSAttributedString alloc] initWithString:linkText attributes:attributes] autorelease];
		[attributedString replaceCharactersInRange:match.range withAttributedString:replacement];
	}

	fullText = [attributedString string];

	// 7. Headers: ### Header or ## Header or # Header
	NSRegularExpression *headerRegex = [NSRegularExpression regularExpressionWithPattern:@"(^|\\n)(#{1,4})\\s+([^\n]+)" options:0 error:nil];
	NSArray *headerMatches = [headerRegex matchesInString:fullText options:0 range:NSMakeRange(0, [fullText length])];
	for (NSInteger index = [headerMatches count] - 1; index >= 0; index--) {
		NSTextCheckingResult *match = [headerMatches objectAtIndex:index];
		NSRange prefixRange = [match rangeAtIndex:1];
		NSRange textRange = [match rangeAtIndex:3];
		NSString *matchedText = [fullText substringWithRange:textRange];
		
		NSRange fullMatchRange = match.range;
		NSString *prefixStr = [fullText substringWithRange:prefixRange];
		
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIFont boldSystemFontOfSize:15.0f], NSFontAttributeName,
			[UIColor colorWithRed:0.05f green:0.05f blue:0.05f alpha:1.0f], NSForegroundColorAttributeName,
			nil];
		NSMutableString *replacementString = [NSMutableString stringWithString:prefixStr];
		[replacementString appendString:matchedText];
		
		NSMutableAttributedString *replacement = [[[NSMutableAttributedString alloc] initWithString:replacementString] autorelease];
		[replacement addAttributes:attributes range:NSMakeRange([prefixStr length], [matchedText length])];
		[attributedString replaceCharactersInRange:fullMatchRange withAttributedString:replacement];
	}
}

+ (NSString *)trimmedString:(NSString *)value fallback:(NSString *)fallback {
	if (![value isKindOfClass:[NSString class]]) {
		return fallback;
	}

	NSString *trimmedValue = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmedValue length] == 0) {
		return fallback;
	}
	return trimmedValue;
}

+ (NSString *)providerIdentifierFromValues:(NSDictionary *)values fallback:(NSString *)fallback {
	NSString *providerName = [self trimmedString:[values objectForKey:@"providerName"] fallback:fallback];
	NSString *baseURL = [self trimmedString:[values objectForKey:@"baseURL"] fallback:@""];
	NSString *identifier = [NSString stringWithFormat:@"%@|%@", providerName, baseURL];
	return identifier;
}

+ (NSDictionary *)profileDictionaryFromValues:(NSDictionary *)values identifier:(NSString *)identifierFallback {
	NSString *providerName = [self trimmedString:[values objectForKey:@"providerName"] fallback:@"Google Gemini"];
	NSString *baseURL = [self trimmedString:[values objectForKey:@"baseURL"] fallback:@"https://generativelanguage.googleapis.com"];
	NSString *chatModel = [self trimmedString:[values objectForKey:@"c-aiModel"] fallback:@"gemini-2.5-flash"];
	NSString *apiKey = [self trimmedString:[values objectForKey:@"apiKey"] fallback:@""];
	NSString *identifier = [self providerIdentifierFromValues:values fallback:identifierFallback];

	return [NSDictionary dictionaryWithObjectsAndKeys:
		identifier, @"identifier",
		providerName, @"providerName",
		baseURL, @"baseURL",
		chatModel, @"c-aiModel",
		apiKey, @"apiKey",
		nil];
}

+ (void)registerProviderDefaults {
	[self invalidateMemoryCache];
	NSString *configPath = [[NSBundle mainBundle] pathForResource:@"ProviderConfig" ofType:@"plist"];
	if (configPath == nil) {
		return;
	}

	NSDictionary *bundleDefaults = [NSDictionary dictionaryWithContentsOfFile:configPath];
	if (bundleDefaults == nil) {
		return;
	}
	NSMutableDictionary *defaults = [NSMutableDictionary dictionaryWithDictionary:bundleDefaults];
	[defaults setObject:[self defaultSystemPrompt] forKey:LCSystemPromptKey];

	[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];

	NSArray *profiles = [[NSUserDefaults standardUserDefaults] objectForKey:LCProviderProfilesKey];
	if ([profiles count] == 0) {
		NSDictionary *initialProfile = [self profileDictionaryFromValues:[NSDictionary dictionaryWithObjectsAndKeys:
			@"Google Gemini", @"providerName",
			@"https://generativelanguage.googleapis.com", @"baseURL",
			@"gemini-2.5-flash", @"c-aiModel",
			@"", @"apiKey",
			nil] identifier:@"default-profile"];

		[[NSUserDefaults standardUserDefaults] setObject:[NSArray arrayWithObject:initialProfile] forKey:LCProviderProfilesKey];
		[[NSUserDefaults standardUserDefaults] setObject:[initialProfile objectForKey:@"identifier"] forKey:LCActiveProviderProfileIDKey];
	}
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)providerDisplayName {
	return [self trimmedString:[[self activeProviderProfile] objectForKey:@"providerName"] fallback:@"Google Gemini"];
}

+ (NSString *)storedValueForKey:(NSString *)key fallback:(NSString *)fallback {
	return [self trimmedString:[[self activeProviderProfile] objectForKey:key] fallback:fallback];
}

+ (NSString *)currentAPIKey {
	NSString *apiKey = [self trimmedString:[[self activeProviderProfile] objectForKey:@"apiKey"] fallback:nil];
	if ([apiKey isEqualToString:@"PASTE_API_KEY_HERE"]) {
		return nil;
	}
	return apiKey;
}

+ (NSString *)configuredBaseURL {
	NSString *baseURL = [self trimmedString:[[self activeProviderProfile] objectForKey:@"baseURL"] fallback:@"https://generativelanguage.googleapis.com"];
	while ([baseURL hasSuffix:@"/"]) {
		baseURL = [baseURL substringToIndex:[baseURL length] - 1];
	}
	return baseURL;
}

+ (NSString *)configuredChatModel {
	return [self trimmedString:[[self activeProviderProfile] objectForKey:@"c-aiModel"] fallback:@"gemini-2.5-flash"];
}

+ (NSString *)configuredSystemPrompt {
	if (cachedSystemPrompt != nil) {
		return cachedSystemPrompt;
	}
	NSString *prompt = [[NSUserDefaults standardUserDefaults] objectForKey:LCSystemPromptKey];
	cachedSystemPrompt = [[self trimmedString:prompt fallback:@""] retain];
	return cachedSystemPrompt;
}

+ (void)saveSystemPrompt:(NSString *)prompt {
	[self invalidateMemoryCache];
	NSString *trimmedPrompt = [self trimmedString:prompt fallback:@""];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([trimmedPrompt length] > 0) {
		[defaults setObject:trimmedPrompt forKey:LCSystemPromptKey];
	} else {
		[defaults setObject:@"" forKey:LCSystemPromptKey];
	}
	[defaults synchronize];
}

+ (NSArray *)providerProfiles {
	if (cachedProfiles != nil) {
		return cachedProfiles;
	}
	NSArray *profiles = [[NSUserDefaults standardUserDefaults] objectForKey:LCProviderProfilesKey];
	if (![profiles isKindOfClass:[NSArray class]]) {
		cachedProfiles = [[NSArray array] retain];
	} else {
		cachedProfiles = [profiles retain];
	}
	return cachedProfiles;
}

+ (NSString *)activeProviderProfileIdentifier {
	return [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_activeProviderProfileID"] ?: [[NSUserDefaults standardUserDefaults] objectForKey:LCActiveProviderProfileIDKey];
}

+ (NSDictionary *)activeProviderProfile {
	if (cachedActiveProfile != nil) {
		return cachedActiveProfile;
	}
	NSString *activeIdentifier = [self activeProviderProfileIdentifier];
	NSArray *profiles = [self providerProfiles];
	for (NSDictionary *profile in profiles) {
		if ([[profile objectForKey:@"identifier"] isEqualToString:activeIdentifier]) {
			cachedActiveProfile = [profile retain];
			return cachedActiveProfile;
		}
	}
	NSDictionary *fallback = ([profiles count] > 0 ? [profiles objectAtIndex:0] : [NSDictionary dictionary]);
	cachedActiveProfile = [fallback retain];
	return cachedActiveProfile;
}

+ (void)persistProfiles:(NSArray *)profiles activeIdentifier:(NSString *)activeIdentifier {
	[self invalidateMemoryCache];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:profiles forKey:LCProviderProfilesKey];
	if ([activeIdentifier length] > 0) {
		[defaults setObject:activeIdentifier forKey:LCActiveProviderProfileIDKey];
	}
	[defaults synchronize];
}

+ (void)saveActiveProviderProfileWithValues:(NSDictionary *)values {
	[self invalidateMemoryCache];
	NSString *activeIdentifier = [self activeProviderProfileIdentifier];
	NSMutableArray *profiles = [NSMutableArray arrayWithArray:[self providerProfiles]];
	NSDictionary *updatedProfile = [self profileDictionaryFromValues:values identifier:(activeIdentifier ?: @"default-profile")];
	BOOL updated = NO;
	for (NSUInteger index = 0; index < [profiles count]; index++) {
		NSDictionary *profile = [profiles objectAtIndex:index];
		if ([[profile objectForKey:@"identifier"] isEqualToString:activeIdentifier]) {
			[profiles replaceObjectAtIndex:index withObject:updatedProfile];
			updated = YES;
			break;
		}
	}
	if (!updated) {
		[profiles addObject:updatedProfile];
	}
	[self persistProfiles:profiles activeIdentifier:[updatedProfile objectForKey:@"identifier"]];
}

+ (void)createProviderProfileWithValues:(NSDictionary *)values {
	[self invalidateMemoryCache];
	NSMutableArray *profiles = [NSMutableArray arrayWithArray:[self providerProfiles]];
	NSString *identifier = [NSString stringWithFormat:@"profile-%u", arc4random()];
	NSDictionary *newProfile = [self profileDictionaryFromValues:values identifier:identifier];
	[profiles addObject:newProfile];
	[self persistProfiles:profiles activeIdentifier:[newProfile objectForKey:@"identifier"]];
}

+ (void)activateProviderProfileWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) {
		return;
	}
	[self invalidateMemoryCache];
	[self persistProfiles:[self providerProfiles] activeIdentifier:identifier];
}

+ (void)updateProviderProfileWithIdentifier:(NSString *)identifier values:(NSDictionary *)values {
	if ([identifier length] == 0) {
		return;
	}
	[self invalidateMemoryCache];
	NSMutableArray *profiles = [NSMutableArray arrayWithArray:[self providerProfiles]];
	NSDictionary *updatedProfile = [self profileDictionaryFromValues:values identifier:identifier];
	for (NSUInteger index = 0; index < [profiles count]; index++) {
		NSDictionary *profile = [profiles objectAtIndex:index];
		if ([[profile objectForKey:@"identifier"] isEqualToString:identifier]) {
			[profiles replaceObjectAtIndex:index withObject:updatedProfile];
			[self persistProfiles:profiles activeIdentifier:[self activeProviderProfileIdentifier]];
			return;
		}
	}
}

+ (void)deleteProviderProfileWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) {
		return;
	}
	[self invalidateMemoryCache];
	NSMutableArray *profiles = [NSMutableArray arrayWithArray:[self providerProfiles]];
	for (NSInteger index = [profiles count] - 1; index >= 0; index--) {
		NSDictionary *profile = [profiles objectAtIndex:index];
		if ([[profile objectForKey:@"identifier"] isEqualToString:identifier]) {
			[profiles removeObjectAtIndex:index];
		}
	}

	NSString *activeIdentifier = [self activeProviderProfileIdentifier];
	if ([profiles count] == 0) {
		NSDictionary *fallbackProfile = [self profileDictionaryFromValues:[NSDictionary dictionaryWithObjectsAndKeys:
			@"Google Gemini", @"providerName",
			@"https://generativelanguage.googleapis.com", @"baseURL",
			@"gemini-2.5-flash", @"c-aiModel",
			@"", @"apiKey",
			nil] identifier:@"default-profile"];
		[profiles addObject:fallbackProfile];
		activeIdentifier = [fallbackProfile objectForKey:@"identifier"];
	} else if ([activeIdentifier isEqualToString:identifier]) {
		activeIdentifier = [[profiles objectAtIndex:0] objectForKey:@"identifier"];
	}

	[self persistProfiles:profiles activeIdentifier:activeIdentifier];
}

+ (NSURL *)configuredChatCompletionURL {
	NSString *baseURL = [self configuredBaseURL];
	NSString *model = [self configuredChatModel];
	if ([baseURL length] == 0) baseURL = @"https://generativelanguage.googleapis.com";
	if ([model length] == 0) model = @"gemini-2.5-flash";
	NSString *fullString = [NSString stringWithFormat:@"%@/v1beta/models/%@:generateContent", baseURL, model];
	return [NSURL URLWithString:fullString];
}

+ (void)applyAuthorizationHeadersToRequest:(NSMutableURLRequest *)request withAPIKey:(NSString *)key {
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	if ([key length] > 0) {
		[request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
	}
}

+ (CGMessage *)messageWithText:(NSString *)text role:(NSString *)role {
	CGMessage *message = [[[CGMessage alloc] init] autorelease];
	message.author = [self providerDisplayName];
	message.role = role;
	message.type = 2;
	message.content = text;
	message.indestructible = YES;
	message.avatar = [UIImage imageNamed:@"Images/defaultAssistantAvatar.png"];
	return message;
}

+ (NSString *)displayTextForMessage:(CGMessage *)message {
	if (![message isKindOfClass:[CGMessage class]]) {
		return @"";
	}

	NSString *rawContent = message.content ?: @"";
	
	for (int depth = 0; depth < 8; depth++) {
		NSString *trimmedContent = [rawContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([trimmedContent length] == 0) {
			break;
		}

		NSString *unescaped = trimmedContent;
		unescaped = [unescaped stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
		unescaped = [unescaped stringByReplacingOccurrencesOfString:@"\\\\n" withString:@"\n"];
		unescaped = [unescaped stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
		
		if ([unescaped hasPrefix:@"\""] && [unescaped hasSuffix:@"\""] && [unescaped length] >= 2) {
			unescaped = [unescaped substringWithRange:NSMakeRange(1, [unescaped length] - 2)];
			unescaped = [unescaped stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
		}

		NSData *jsonData = [unescaped dataUsingEncoding:NSUTF8StringEncoding];
		if (jsonData != nil) {
			NSError *jsonError = nil;
			id parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
			if (jsonError == nil && [parsed isKindOfClass:[NSDictionary class]]) {
				NSDictionary *dict = (NSDictionary *)parsed;
				NSDictionary *errDict = [dict objectForKey:@"error"];
				if ([errDict isKindOfClass:[NSDictionary class]]) {
					NSString *errMsg = [errDict objectForKey:@"message"];
					if ([errMsg isKindOfClass:[NSString class]] && [errMsg length] > 0) {
						rawContent = errMsg;
						continue;
					}
				}
				id directContent = [dict objectForKey:@"content"];
				if ([directContent isKindOfClass:[NSString class]]) {
					rawContent = directContent;
					continue;
				}
			}
		}
		break;
	}

	NSString *discardedReasoning = nil;
	NSString *visibleText = [self stringByStrippingThinkBlocks:rawContent extractedReasoning:&discardedReasoning];
	if ([message.hiddenReasoningContent length] == 0 && [discardedReasoning length] > 0) {
		message.hiddenReasoningContent = discardedReasoning;
	}
	return [self stringByNormalizingMarkdown:visibleText];
}

+ (NSAttributedString *)attributedDisplayStringForMessage:(CGMessage *)message font:(UIFont *)font textColor:(UIColor *)textColor {
	NSString *displayText = [self displayTextForMessage:message];
	NSMutableAttributedString *attributedString = [[[NSMutableAttributedString alloc] initWithString:displayText attributes:[NSDictionary dictionaryWithObjectsAndKeys:
		(font ?: [UIFont systemFontOfSize:15.0f]), NSFontAttributeName,
		(textColor ?: [UIColor blackColor]), NSForegroundColorAttributeName,
		nil]] autorelease];
	[self applyMarkdownAttributesToAttributedString:attributedString];
	return attributedString;
}

+ (CGFloat)heightForMessage:(CGMessage *)message width:(CGFloat)width font:(UIFont *)font {
	NSString *displayText = [self displayTextForMessage:message];
	CGSize textSize = [displayText sizeWithFont:(font ?: [UIFont systemFontOfSize:15.0f])
				  constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
				      lineBreakMode:NSLineBreakByWordWrapping];
	CGFloat height = textSize.height;
	if (message.imageAttachment != nil) {
		height += 72.0f;
	}
	return MAX(72.0f, height + 34.0f);
}

+ (NSString *)base64StringForImage:(UIImage *)image {
	if (image == nil) {
		return nil;
	}

	NSData *jpegData = UIImageJPEGRepresentation(image, 0.75f);
	if ([jpegData length] == 0) {
		return nil;
	}
	return [(id)jpegData base64Encoding];
}

+ (CGMessage *)assistantMessageWithText:(NSString *)text {
	return [self messageWithText:text role:@"assistant"];
}

+ (CGMessage *)assistantMessageWithText:(NSString *)text image:(UIImage *)image {
	CGSize size = CGSizeZero;
	(void)size;
	CGMessage *message = [self messageWithText:text role:@"assistant"];
	message.imageAttachment = image;
	return message;
}

+ (CGMessage *)localMessageWithText:(NSString *)messageText {
	return [self messageWithText:messageText role:@"user"];
}

+ (NSString *)extractErrorMessageFromResponseData:(NSData *)data fallback:(NSString *)fallback {
	if (data == nil || [data length] == 0) {
		return fallback;
	}

	NSError *jsonError = nil;
	id parsedObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
	if (jsonError != nil || ![parsedObject isKindOfClass:[NSDictionary class]]) {
		return fallback;
	}

	NSDictionary *responseDictionary = (NSDictionary *)parsedObject;
	NSDictionary *errorMessage = [responseDictionary objectForKey:@"error"];
	if ([errorMessage isKindOfClass:[NSDictionary class]]) {
		NSString *message = [self trimmedString:[errorMessage objectForKey:@"message"] fallback:nil];
		if ([message length] > 0) {
			return message;
		}
	}

	NSString *message = [self trimmedString:[responseDictionary objectForKey:@"message"] fallback:nil];
	if ([message length] > 0) {
		return message;
	}

	return fallback;
}

@end
