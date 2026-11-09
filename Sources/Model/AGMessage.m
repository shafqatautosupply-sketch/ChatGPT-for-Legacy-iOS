#import "AGMessage.h"

@implementation AGMessage

@synthesize role = _role;
@synthesize author = _author;
@synthesize content = _content;
@synthesize toolCallID = _toolCallID;
@synthesize toolName = _toolName;
@synthesize toolCalls = _toolCalls;
@synthesize localOnly = _localOnly;
@synthesize compacted = _compacted;
@synthesize omitted = _omitted;
@synthesize cachedDisplayText = _cachedDisplayText;
@synthesize cachedSegment = _cachedSegment;
@synthesize cachedSegmentStyle = _cachedSegmentStyle;
@synthesize cachedSegmentHeight = _cachedSegmentHeight;
@synthesize cachedHeightWidth = _cachedHeightWidth;

+ (AGMessage *)messageWithRole:(NSString *)role content:(NSString *)content {
	AGMessage *message = [[[AGMessage alloc] init] autorelease];
	message.role = role;
	message.content = content;
	return message;
}

- (void)setContent:(NSString *)content {
	if (content == _content) return;
	[_content release];
	_content = [content copy];
	// Any render cache is stale once the text changes.
	[_cachedDisplayText release]; _cachedDisplayText = nil;
	[_cachedSegment release]; _cachedSegment = nil;
	_cachedSegmentHeight = 0;
}

- (void)dealloc {
	[_role release];
	[_author release];
	[_content release];
	[_toolCallID release];
	[_toolName release];
	[_toolCalls release];
	[_cachedDisplayText release];
	[_cachedSegment release];
	[super dealloc];
}

@end
