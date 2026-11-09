#import <Foundation/Foundation.h>

/// One entry in a conversation. Foundation-only on purpose (no UIKit) so the
/// context builder and storage layers can be unit-tested off-device.
@interface AGMessage : NSObject {
@private
	NSString *_role;
	NSString *_author;
	NSString *_content;
	NSString *_toolCallID;
	NSString *_toolName;
	NSArray *_toolCalls;
	BOOL _localOnly;
	BOOL _compacted;
	BOOL _omitted;
	NSString *_cachedDisplayText;
	NSAttributedString *_cachedSegment;
	NSUInteger _cachedSegmentStyle;
	double _cachedSegmentHeight;
	double _cachedHeightWidth;
}

/// "user", "assistant", "tool" or "system".
@property (nonatomic, retain) NSString *role;
@property (nonatomic, retain) NSString *author;
@property (nonatomic, copy) NSString *content;

/// Tool-calling metadata (Gemini function calls / responses).
@property (nonatomic, retain) NSString *toolCallID;
@property (nonatomic, retain) NSString *toolName;
@property (nonatomic, retain) NSArray *toolCalls;

/// Local-only notices (network errors, "API key missing", ...). They are shown
/// and saved but are NEVER sent back to the model: they cost tokens and made the
/// model "remember" its own error messages as if it had said them.
@property (nonatomic, assign) BOOL localOnly;

/// Set by the context builder once this message's bulky payload (tool output or
/// file contents in a function call) has been shrunk for the model. The flag is
/// persisted so the same message is always shrunk the same way; that keeps the
/// request prefix byte-stable, which is what makes Gemini's implicit prompt
/// caching (discounted repeated-prefix tokens) actually kick in.
@property (nonatomic, assign) BOOL compacted;

/// Set when a whole old turn was dropped from the model's context (the chat UI
/// and saved history still show it). Persisted for the same cache-stability reason.
@property (nonatomic, assign) BOOL omitted;

/// Render caches owned by AGMessageRenderer. Never persisted.
@property (nonatomic, retain) NSString *cachedDisplayText;
@property (nonatomic, retain) NSAttributedString *cachedSegment;
@property (nonatomic, assign) NSUInteger cachedSegmentStyle;
/// Measured height of cachedSegment at cachedHeightWidth (0 = not measured yet).
@property (nonatomic, assign) double cachedSegmentHeight;
@property (nonatomic, assign) double cachedHeightWidth;

+ (AGMessage *)messageWithRole:(NSString *)role content:(NSString *)content;

@end
