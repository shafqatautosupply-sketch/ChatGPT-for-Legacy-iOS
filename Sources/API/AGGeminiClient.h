#import <Foundation/Foundation.h>

extern NSString * const AGAPIResponseNotification;
extern NSString * const AGAPIMessageDidUpdateNotification;
extern NSString * const AGAPIStatusDidChangeNotification;
extern NSString * const AGPureChatModeChangedNotification;
extern NSString * const AGAgentModeChangedNotification;
extern NSString * const AGTerminalModeChangedNotification;
extern NSString * const AGMarkdownModeChangedNotification;

/// userInfo key on AGAPIResponseNotification / AGAPIStatusDidChangeNotification:
/// the run (NSNumber) that produced it. Observers must ignore notifications whose
/// run is no longer `+currentRunID`, otherwise a cancelled or superseded run can
/// write into the wrong chat.
extern NSString * const AGAPIRunUserInfoKey;

@interface AGGeminiClient : NSObject

/// Starts a run: one model request, then (agent mode) tool calls and follow-up
/// requests until the model answers in text. Any older run is cancelled.
+ (void)createChatCompletionWithMessages:(NSArray *)messages;
+ (void)cancelCurrentAgentTask;
+ (NSUInteger)currentRunID;

+ (BOOL)isPureChatModeEnabled;
+ (void)setPureChatModeEnabled:(BOOL)enabled;
+ (BOOL)isAgentModeEnabled;
+ (void)setAgentModeEnabled:(BOOL)enabled;
+ (BOOL)isTerminalModeEnabled;
+ (void)setTerminalModeEnabled:(BOOL)enabled;
+ (BOOL)isMarkdownEnabled;
+ (void)setMarkdownEnabled:(BOOL)enabled;

/// Token usage reported by the API for the last request (prompt/cached/output/thoughts).
+ (NSDictionary *)lastUsage;

@end
