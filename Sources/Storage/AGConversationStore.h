#import <Foundation/Foundation.h>

@class AGMessage;
@class AGConversation;

/// On-disk chat history: one JSON file per conversation in
/// Library/LegacyChatApp/Conversations (path kept so existing chats still load).
@interface AGConversationStore : NSObject

+ (NSString *)conversationsDirectory;
+ (NSString *)pathForConversationIdentifier:(NSString *)identifier;

/// Chat list for the Chats screen, newest first. Uses a small index file, so
/// opening the list does not parse every message of every chat. The returned
/// objects carry title/dates/messageCount only (`messages` is empty).
+ (NSArray *)loadConversations;
+ (NSArray *)allConversations;
/// Full conversation including all messages.
+ (AGConversation *)conversationWithIdentifier:(NSString *)identifier;

/// Synchronous save (serialised with all other store work).
+ (void)saveMessages:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title;
/// Non-blocking save for the UI. Saves are applied in call order and a burst of
/// saves (an agent loop posts two messages per step) is coalesced into one write
/// of the newest snapshot. Previously concurrent writers could finish out of
/// order and leave an OLDER snapshot on disk.
+ (void)saveMessagesAsync:(NSArray *)messages conversationID:(NSString *)conversationID title:(NSString *)title;

+ (BOOL)deleteConversationWithIdentifier:(NSString *)identifier;
+ (NSString *)nextConversationIdentifier;
+ (NSString *)currentConversationIdentifier;
+ (void)setCurrentConversationIdentifier:(NSString *)identifier;

+ (NSInteger)savedMessageLimit;
+ (void)setSavedMessageLimit:(NSInteger)limit;
+ (NSInteger)loadedMessageLimit;
+ (void)setLoadedMessageLimit:(NSInteger)limit;

// Token saver: local, free, deterministic (see AGContextBuilder). It replaced the
// "auto-compress" feature that called the model to summarise the chat on every
// save and then overwrote the saved history.
+ (BOOL)isTokenSaverEnabled;
+ (void)setTokenSaverEnabled:(BOOL)enabled;
/// Estimated tokens of history sent per request before old output is shrunk; 0 = unlimited.
+ (NSUInteger)contextTokenBudget;
+ (NSInteger)configuredContextTokenBudget;
+ (void)setConfiguredContextTokenBudget:(NSInteger)budget;

@end
