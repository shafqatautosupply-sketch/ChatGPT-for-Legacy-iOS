#import <UIKit/UIKit.h>

@class AGMessage;

/// Turns one AGMessage into the attributed text block shown in the chat view.
///
/// Everything here is computed once per message and cached on the message
/// (display text, attributed segment, measured height), so scrolling, appending
/// a message and rebuilding the log never re-run regexes or text layout for old
/// messages. Styling (colored role labels, monospaced tool output, spacing) is
/// just attributes on the same string: no extra views, no extra layout passes.
@interface AGMessageRenderer : NSObject

/// Cleaned text for a message: <think> blocks removed, JSON error bodies
/// unwrapped, tool calls summarised, very long tool output clipped for display
/// (the model still receives the full, separately-limited output).
+ (NSString *)displayTextForMessage:(AGMessage *)message;

/// Label + body block for the message, cached per style.
+ (NSAttributedString *)segmentForMessage:(AGMessage *)message terminal:(BOOL)terminal markdown:(BOOL)markdown;

/// Height of `segment` at `width`, cached on the message.
+ (double)heightForMessage:(AGMessage *)message segment:(NSAttributedString *)segment width:(CGFloat)width;

+ (UIFont *)terminalFont;

@end
