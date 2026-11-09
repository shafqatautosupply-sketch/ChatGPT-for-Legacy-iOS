#import <Foundation/Foundation.h>

/// Text clean-up for anything that ends up in the chat view or in tool results.
@interface AGTextUtil : NSObject

/// Removes what a text view cannot lay out safely and what only wastes tokens:
/// ANSI escape sequences, NUL and other control characters (tab and newline are kept),
/// C1 controls, BOM and object-replacement characters. CR and CRLF become LF.
+ (NSString *)sanitizedText:(NSString *)text;

/// YES if every character is printable ASCII (or tab/newline). Such text can be set
/// in a monospaced font without any glyph fallback.
+ (BOOL)isPlainASCII:(NSString *)text;

@end
