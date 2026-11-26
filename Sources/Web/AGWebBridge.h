#import <Foundation/Foundation.h>

/// Posted (main thread) by the chat screen when the chat on screen is replaced: new chat, another
/// chat opened. Lets the web page reload its transcript.
extern NSString * const AGWebConversationChangedNotification;

/// What the web page may do to the chat on the phone. The chat screen implements this, so the
/// phone and every browser look at ONE transcript: a message sent from the web page appears on
/// the phone and the other way round. Every method is called on the MAIN thread.
///
/// Deliberately small. The web page cannot read or change settings, API keys, the system prompt
/// or the guardrails, and it does not answer approval questions: those are asked on the phone.
@protocol AGWebBridge <NSObject>

/// Keys: "conversation" (id), "reset" (BOOL: the client must drop what it has), "total" (message
/// count), "messages" (array from AGWebAPI +dictionaryForMessage:..., with absolute "i"), "running",
/// "agent" (Agent Mode on), "provider", "model".
/// `known` is the chat id the client already has and `index` how many of its messages it has;
/// when the chat differs, or index is out of range, answer with reset = YES and the newest messages.
- (NSDictionary *)webSnapshotKnownConversation:(NSString *)known fromIndex:(NSUInteger)index;

/// Sends `text` as the user. NO with a readable reason when a task is already running.
- (BOOL)webSendText:(NSString *)text error:(NSString **)error;
- (void)webStop;
- (void)webStartNewConversation;
- (BOOL)webOpenConversation:(NSString *)identifier;

@end
