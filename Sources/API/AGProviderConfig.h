#import <Foundation/Foundation.h>

@class AGMessage;

/// Profile `providerType` values. Profiles saved by older versions have no type and are Gemini.
extern NSString * const AGProviderTypeGemini;
extern NSString * const AGProviderTypeOpenAI;

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
+ (NSArray *)providerProfilesOfType:(NSString *)type;
+ (NSString *)providerTypeOfProfile:(NSDictionary *)profile;
+ (NSString *)activeProviderType;
+ (BOOL)isOpenAICompatibleActive;
/// Suggested name / base URL / model for a new profile of `type`.
+ (NSDictionary *)factoryValuesForType:(NSString *)type;
+ (NSDictionary *)activeProviderProfile;
+ (NSString *)activeProviderProfileIdentifier;
+ (void)saveActiveProviderProfileWithValues:(NSDictionary *)values;
+ (void)createProviderProfileWithValues:(NSDictionary *)values;
+ (void)activateProviderProfileWithIdentifier:(NSString *)identifier;
+ (void)updateProviderProfileWithIdentifier:(NSString *)identifier values:(NSDictionary *)values;
+ (void)deleteProviderProfileWithIdentifier:(NSString *)identifier;

+ (NSURL *)configuredChatCompletionURL;
+ (void)applyAuthorizationHeadersToRequest:(NSMutableURLRequest *)request withAPIKey:(NSString *)key;

/// Optional `generationConfig` (Gemini only): the thinking level.
/// Setting (Settings > Model > Thinking, stored in `ag_thinking_level`):
///   auto (default)  Medium on Gemini 3+ Flash-Lite models (at the model's own default, minimal, they stop
///                   early on multi-step agent tasks), nothing for every other model
///   default         send nothing: the model's own default
///   minimal | low | medium | high   sent as thinkingLevel
/// thinkingLevel is only sent to Gemini 3 and newer: Gemini 2.5 rejects it with HTTP 400, so there the
/// setting is ignored. The hidden default `ag_thinking_budget` (Gemini 2.5: token count, -1 = dynamic,
/// 0 = off) is still honoured when no level is sent; level and budget are never sent together.
+ (NSDictionary *)generationConfigForCurrentModel;

/// The choices in menu order: auto, default, minimal, low, medium, high.
+ (NSArray *)thinkingLevelChoices;
/// The stored choice, normalised (unknown or missing = auto).
+ (NSString *)thinkingLevelSetting;
+ (void)setThinkingLevelSetting:(NSString *)choice;
+ (NSString *)displayNameForThinkingLevel:(NSString *)choice;
/// Gemini 3 or newer ("gemini-3-flash-preview", "gemini-3.5-flash-lite", ...). Aliases such as
/// "gemini-flash-latest" are treated as unknown (NO).
+ (BOOL)modelSupportsThinkingLevel:(NSString *)model;
/// What goes on the wire for `choice` and `model`: minimal/low/medium/high, or nil = send no level.
+ (NSString *)effectiveThinkingLevelForChoice:(NSString *)choice model:(NSString *)model;

/// A local notice (errors, status). Shown and saved, never sent to the model.
+ (AGMessage *)localNoticeWithText:(NSString *)text;
+ (AGMessage *)assistantMessageWithText:(NSString *)text;
+ (NSString *)extractErrorMessageFromResponseData:(NSData *)data fallback:(NSString *)fallback;

@end
