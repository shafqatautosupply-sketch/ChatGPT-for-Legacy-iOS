#import <Foundation/Foundation.h>

/// A chat. From the Chats list it carries metadata only (`messages` is empty);
/// +[AGConversationStore conversationWithIdentifier:] returns the full transcript.
@interface AGConversation : NSObject {
@private
	NSString *_uuid;
	NSString *_creationDate;
	NSString *_lastTimeEdited;
	NSString *_title;
	int _messageCount;
	NSMutableArray *_messages;
}

@property (nonatomic, retain) NSString *uuid;
@property (nonatomic, retain) NSString *creationDate;
@property (nonatomic, retain) NSString *lastTimeEdited;
@property (nonatomic, retain) NSString *title;
@property (nonatomic, assign) int messageCount;
@property (nonatomic, retain) NSMutableArray *messages;

@end
