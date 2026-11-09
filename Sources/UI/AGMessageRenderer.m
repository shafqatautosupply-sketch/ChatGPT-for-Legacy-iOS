#import "AGMessageRenderer.h"
#import "AGMessage.h"
#import "AGTextUtil.h"

static const NSUInteger AGDisplayToolHead = 700;
static const NSUInteger AGDisplayToolTail = 1500;

#pragma mark - Cached regular expressions (compiling them per message was a hot spot)

static NSRegularExpression *AGRegex(NSString *pattern, NSRegularExpressionOptions options) {
	return [[NSRegularExpression alloc] initWithPattern:pattern options:options error:nil]; // intentionally kept for the process lifetime
}

static NSRegularExpression *AGThinkRegex(void) {
	static NSRegularExpression *re = nil; static dispatch_once_t once;
	dispatch_once(&once, ^{ re = AGRegex(@"<think>([\\s\\S]*?)</think>", NSRegularExpressionCaseInsensitive); });
	return re;
}
static NSRegularExpression *AGFenceRegex(void) {
	static NSRegularExpression *re = nil; static dispatch_once_t once;
	// ```lang\n ... ```   (language tag may contain + - . # like c++ / objective-c; closing fence optional)
	dispatch_once(&once, ^{ re = AGRegex(@"```[^\\n`]*\\n([\\s\\S]*?)(?:```|\\z)", 0); });
	return re;
}
static NSRegularExpression *AGInlineRegex(void) {
	static NSRegularExpression *re = nil; static dispatch_once_t once;
	// 1 `code`   2 **bold**   3 *italic*   4 ~~strike~~   5 [text](   6 url)
	dispatch_once(&once, ^{
		re = AGRegex(@"`([^`\\n]+)`|\\*\\*([^*\\n]+?)\\*\\*|(?<![*\\w])\\*(?![\\s*])([^*\\n]+?)(?<![\\s*])\\*(?![*\\w])|~~([^~\\n]+?)~~|\\[([^\\]\\n]+)\\]\\((https?://[^)\\s]+)\\)", 0);
	});
	return re;
}
static NSRegularExpression *AGHeaderRegex(void) {
	static NSRegularExpression *re = nil; static dispatch_once_t once;
	dispatch_once(&once, ^{ re = AGRegex(@"^(#{1,4})\\s+(.+)$", 0); });
	return re;
}
static NSRegularExpression *AGBulletRegex(void) {
	static NSRegularExpression *re = nil; static dispatch_once_t once;
	dispatch_once(&once, ^{ re = AGRegex(@"^(\\s*)[-*+]\\s+(.*)$", 0); });
	return re;
}

#pragma mark - Colors

static UIColor *AGRGB(CGFloat r, CGFloat g, CGFloat b) { return [UIColor colorWithRed:r green:g blue:b alpha:1.0f]; }

@implementation AGMessageRenderer

+ (UIFont *)terminalFont {
	UIFont *font = [UIFont fontWithName:@"Menlo" size:13.0f];
	if (font == nil) font = [UIFont fontWithName:@"Courier" size:13.0f];
	if (font == nil) font = [UIFont boldSystemFontOfSize:13.0f];
	return font;
}

#pragma mark - Display text

static NSString *AGClipForDisplay(NSString *text) {
	NSUInteger limit = AGDisplayToolHead + AGDisplayToolTail;
	if ([text length] <= limit + 200) return text;
	NSString *head = [text substringToIndex:AGDisplayToolHead];
	NSString *tail = [text substringFromIndex:[text length] - AGDisplayToolTail];
	return [NSString stringWithFormat:@"%@\n... %lu characters not shown here (the full output was given to the model) ...\n%@",
		head, (unsigned long)([text length] - limit), tail];
}

static NSString *AGToolCallSummary(AGMessage *message) {
	NSMutableArray *lines = [NSMutableArray array];
	for (NSDictionary *call in message.toolCalls) {
		NSDictionary *fn = [call isKindOfClass:[NSDictionary class]] ? [call objectForKey:@"function"] : nil;
		if (![fn isKindOfClass:[NSDictionary class]]) continue;
		NSString *name = [fn objectForKey:@"name"] ?: @"tool";
		NSString *json = [fn objectForKey:@"arguments"];
		NSDictionary *args = nil;
		if ([json isKindOfClass:[NSString class]]) {
			id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
			if ([parsed isKindOfClass:[NSDictionary class]]) args = parsed;
		}
		NSString *detail = nil;
		if ([name isEqualToString:@"runShellCommand"]) detail = [args objectForKey:@"command"];
		else if ([name isEqualToString:@"writeFile"]) detail = [NSString stringWithFormat:@"%@ (%lu chars)", [args objectForKey:@"filepath"] ?: @"?", (unsigned long)[[args objectForKey:@"content"] length]];
		else detail = [args objectForKey:@"filepath"];
		if (![detail isKindOfClass:[NSString class]]) detail = @"";
		detail = [AGTextUtil sanitizedText:detail];
		if ([detail length] > 400) detail = [[detail substringToIndex:400] stringByAppendingString:@"..."];
		[lines addObject:[NSString stringWithFormat:@"> %@ %@", name, detail]];
	}
	return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)computeDisplayText:(AGMessage *)message {
	NSString *raw = [AGTextUtil sanitizedText:(message.content ?: @"")];
	NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	// Call-only assistant turn (new format has no text; old saved chats stored "Tool Call: ...").
	if ([message.toolCalls count] > 0 && ([trimmed length] == 0 || [trimmed hasPrefix:@"Tool Call: "])) {
		return AGToolCallSummary(message);
	}

	// <think>…</think> reasoning from OpenAI-compatible providers is not part of the answer.
	NSRegularExpression *think = AGThinkRegex();
	if ([trimmed rangeOfString:@"<think>" options:NSCaseInsensitiveSearch].location != NSNotFound) {
		trimmed = [[think stringByReplacingMatchesInString:trimmed options:0 range:NSMakeRange(0, [trimmed length]) withTemplate:@""]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}

	// A raw API error body: show just the message.
	if ([trimmed hasPrefix:@"{"] && [trimmed rangeOfString:@"\"error\""].location != NSNotFound) {
		id parsed = [NSJSONSerialization JSONObjectWithData:[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
		NSDictionary *error = [parsed isKindOfClass:[NSDictionary class]] ? [parsed objectForKey:@"error"] : nil;
		NSString *text = [error isKindOfClass:[NSDictionary class]] ? [error objectForKey:@"message"] : nil;
		if ([text length] > 0) trimmed = text;
	}

	// Some providers double-escape: the whole answer arrives on one line with literal "\n".
	// Only repair that case. (Unconditional replacement used to corrupt code such as printf("a\n").)
	if ([trimmed rangeOfString:@"\n"].location == NSNotFound && [trimmed rangeOfString:@"\\n"].location != NSNotFound) {
		trimmed = [trimmed stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
		trimmed = [trimmed stringByReplacingOccurrencesOfString:@"\\t" withString:@"\t"];
	}

	if ([message.role isEqualToString:@"tool"]) trimmed = AGClipForDisplay(trimmed);
	return trimmed;
}

+ (NSString *)displayTextForMessage:(AGMessage *)message {
	NSString *cached = nil;
	@synchronized(message) { cached = message.cachedDisplayText; }
	if (cached != nil) return cached;
	NSString *text = [self computeDisplayText:message] ?: @"";
	@synchronized(message) { message.cachedDisplayText = text; }
	return text;
}

#pragma mark - Markdown (single pass, left to right)

static void AGAppend(NSMutableAttributedString *out, NSString *string, NSDictionary *attrs) {
	if ([string length] == 0) return;
	NSAttributedString *piece = [[NSAttributedString alloc] initWithString:string attributes:attrs];
	[out appendAttributedString:piece];
	[piece release];
}

typedef struct { NSDictionary *base, *bold, *italic, *code, *strike, *link, *dim, *header, *codeBlock; } AGStyles;

static void AGAppendInline(NSMutableAttributedString *out, NSString *line, const AGStyles *s) {
	NSRegularExpression *re = AGInlineRegex();
	NSUInteger cursor = 0, length = [line length];
	for (NSTextCheckingResult *m in [re matchesInString:line options:0 range:NSMakeRange(0, length)]) {
		AGAppend(out, [line substringWithRange:NSMakeRange(cursor, m.range.location - cursor)], s->base);
		if ([m rangeAtIndex:1].location != NSNotFound)      AGAppend(out, [line substringWithRange:[m rangeAtIndex:1]], s->code);
		else if ([m rangeAtIndex:2].location != NSNotFound) AGAppend(out, [line substringWithRange:[m rangeAtIndex:2]], s->bold);
		else if ([m rangeAtIndex:3].location != NSNotFound) AGAppend(out, [line substringWithRange:[m rangeAtIndex:3]], s->italic);
		else if ([m rangeAtIndex:4].location != NSNotFound) AGAppend(out, [line substringWithRange:[m rangeAtIndex:4]], s->strike);
		else if ([m rangeAtIndex:5].location != NSNotFound) {
			AGAppend(out, [line substringWithRange:[m rangeAtIndex:5]], s->link);
			AGAppend(out, [NSString stringWithFormat:@" (%@)", [line substringWithRange:[m rangeAtIndex:6]]], s->dim);
		}
		cursor = NSMaxRange(m.range);
	}
	AGAppend(out, [line substringFromIndex:cursor], s->base);
}

static void AGAppendProse(NSMutableAttributedString *out, NSString *prose, const AGStyles *s) {
	NSArray *lines = [prose componentsSeparatedByString:@"\n"];
	for (NSUInteger i = 0; i < [lines count]; i++) {
		NSString *line = [lines objectAtIndex:i];
		NSRange whole = NSMakeRange(0, [line length]);
		NSTextCheckingResult *header = [AGHeaderRegex() firstMatchInString:line options:0 range:whole];
		if (header != nil) {
			AGAppend(out, [line substringWithRange:[header rangeAtIndex:2]], s->header);
		} else {
			NSTextCheckingResult *bullet = [AGBulletRegex() firstMatchInString:line options:0 range:whole];
			if (bullet != nil) {
				AGAppend(out, [[line substringWithRange:[bullet rangeAtIndex:1]] stringByAppendingString:@"• "], s->base);
				AGAppendInline(out, [line substringWithRange:[bullet rangeAtIndex:2]], s);
			} else {
				AGAppendInline(out, line, s);
			}
		}
		if (i + 1 < [lines count]) AGAppend(out, @"\n", s->base);
	}
}

static void AGAppendMarkdown(NSMutableAttributedString *out, NSString *text, const AGStyles *s) {
	NSUInteger cursor = 0;
	for (NSTextCheckingResult *m in [AGFenceRegex() matchesInString:text options:0 range:NSMakeRange(0, [text length])]) {
		AGAppendProse(out, [text substringWithRange:NSMakeRange(cursor, m.range.location - cursor)], s);
		NSString *code = [text substringWithRange:[m rangeAtIndex:1]];
		while ([code hasSuffix:@"\n"]) code = [code substringToIndex:[code length] - 1];
		AGAppend(out, code, s->codeBlock);   // code is never touched by inline rules: `a * b * c` stays intact
		AGAppend(out, @"\n", s->base);
		cursor = NSMaxRange(m.range);
		// swallow one newline after the closing fence so we do not add a blank line
		if (cursor < [text length] && [text characterAtIndex:cursor] == '\n') cursor++;
	}
	AGAppendProse(out, [text substringFromIndex:cursor], s);
}

#pragma mark - Segment

+ (NSAttributedString *)buildSegmentForMessage:(AGMessage *)message terminal:(BOOL)terminal markdown:(BOOL)markdown {
	NSString *role = message.role ?: @"user";
	BOOL isUser = [role isEqualToString:@"user"];
	BOOL isTool = [role isEqualToString:@"tool"];
	BOOL isNotice = message.localOnly;
	BOOL isCall = [message.toolCalls count] > 0 && !isTool;
	NSString *body = [self displayTextForMessage:message];

	NSMutableAttributedString *out = [[[NSMutableAttributedString alloc] init] autorelease];

	if (terminal) {
		// Terminal theme keeps its original look (green on black, ===== banners).
		NSString *divider = @"==================================";
		NSString *label = isUser ? @"[USER >>]" : (isTool ? @"[TOOL OUTPUT >>]" : @"[AGENT >>]");
		NSMutableParagraphStyle *center = [[[NSMutableParagraphStyle alloc] init] autorelease]; center.alignment = NSTextAlignmentCenter;
		NSMutableParagraphStyle *left = [[[NSMutableParagraphStyle alloc] init] autorelease]; left.alignment = NSTextAlignmentLeft;
		UIFont *font = [self terminalFont];
		UIColor *green = AGRGB(0.15f, 0.95f, 0.15f);
		AGAppend(out, [NSString stringWithFormat:@"%@\n%@\n%@\n", divider, label, divider],
			[NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, green, NSForegroundColorAttributeName, center, NSParagraphStyleAttributeName, nil]);
		AGAppend(out, [NSString stringWithFormat:@"%@\n\n", body],
			[NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, green, NSForegroundColorAttributeName, left, NSParagraphStyleAttributeName, nil]);
		return out;
	}

	UIColor *labelColor, *bodyColor;
	NSString *labelText;
	UIFont *bodyFont = [UIFont systemFontOfSize:14.0f];
	// Courier only for pure-ASCII text: for anything else the text view would have to
	// substitute fonts glyph by glyph, which is what the crash report points at.
	BOOL monoSafe = [AGTextUtil isPlainASCII:body];
	if (isNotice)      { labelText = @"NOTICE";    labelColor = AGRGB(0.65f, 0.12f, 0.12f); bodyColor = AGRGB(0.50f, 0.10f, 0.10f); }
	else if (isUser)   { labelText = @"YOU";       labelColor = AGRGB(0.05f, 0.32f, 0.70f); bodyColor = AGRGB(0.05f, 0.16f, 0.38f); }
	else if (isTool)   { labelText = @"TOOL RESULT"; labelColor = AGRGB(0.55f, 0.35f, 0.05f); bodyColor = AGRGB(0.28f, 0.28f, 0.28f); bodyFont = monoSafe ? ([UIFont fontWithName:@"Courier" size:12.0f] ?: bodyFont) : [UIFont systemFontOfSize:13.0f]; }
	else               { labelText = ([message.author length] > 0) ? [message.author uppercaseString] : @"ASSISTANT"; labelColor = AGRGB(0.08f, 0.42f, 0.30f); bodyColor = [UIColor blackColor]; }
	if (isCall) { bodyFont = monoSafe ? ([UIFont fontWithName:@"Courier" size:12.0f] ?: bodyFont) : [UIFont systemFontOfSize:13.0f]; bodyColor = AGRGB(0.45f, 0.28f, 0.04f); }

	NSMutableParagraphStyle *labelStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
	labelStyle.alignment = NSTextAlignmentLeft;
	NSMutableParagraphStyle *bodyStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
	bodyStyle.alignment = NSTextAlignmentLeft;

	AGAppend(out, [labelText stringByAppendingString:@"\n"],
		[NSDictionary dictionaryWithObjectsAndKeys:[UIFont boldSystemFontOfSize:11.0f], NSFontAttributeName, labelColor, NSForegroundColorAttributeName, labelStyle, NSParagraphStyleAttributeName, nil]);

	CGFloat size = [bodyFont pointSize];
	UIFont *mono = monoSafe ? ([UIFont fontWithName:@"Courier" size:size - 1.0f] ?: bodyFont) : bodyFont;
	NSDictionary *base = [NSDictionary dictionaryWithObjectsAndKeys:bodyFont, NSFontAttributeName, bodyColor, NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, nil];

	if (markdown && !isTool && !isCall && !isNotice) {
		AGStyles styles;
		styles.base = base;
		styles.bold = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont boldSystemFontOfSize:size], NSFontAttributeName, bodyColor, NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, nil];
		styles.italic = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont italicSystemFontOfSize:size], NSFontAttributeName, bodyColor, NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, nil];
		styles.code = [NSDictionary dictionaryWithObjectsAndKeys:mono, NSFontAttributeName, AGRGB(0.60f, 0.14f, 0.30f), NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, nil];
		styles.codeBlock = [NSDictionary dictionaryWithObjectsAndKeys:mono, NSFontAttributeName, AGRGB(0.10f, 0.22f, 0.30f), NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, nil];
		styles.strike = [NSDictionary dictionaryWithObjectsAndKeys:bodyFont, NSFontAttributeName, bodyColor, NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, [NSNumber numberWithInt:NSUnderlineStyleSingle], NSStrikethroughStyleAttributeName, nil];
		styles.link = [NSDictionary dictionaryWithObjectsAndKeys:bodyFont, NSFontAttributeName, AGRGB(0.0f, 0.40f, 0.80f), NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, [NSNumber numberWithInt:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName, nil];
		styles.dim = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont systemFontOfSize:size - 2.0f], NSFontAttributeName, AGRGB(0.45f, 0.45f, 0.45f), NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, nil];
		styles.header = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont boldSystemFontOfSize:size + 1.0f], NSFontAttributeName, AGRGB(0.05f, 0.05f, 0.05f), NSForegroundColorAttributeName, bodyStyle, NSParagraphStyleAttributeName, nil];
		AGAppendMarkdown(out, body, &styles);
		AGAppend(out, @"\n\n", base);
	} else {
		AGAppend(out, [body stringByAppendingString:@"\n\n"], base);
	}
	return out;
}

+ (NSAttributedString *)segmentForMessage:(AGMessage *)message terminal:(BOOL)terminal markdown:(BOOL)markdown {
	NSUInteger style = 4 | (terminal ? 1 : 0) | (markdown ? 2 : 0);
	NSAttributedString *cached = nil;
	@synchronized(message) { if (message.cachedSegmentStyle == style) cached = message.cachedSegment; }
	if (cached != nil) return cached;

	NSAttributedString *segment = [self buildSegmentForMessage:message terminal:terminal markdown:markdown];
	@synchronized(message) {
		message.cachedSegment = segment;
		message.cachedSegmentStyle = style;
		message.cachedSegmentHeight = 0;
	}
	return segment;
}

+ (double)heightForMessage:(AGMessage *)message segment:(NSAttributedString *)segment width:(CGFloat)width {
	@synchronized(message) {
		if (message.cachedSegmentHeight > 0 && message.cachedHeightWidth == (double)width && message.cachedSegment == segment) return message.cachedSegmentHeight;
	}
	CGRect rect = [segment boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading context:nil];
	double height = ceil(rect.size.height);
	@synchronized(message) {
		if (message.cachedSegment == segment) { message.cachedSegmentHeight = height; message.cachedHeightWidth = width; }
	}
	return height;
}

@end
