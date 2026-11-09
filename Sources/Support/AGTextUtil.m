#import "AGTextUtil.h"

@implementation AGTextUtil

+ (NSString *)sanitizedText:(NSString *)text {
	NSUInteger length = [text length];
	if (length == 0) return text ?: @"";

	// Fast path: nothing to change (the common case).
	BOOL dirty = NO;
	for (NSUInteger i = 0; i < length && !dirty; i++) {
		unichar c = [text characterAtIndex:i];
		if ((c < 0x20 && c != '\n' && c != '\t') || (c >= 0x7F && c <= 0x9F) || c == 0xFEFF || c == 0xFFFC || c == 0x2028 || c == 0x2029) dirty = YES;
	}
	if (!dirty) return text;

	unichar *buffer = (unichar *)malloc(length * sizeof(unichar));
	if (buffer == NULL) return text;
	NSUInteger out = 0;
	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [text characterAtIndex:i];

		if (c == 0x1B) { // ESC: drop "ESC [ params final" (colors, cursor moves) or ESC + one char
			if (i + 1 < length && [text characterAtIndex:i + 1] == '[') {
				i += 2;
				while (i < length) {
					unichar d = [text characterAtIndex:i];
					if (d >= 0x40 && d <= 0x7E) break;
					i++;
				}
			} else if (i + 1 < length) {
				i++;
			}
			continue;
		}
		if (c == '\r') {
			if (i + 1 < length && [text characterAtIndex:i + 1] == '\n') continue; // CRLF: the LF follows
			buffer[out++] = '\n';
			continue;
		}
		if (c == 0x2028 || c == 0x2029) { buffer[out++] = '\n'; continue; }
		if (c == '\n' || c == '\t') { buffer[out++] = c; continue; }
		if (c < 0x20 || (c >= 0x7F && c <= 0x9F) || c == 0xFEFF || c == 0xFFFC) continue;
		buffer[out++] = c;
	}
	NSString *result = [NSString stringWithCharacters:buffer length:out];
	free(buffer);
	return result;
}

+ (BOOL)isPlainASCII:(NSString *)text {
	NSUInteger length = [text length];
	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [text characterAtIndex:i];
		if (c == '\n' || c == '\t') continue;
		if (c < 0x20 || c > 0x7E) return NO;
	}
	return YES;
}

@end
