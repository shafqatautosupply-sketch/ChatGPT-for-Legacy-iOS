#import <Foundation/Foundation.h>

@class AGMessage;

/// Provider profiles (name / base URL / model / key), system prompt and request
/// helpers. Foundation-only: rendering lives in AGMessageRenderer.
@interface AGProviderConfig : NSObject

+ (void)registerProviderDefaults;
+ (NSString *)providerDisplayName;
+ (NSString *)currentAPIKey;
+ (NSString *)configuredBaseURL;
+ (NSString *)configuredChatModel;
+ (NSString *)defaultSystemPrompt;
+ (NSString *)configuredSystemPrompt;
+ (void)saveSystemPrompt:(NSString *)prompt;
+ (NSString *)storedValueForKey:(NSString *)key fallback:(NSString *)fallback;

+ (NSArray *)providerProfiles;
+ (NSDictionary *)activeProviderProfile;
+ (NSString *)activeProviderProfileIdentifier;
+ (void)saveActiveProviderProfileWithValues:(NSDictionary *)values;
+ (void)createProviderProfileWithValues:(NSDictionary *)values;
+ (void)activateProviderProfileWithIdentifier:(NSString *)identifier;
+ (void)updateProviderProfileWithIdentifier:(NSString *)identifier values:(NSDictionary *)values;
+ (void)deleteProviderProfileWithIdentifier:(NSString *)identifier;

+ (NSURL *)configuredChatCompletionURL;
+ (void)applyAuthorizationHeadersToRequest:(NSMutableURLRequest *)request withAPIKey:(NSString *)key;

/// Optional `generationConfig`. Empty by default: the original forced
/// thinkingLevel=HIGH on every agent request, which is rejected by Gemini 2.5
/// models and bills maximum reasoning tokens on every step. Opt in with the
/// hidden defaults `ag_thinking_level` (Gemini 3: minimal/low/medium/high) or
/// `ag_thinking_budget` (Gemini 2.5: token count, -1 = dynamic, 0 = off).
+ (NSDictionary *)generationConfigForCurrentModel;

/// A local notice (errors, status). Shown and saved, never sent to the model.
+ (AGMessage *)localNoticeWithText:(NSString *)text;
+ (AGMessage *)assistantMessageWithText:(NSString *)text;
+ (NSString *)extractErrorMessageFromResponseData:(NSData *)data fallback:(NSString *)fallback;

@end
