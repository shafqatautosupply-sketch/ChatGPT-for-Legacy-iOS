#import <Foundation/Foundation.h>

extern NSString * const LCAPIResponseNotification;
extern NSString * const LCAPIMessageDidUpdateNotification;
extern NSString * const LCAPIStatusDidChangeNotification;
extern NSString * const LCPureChatModeChangedNotification;
extern NSString * const LCAgentModeChangedNotification;
extern NSString * const LCTerminalModeChangedNotification;
extern NSString * const LCMarkdownModeChangedNotification;

@interface CGAPICommunicator : NSObject

+ (void)createChatCompletionWithMessages:(NSArray *)messages;
+ (BOOL)isPureChatModeEnabled;
+ (void)setPureChatModeEnabled:(BOOL)enabled;
+ (BOOL)isAgentModeEnabled;
+ (void)setAgentModeEnabled:(BOOL)enabled;
+ (BOOL)isTerminalModeEnabled;
+ (void)setTerminalModeEnabled:(BOOL)enabled;
+ (BOOL)isMarkdownEnabled;
+ (void)setMarkdownEnabled:(BOOL)enabled;

@end
