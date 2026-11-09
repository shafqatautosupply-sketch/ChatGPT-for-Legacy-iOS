#import "AGAgentTools.h"
#import "AGGuardrails.h"
#import "AGShellRunner.h"
#import "AGTextUtil.h"
#include <string.h>
#include <sys/stat.h>

static const unsigned long long AGMaxReadBytes = 4ULL * 1024 * 1024;
static const NSUInteger AGMaxWriteBytes = 2 * 1024 * 1024;
static const NSUInteger AGMaxLineChars = 500;

static NSDictionary *AGProp(NSString *type, NSString *description) {
	return [NSDictionary dictionaryWithObjectsAndKeys:type, @"type", description, @"description", nil];
}

static NSDictionary *AGTool(NSString *name, NSString *description, NSDictionary *props, NSArray *required) {
	return [NSDictionary dictionaryWithObjectsAndKeys:
		name, @"name", description, @"description",
		[NSDictionary dictionaryWithObjectsAndKeys:@"OBJECT", @"type", props, @"properties", required, @"required", nil], @"parameters",
		nil];
}

@implementation AGAgentTools

#pragma mark - Declarations

+ (NSArray *)toolDeclarations {
	NSArray *sorted = [[[AGGuardrails allowedBinaries] allObjects] sortedArrayUsingSelector:@selector(compare:)];
	NSString *shellDescription = [NSString stringWithFormat:
		@"Run a command in the workspace (no shell). Allowed: %@. Supports quotes, globs (*.m), cd, and 'a && b' chains. No pipes, redirects (use writeFile/editFile), ; or $() expansion. Paths must stay inside the workspace/Theos dir. Shows [exit code N] on failure.",
		[sorted componentsJoinedByString:@" "]];

	NSDictionary *shell = AGTool(@"runShellCommand", shellDescription,
		[NSDictionary dictionaryWithObject:AGProp(@"STRING", @"Command line, e.g. \"cd proj && make package\"") forKey:@"command"],
		[NSArray arrayWithObject:@"command"]);

	NSDictionary *write = AGTool(@"writeFile", @"Create or overwrite a text file (parent folders are created). For small changes to an existing file prefer editFile.",
		[NSDictionary dictionaryWithObjectsAndKeys:
			AGProp(@"STRING", @"Path relative to the workspace"), @"filepath",
			AGProp(@"STRING", @"Full file content"), @"content", nil],
		[NSArray arrayWithObjects:@"filepath", @"content", nil]);

	NSDictionary *edit = AGTool(@"editFile", @"Replace exact text in an existing file. old_text must match exactly once (include surrounding lines to make it unique) unless replace_all is true.",
		[NSDictionary dictionaryWithObjectsAndKeys:
			AGProp(@"STRING", @"Path relative to the workspace"), @"filepath",
			AGProp(@"STRING", @"Exact text to find"), @"old_text",
			AGProp(@"STRING", @"Replacement text"), @"new_text",
			AGProp(@"BOOLEAN", @"Replace every occurrence (default false)"), @"replace_all", nil],
		[NSArray arrayWithObjects:@"filepath", @"old_text", @"new_text", nil]);

	NSDictionary *read = AGTool(@"readFile", @"Read a text file with line numbers. Returns up to ~200 lines or the output budget; the header tells you where to continue.",
		[NSDictionary dictionaryWithObjectsAndKeys:
			AGProp(@"STRING", @"Path relative to the workspace"), @"filepath",
			AGProp(@"INTEGER", @"First line, 1-based (optional)"), @"line_start",
			AGProp(@"INTEGER", @"Last line (optional)"), @"line_end", nil],
		[NSArray arrayWithObject:@"filepath"]);

	NSArray *declarations = [NSArray arrayWithObjects:shell, read, write, edit, nil];
	return [NSArray arrayWithObject:[NSDictionary dictionaryWithObject:declarations forKey:@"functionDeclarations"]];
}

#pragma mark - Output clipping

+ (NSUInteger)toolOutputLimit {
	NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:@"agent_tool_output_limit"];
	if (saved < 1000) return 8000;
	return (NSUInteger)MIN(saved, 60000);
}

+ (NSString *)clipText:(NSString *)text toLimit:(NSUInteger)limit tailFraction:(double)tailFraction {
	if ([text length] <= limit || limit < 200) return text;

	NSUInteger tailLength = (NSUInteger)(limit * tailFraction);
	NSUInteger headLength = limit - tailLength;
	NSUInteger length = [text length];

	NSRange headEnd = [text rangeOfComposedCharacterSequenceAtIndex:headLength - 1];
	headLength = NSMaxRange(headEnd);
	NSString *head = [text substringToIndex:headLength];
	NSRange lastNewline = [head rangeOfString:@"\n" options:NSBackwardsSearch];
	if (lastNewline.location != NSNotFound && lastNewline.location > headLength / 2) head = [head substringToIndex:lastNewline.location];

	NSUInteger tailStart = length - tailLength;
	NSRange tailStartRange = [text rangeOfComposedCharacterSequenceAtIndex:tailStart];
	tailStart = tailStartRange.location;
	NSString *tail = [text substringFromIndex:tailStart];
	NSRange firstNewline = [tail rangeOfString:@"\n"];
	if (firstNewline.location != NSNotFound && firstNewline.location < tailLength / 2) tail = [tail substringFromIndex:firstNewline.location + 1];

	NSUInteger omitted = length - [head length] - [tail length];
	return [NSString stringWithFormat:@"%@\n[... %lu characters omitted ...]\n%@", head, (unsigned long)omitted, tail];
}

#pragma mark - Dispatcher

static NSString *AGString(id value) { return [value isKindOfClass:[NSString class]] ? value : nil; }
static NSInteger AGInteger(id value, NSInteger fallback) { return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback; }
static BOOL AGBool(id value) {
	if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
	if ([value isKindOfClass:[NSString class]]) return [[value lowercaseString] isEqualToString:@"true"];
	return NO;
}

+ (NSString *)executeToolNamed:(NSString *)name arguments:(id)arguments workspace:(NSString *)workspace isCancelled:(BOOL (^)(void))cancelled {
	NSDictionary *args = [arguments isKindOfClass:[NSDictionary class]] ? arguments : [NSDictionary dictionary];
	NSString *result = nil;

	if ([name isEqualToString:@"runShellCommand"]) {
		NSString *command = AGString([args objectForKey:@"command"]);
		result = (command == nil) ? @"Error: 'command' (string) is required."
			: [AGShellRunner runCommandLine:command workspace:workspace isCancelled:cancelled];
		// Build output: errors are at the END, so keep the tail.
		result = [AGTextUtil sanitizedText:result]; // no ANSI/control bytes: they crash text layout and waste tokens
		return [self clipText:result toLimit:[self toolOutputLimit] tailFraction:0.7];
	}
	if ([name isEqualToString:@"readFile"]) {
		NSString *path = AGString([args objectForKey:@"filepath"]);
		if (path == nil) return @"Error: 'filepath' (string) is required.";
		return [self readFileAtPath:path lineStart:AGInteger([args objectForKey:@"line_start"], 1) lineEnd:AGInteger([args objectForKey:@"line_end"], 0) workspace:workspace];
	}
	if ([name isEqualToString:@"writeFile"]) {
		NSString *path = AGString([args objectForKey:@"filepath"]);
		id content = [args objectForKey:@"content"];
		if (path == nil || content == nil) return @"Error: 'filepath' and 'content' are required.";
		return [self writeFileAtPath:path content:content workspace:workspace];
	}
	if ([name isEqualToString:@"editFile"]) {
		NSString *path = AGString([args objectForKey:@"filepath"]);
		NSString *oldText = AGString([args objectForKey:@"old_text"]);
		NSString *newText = AGString([args objectForKey:@"new_text"]);
		if (path == nil || oldText == nil || newText == nil) return @"Error: 'filepath', 'old_text' and 'new_text' are required.";
		return [self editFileAtPath:path oldText:oldText newText:newText replaceAll:AGBool([args objectForKey:@"replace_all"]) workspace:workspace];
	}
	return [NSString stringWithFormat:@"Error: Unknown tool function '%@'", name ?: @""];
}

#pragma mark - Reading

+ (NSString *)readFileAtPath:(NSString *)path lineStart:(NSInteger)lineStart lineEnd:(NSInteger)lineEnd workspace:(NSString *)workspace {
	NSString *reason = nil;
	NSString *canonical = [AGGuardrails authorizePath:path relativeTo:workspace forWrite:NO reason:&reason];
	if (canonical == nil) return [NSString stringWithFormat:@"Error: %@", reason];

	struct stat st;
	if (stat([canonical fileSystemRepresentation], &st) != 0) return [NSString stringWithFormat:@"Error: File not found at path '%@'.", path];
	if (S_ISDIR(st.st_mode)) return [NSString stringWithFormat:@"Error: '%@' is a directory; use runShellCommand with ls.", path];
	if ((unsigned long long)st.st_size > AGMaxReadBytes) {
		return [NSString stringWithFormat:@"Error: '%@' is %.1f MB; too large to read whole. Use grep, head or tail through runShellCommand.", path, st.st_size / 1048576.0];
	}

	NSData *data = [NSData dataWithContentsOfFile:canonical];
	if (data == nil) return [NSString stringWithFormat:@"Error: Failed to read file at path '%@'.", path];
	NSUInteger probe = MIN([data length], (NSUInteger)8000);
	if (memchr([data bytes], 0, probe) != NULL) return [NSString stringWithFormat:@"Error: '%@' looks like a binary file.", path];

	NSString *content = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	if (content == nil) content = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
	if (content == nil) return [NSString stringWithFormat:@"Error: Could not decode '%@' as text.", path];

	content = [AGTextUtil sanitizedText:content];
	NSMutableArray *lines = [NSMutableArray arrayWithArray:[content componentsSeparatedByString:@"\n"]];
	if ([lines count] > 1 && [[lines lastObject] length] == 0) [lines removeLastObject]; // trailing newline is not a line
	NSInteger total = (NSInteger)[lines count];

	NSInteger start = (lineStart < 1) ? 1 : lineStart;
	if (start > total) return [NSString stringWithFormat:@"Error: line_start (%ld) exceeds total lines (%ld) of file.", (long)start, (long)total];
	NSInteger wanted = (lineEnd >= start) ? MIN(lineEnd, total) : MIN(start + 199, total);

	// Stop at the output budget on a LINE boundary, so the header below is the
	// truth. (The old code cut mid-line after the header already claimed 200
	// lines, so the model silently skipped the lines in between.)
	NSUInteger budget = [self toolOutputLimit] - 200;
	NSMutableString *body = [NSMutableString string];
	NSInteger shown = start - 1;
	for (NSInteger i = start; i <= wanted; i++) {
		NSString *line = [lines objectAtIndex:(NSUInteger)(i - 1)];
		if ([line length] > AGMaxLineChars) line = [[line substringToIndex:AGMaxLineChars] stringByAppendingString:@" ...[line truncated]"];
		NSString *rendered = [NSString stringWithFormat:@"%ld: %@\n", (long)i, line];
		if ([body length] + [rendered length] > budget && shown >= start) break;
		[body appendString:rendered];
		shown = i;
	}

	NSMutableString *result = [NSMutableString stringWithFormat:@"[%@ | lines %ld-%ld of %ld]\n%@", path, (long)start, (long)shown, (long)total, body];
	if (shown < total) [result appendFormat:@"[%ld more lines; continue with line_start=%ld]", (long)(total - shown), (long)(shown + 1)];
	return result;
}

#pragma mark - Writing

+ (NSString *)writeFileAtPath:(NSString *)path content:(id)content workspace:(NSString *)workspace {
	NSString *reason = nil;
	NSString *canonical = [AGGuardrails authorizePath:path relativeTo:workspace forWrite:YES reason:&reason];
	if (canonical == nil) return [NSString stringWithFormat:@"Error: %@", reason];

	NSString *text = nil;
	if ([content isKindOfClass:[NSString class]]) {
		text = content;
	} else if ([content isKindOfClass:[NSDictionary class]] || [content isKindOfClass:[NSArray class]]) {
		NSData *json = [NSJSONSerialization dataWithJSONObject:content options:NSJSONWritingPrettyPrinted error:nil];
		if (json != nil) text = [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease];
	}
	if (text == nil) text = [content description] ?: @"";

	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	if ([data length] > AGMaxWriteBytes) return [NSString stringWithFormat:@"Error: content is %lu KB; the limit is %lu KB per write. Split the file.", (unsigned long)([data length] / 1024), (unsigned long)(AGMaxWriteBytes / 1024)];

	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir = NO;
	if ([fm fileExistsAtPath:canonical isDirectory:&isDir] && isDir) return [NSString stringWithFormat:@"Error: '%@' is a directory.", path];
	NSString *parent = [canonical stringByDeletingLastPathComponent];
	if (![fm fileExistsAtPath:parent]) [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];

	NSDictionary *oldAttributes = [fm attributesOfItemAtPath:canonical error:nil];
	if (![data writeToFile:canonical atomically:YES]) return @"Error: Failed to write file to disk.";
	NSNumber *mode = [oldAttributes objectForKey:NSFilePosixPermissions];
	if (mode != nil) [fm setAttributes:[NSDictionary dictionaryWithObject:mode forKey:NSFilePosixPermissions] ofItemAtPath:canonical error:nil];

	NSUInteger lineCount = [[text componentsSeparatedByString:@"\n"] count];
	return [NSString stringWithFormat:@"Success: wrote %lu bytes (%lu lines) to %@", (unsigned long)[data length], (unsigned long)lineCount, path];
}

+ (NSString *)editFileAtPath:(NSString *)path oldText:(NSString *)oldText newText:(NSString *)newText replaceAll:(BOOL)replaceAll workspace:(NSString *)workspace {
	if ([oldText length] == 0) return @"Error: old_text must not be empty (use writeFile to create a file).";
	NSString *reason = nil;
	NSString *canonical = [AGGuardrails authorizePath:path relativeTo:workspace forWrite:YES reason:&reason];
	if (canonical == nil) return [NSString stringWithFormat:@"Error: %@", reason];

	NSFileManager *fm = [NSFileManager defaultManager];
	NSDictionary *attributes = [fm attributesOfItemAtPath:canonical error:nil];
	if (attributes == nil) return [NSString stringWithFormat:@"Error: File not found at path '%@'.", path];
	if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > AGMaxReadBytes) return @"Error: file too large to edit.";

	NSData *data = [NSData dataWithContentsOfFile:canonical];
	NSString *content = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	if (content == nil) return [NSString stringWithFormat:@"Error: '%@' is not valid UTF-8 text.", path];

	NSUInteger count = 0;
	NSRange search = NSMakeRange(0, [content length]);
	NSRange firstMatch = NSMakeRange(NSNotFound, 0);
	while (search.length > 0) {
		NSRange found = [content rangeOfString:oldText options:0 range:search];
		if (found.location == NSNotFound) break;
		if (count == 0) firstMatch = found;
		count++;
		search.location = NSMaxRange(found);
		search.length = [content length] - search.location;
	}

	if (count == 0) return [NSString stringWithFormat:@"Error: old_text was not found in %@. Check whitespace and indentation, or readFile the region first.", path];
	if (count > 1 && !replaceAll) return [NSString stringWithFormat:@"Error: old_text appears %lu times in %@. Add surrounding lines to make it unique, or set replace_all=true.", (unsigned long)count, path];

	NSString *updated = replaceAll
		? [content stringByReplacingOccurrencesOfString:oldText withString:newText]
		: [content stringByReplacingCharactersInRange:firstMatch withString:newText];
	NSData *newData = [updated dataUsingEncoding:NSUTF8StringEncoding];
	if (![newData writeToFile:canonical atomically:YES]) return @"Error: Failed to write file to disk.";
	NSNumber *mode = [attributes objectForKey:NSFilePosixPermissions];
	if (mode != nil) [fm setAttributes:[NSDictionary dictionaryWithObject:mode forKey:NSFilePosixPermissions] ofItemAtPath:canonical error:nil];

	return [NSString stringWithFormat:@"Success: edited %@ (%lu replacement%@).", path, (unsigned long)(replaceAll ? count : 1), (replaceAll && count != 1) ? @"s" : @""];
}

@end
