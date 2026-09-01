#import <Foundation/Foundation.h>

@class CGMessage;
@class CGConversation;

@interface LCConversationStore : NSObject

+ (NSString *)conversationsDirectory;
+ (NSString *)pathForConversationIdentifier:(NSString *)identifier;
+ (NSArray *)allConversations;
+ (CGConversation *)conversationWithIdentifier:(NSString *)identifier;
+ (void)saveMessages:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title;
+ (BOOL)deleteConversationWithIdentifier:(NSString *)identifier;
+ (NSString *)nextConversationIdentifier;
+ (NSString *)currentConversationIdentifier;
+ (void)setCurrentConversationIdentifier:(NSString *)identifier;
+ (NSInteger)savedMessageLimit;
+ (void)setSavedMessageLimit:(NSInteger)limit;
+ (NSInteger)loadedMessageLimit;
+ (void)setLoadedMessageLimit:(NSInteger)limit;

// Compression Settings & Logic (Online AI Agent Summarization Only)
+ (BOOL)isAutoCompressionEnabled;
+ (void)setAutoCompressionEnabled:(BOOL)enabled;
+ (NSArray *)compressedMessagesFromMessages:(NSArray *)messages maxRecentCount:(NSInteger)recentCount;
+ (BOOL)compressCurrentConversationInPlace;

@end
