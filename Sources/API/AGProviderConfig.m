#import "AGProviderConfig.h"
#import "AGMessage.h"

static NSString * const AGProviderProfilesKey = @"providerProfiles";
static NSString * const AGActiveProviderProfileIDKey = @"activeProviderProfileID";
static NSString * const AGLegacyActiveProfileIDKey = @"agent_activeProviderProfileID";
static NSString * const AGSystemPromptKey = @"systemPrompt";
static NSString * const AGDefaultBaseURL = @"https://generativelanguage.googleapis.com";
static NSString * const AGDefaultModel = @"gemini-2.5-flash";

// NOTE: the old in-memory caches (profiles, active profile, prompt) are gone.
// They were released on the main thread while the agent thread was reading them,
// and NSUserDefaults is already an in-memory cache.

@implementation AGProviderConfig

+ (NSString *)defaultSystemPrompt {
	return @"You are a concise, helpful assistant in a legacy iOS app. Prefer clear, direct answers. "
		@"When working with files: locate them with `ls` or `find . -name '<name>'` before reading; read only the line ranges you need; "
		@"change existing files with editFile (small exact replacements) instead of rewriting them with writeFile; "
		@"chain related shell commands with && to save steps. Do not repeat file contents back to the user.";
}

+ (NSString *)trimmedString:(NSString *)value fallback:(NSString *)fallback {
	if (![value isKindOfClass:[NSString class]]) return fallback;
	NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return ([trimmed length] == 0) ? fallback : trimmed;
}

#pragma mark - Profiles

/// Builds a profile dictionary. The identifier is ALWAYS the one passed in: it
/// used to be re-derived from "name|baseURL", so two profiles with the same
/// name and URL (typical: two keys or two models on Gemini) collided, and
/// renaming the active profile orphaned it.
+ (NSDictionary *)profileDictionaryFromValues:(NSDictionary *)values identifier:(NSString *)identifier {
	return [NSDictionary dictionaryWithObjectsAndKeys:
		identifier, @"identifier",
		[self trimmedString:[values objectForKey:@"providerName"] fallback:@"Google Gemini"], @"providerName",
		[self trimmedString:[values objectForKey:@"baseURL"] fallback:AGDefaultBaseURL], @"baseURL",
		[self trimmedString:[values objectForKey:@"c-aiModel"] fallback:AGDefaultModel], @"c-aiModel",
		[self trimmedString:[values objectForKey:@"apiKey"] fallback:@""], @"apiKey",
		nil];
}

+ (NSString *)newIdentifier {
	return [NSString stringWithFormat:@"profile-%08x%08x", arc4random(), arc4random()];
}

+ (NSDictionary *)factoryValues {
	return [NSDictionary dictionaryWithObjectsAndKeys:@"Google Gemini", @"providerName", AGDefaultBaseURL, @"baseURL", AGDefaultModel, @"c-aiModel", @"", @"apiKey", nil];
}

+ (void)registerProviderDefaults {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *configPath = [[NSBundle mainBundle] pathForResource:@"ProviderConfig" ofType:@"plist"];
	NSDictionary *bundleDefaults = (configPath != nil) ? [NSDictionary dictionaryWithContentsOfFile:configPath] : nil;
	NSMutableDictionary *registered = [NSMutableDictionary dictionaryWithDictionary:bundleDefaults];
	[registered setObject:[self defaultSystemPrompt] forKey:AGSystemPromptKey];
	[defaults registerDefaults:registered];

	NSArray *stored = [defaults objectForKey:AGProviderProfilesKey];
	if (![stored isKindOfClass:[NSArray class]] || [stored count] == 0) {
		NSDictionary *initial = [self profileDictionaryFromValues:[self factoryValues] identifier:@"default-profile"];
		[defaults setObject:[NSArray arrayWithObject:initial] forKey:AGProviderProfilesKey];
		[defaults setObject:@"default-profile" forKey:AGActiveProviderProfileIDKey];
	} else {
		// One-time repair of profiles saved by older versions: identical "name|url"
		// identifiers made the second profile unselectable. Give duplicates new ids.
		NSMutableArray *repaired = [NSMutableArray array];
		NSMutableSet *seen = [NSMutableSet set];
		BOOL changed = NO;
		for (NSDictionary *profile in stored) {
			if (![profile isKindOfClass:[NSDictionary class]]) { changed = YES; continue; }
			NSString *identifier = [profile objectForKey:@"identifier"];
			if (![identifier isKindOfClass:[NSString class]] || [identifier length] == 0 || [seen containsObject:identifier]) {
				NSMutableDictionary *fixed = [NSMutableDictionary dictionaryWithDictionary:profile];
				[fixed setObject:[self newIdentifier] forKey:@"identifier"];
				[repaired addObject:fixed];
				changed = YES;
			} else {
				[seen addObject:identifier];
				[repaired addObject:profile];
			}
		}
		if (changed) [defaults setObject:repaired forKey:AGProviderProfilesKey];
	}
	[defaults synchronize];
}

+ (NSArray *)providerProfiles {
	NSArray *profiles = [[NSUserDefaults standardUserDefaults] objectForKey:AGProviderProfilesKey];
	return [profiles isKindOfClass:[NSArray class]] ? profiles : [NSArray array];
}

+ (NSString *)activeProviderProfileIdentifier {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:AGActiveProviderProfileIDKey] ?: [defaults objectForKey:AGLegacyActiveProfileIDKey];
}

+ (NSDictionary *)activeProviderProfile {
	NSString *activeIdentifier = [self activeProviderProfileIdentifier];
	NSArray *profiles = [self providerProfiles];
	for (NSDictionary *profile in profiles) {
		if ([[profile objectForKey:@"identifier"] isEqualToString:activeIdentifier]) return profile;
	}
	return ([profiles count] > 0) ? [profiles objectAtIndex:0] : [NSDictionary dictionary];
}

+ (void)persistProfiles:(NSArray *)profiles activeIdentifier:(NSString *)activeIdentifier {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:profiles forKey:AGProviderProfilesKey];
	if ([activeIdentifier length] > 0) [defaults setObject:activeIdentifier forKey:AGActiveProviderProfileIDKey];
	[defaults removeObjectForKey:AGLegacyActiveProfileIDKey];
	[defaults synchronize];
}

+ (void)saveActiveProviderProfileWithValues:(NSDictionary *)values {
	NSString *activeIdentifier = [self activeProviderProfileIdentifier];
	NSString *identifier = ([activeIdentifier length] > 0) ? activeIdentifier : @"default-profile";
	[self updateProviderProfileWithIdentifier:identifier values:values createIfMissing:YES];
}

+ (void)createProviderProfileWithValues:(NSDictionary *)values {
	NSMutableArray *profiles = [NSMutableArray arrayWithArray:[self providerProfiles]];
	NSDictionary *profile = [self profileDictionaryFromValues:values identifier:[self newIdentifier]];
	[profiles addObject:profile];
	[self persistProfiles:profiles activeIdentifier:[profile objectForKey:@"identifier"]];
}

+ (void)activateProviderProfileWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) return;
	[self persistProfiles:[self providerProfiles] activeIdentifier:identifier];
}

+ (void)updateProviderProfileWithIdentifier:(NSString *)identifier values:(NSDictionary *)values {
	[self updateProviderProfileWithIdentifier:identifier values:values createIfMissing:NO];
}

+ (void)updateProviderProfileWithIdentifier:(NSString *)identifier values:(NSDictionary *)values createIfMissing:(BOOL)create {
	if ([identifier length] == 0) return;
	NSMutableArray *profiles = [NSMutableArray arrayWithArray:[self providerProfiles]];
	NSDictionary *updated = [self profileDictionaryFromValues:values identifier:identifier]; // identifier unchanged
	for (NSUInteger i = 0; i < [profiles count]; i++) {
		if ([[[profiles objectAtIndex:i] objectForKey:@"identifier"] isEqualToString:identifier]) {
			[profiles replaceObjectAtIndex:i withObject:updated];
			[self persistProfiles:profiles activeIdentifier:[self activeProviderProfileIdentifier]];
			return;
		}
	}
	if (create) {
		[profiles addObject:updated];
		[self persistProfiles:profiles activeIdentifier:identifier];
	}
}

+ (void)deleteProviderProfileWithIdentifier:(NSString *)identifier {
	if ([identifier length] == 0) return;
	NSMutableArray *profiles = [NSMutableArray arrayWithArray:[self providerProfiles]];
	for (NSInteger i = (NSInteger)[profiles count] - 1; i >= 0; i--) {
		if ([[[profiles objectAtIndex:(NSUInteger)i] objectForKey:@"identifier"] isEqualToString:identifier]) [profiles removeObjectAtIndex:(NSUInteger)i];
	}
	NSString *active = [self activeProviderProfileIdentifier];
	if ([profiles count] == 0) {
		NSDictionary *fallback = [self profileDictionaryFromValues:[self factoryValues] identifier:@"default-profile"];
		[profiles addObject:fallback];
		active = @"default-profile";
	} else if ([active isEqualToString:identifier] || active == nil) {
		active = [[profiles objectAtIndex:0] objectForKey:@"identifier"];
	}
	[self persistProfiles:profiles activeIdentifier:active];
}

#pragma mark - Values

+ (NSString *)providerDisplayName { return [self trimmedString:[[self activeProviderProfile] objectForKey:@"providerName"] fallback:@"Google Gemini"]; }
+ (NSString *)storedValueForKey:(NSString *)key fallback:(NSString *)fallback { return [self trimmedString:[[self activeProviderProfile] objectForKey:key] fallback:fallback]; }

+ (NSString *)currentAPIKey {
	NSString *key = [self trimmedString:[[self activeProviderProfile] objectForKey:@"apiKey"] fallback:nil];
	return [key isEqualToString:@"PASTE_API_KEY_HERE"] ? nil : key;
}

+ (NSString *)configuredBaseURL {
	NSString *base = [self trimmedString:[[self activeProviderProfile] objectForKey:@"baseURL"] fallback:AGDefaultBaseURL];
	while ([base hasSuffix:@"/"]) base = [base substringToIndex:[base length] - 1];
	return base;
}

+ (NSString *)configuredChatModel { return [self trimmedString:[[self activeProviderProfile] objectForKey:@"c-aiModel"] fallback:AGDefaultModel]; }

+ (NSString *)configuredSystemPrompt {
	return [self trimmedString:[[NSUserDefaults standardUserDefaults] objectForKey:AGSystemPromptKey] fallback:@""];
}

+ (void)saveSystemPrompt:(NSString *)prompt {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:[self trimmedString:prompt fallback:@""] forKey:AGSystemPromptKey];
	[defaults synchronize];
}

+ (NSURL *)configuredChatCompletionURL {
	NSString *model = [self configuredChatModel];
	NSString *escapedModel = [model stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: model;
	return [NSURL URLWithString:[NSString stringWithFormat:@"%@/v1beta/models/%@:generateContent", [self configuredBaseURL], escapedModel]];
}

+ (void)applyAuthorizationHeadersToRequest:(NSMutableURLRequest *)request withAPIKey:(NSString *)key {
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	if ([key length] > 0) [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
}

+ (NSDictionary *)generationConfigForCurrentModel {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *level = [defaults stringForKey:@"ag_thinking_level"];
	id budget = [defaults objectForKey:@"ag_thinking_budget"];
	NSMutableDictionary *thinking = [NSMutableDictionary dictionary];
	if ([level length] > 0) [thinking setObject:[level lowercaseString] forKey:@"thinkingLevel"];
	if (budget != nil && [budget respondsToSelector:@selector(integerValue)]) [thinking setObject:[NSNumber numberWithInteger:[budget integerValue]] forKey:@"thinkingBudget"];
	if ([thinking count] == 0) return nil;
	return [NSDictionary dictionaryWithObject:thinking forKey:@"thinkingConfig"];
}

#pragma mark - Messages

+ (AGMessage *)assistantMessageWithText:(NSString *)text {
	AGMessage *message = [AGMessage messageWithRole:@"assistant" content:text];
	message.author = [self providerDisplayName];
	return message;
}

+ (AGMessage *)localNoticeWithText:(NSString *)text {
	AGMessage *message = [AGMessage messageWithRole:@"assistant" content:text];
	message.author = [self providerDisplayName];
	message.localOnly = YES;
	return message;
}

+ (NSString *)extractErrorMessageFromResponseData:(NSData *)data fallback:(NSString *)fallback {
	if ([data length] == 0) return fallback;
	id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![parsed isKindOfClass:[NSDictionary class]]) return fallback;
	NSDictionary *error = [parsed objectForKey:@"error"];
	if ([error isKindOfClass:[NSDictionary class]]) {
		NSString *message = [self trimmedString:[error objectForKey:@"message"] fallback:nil];
		if ([message length] > 0) return message;
	}
	NSString *message = [self trimmedString:[parsed objectForKey:@"message"] fallback:nil];
	return ([message length] > 0) ? message : fallback;
}

@end
