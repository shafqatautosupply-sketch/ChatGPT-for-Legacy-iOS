#import "AGApproval.h"
#import "AGGuardrails.h"
#include <stdio.h>
#include <Block.h>

NSString * const AGApprovalAbandonedNotification = @"AGApprovalAbandonedNotification";
NSString * const AGApprovalPendingChangedNotification = @"AGApprovalPendingChangedNotification";

static const NSUInteger AGDetailMaxChars = 700;
static const NSUInteger AGPreviewMaxChars = 420;
static const NSUInteger AGPreviewMaxLines = 12;

/// One pending question. The first answer wins; later ones are ignored.
@interface AGApprovalTicket : NSObject {
	NSInteger _choice;
}
- (BOOL)setChoiceOnce:(NSInteger)choice;
- (NSInteger)choice;   // -1 while nobody has answered
@end

@implementation AGApprovalTicket
- (id)init { self = [super init]; if (self) _choice = -1; return self; }
- (BOOL)setChoiceOnce:(NSInteger)choice {
	@synchronized(self) {
		if (_choice != -1) return NO;
		_choice = choice;
		return YES;
	}
}
- (NSInteger)choice { @synchronized(self) { return _choice; } }
@end

static AGApprovalHandler g_handler = NULL;
static NSMutableSet *g_taskApprovals = nil;
static NSString *g_pendingTitle = nil;   // guarded by @synchronized([AGApproval class])

@implementation AGApproval

#pragma mark - Settings

+ (BOOL)boolDefault:(NSString *)key fallback:(BOOL)fallback {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	return (value != nil && [value respondsToSelector:@selector(boolValue)]) ? [value boolValue] : fallback;
}

+ (BOOL)confirmCodeEnabled { return [self boolDefault:@"agent_confirm_code" fallback:YES]; }
+ (BOOL)confirmDeleteEnabled { return [self boolDefault:@"agent_confirm_delete" fallback:YES]; }

+ (NSTimeInterval)timeout {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_approval_timeout"];
	NSTimeInterval seconds = (value != nil && [value respondsToSelector:@selector(doubleValue)]) ? [value doubleValue] : 600.0;
	if (seconds < 1.0) seconds = 600.0;
	return MIN(seconds, 3600.0);
}

+ (NSString *)pendingTitle {
	@synchronized([AGApproval class]) { return [[g_pendingTitle retain] autorelease]; }
}

+ (void)setPendingTitle:(NSString *)title {
	@synchronized([AGApproval class]) {
		if (title == g_pendingTitle || [title isEqualToString:g_pendingTitle]) return;
		[g_pendingTitle release];
		g_pendingTitle = [title copy];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:AGApprovalPendingChangedNotification object:nil];
}

+ (void)setHandler:(AGApprovalHandler)handler {
	@synchronized(self) {
		AGApprovalHandler old = g_handler;
		g_handler = (handler != NULL) ? Block_copy(handler) : NULL;
		if (old != NULL) Block_release(old);
	}
}

#pragma mark - Which commands are gated

+ (NSSet *)gatedBinaries {
	NSMutableSet *set = [NSMutableSet setWithObjects:@"make", @"python", @"python2", @"python2.7", @"python3", nil];
	id extra = [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_confirm_binaries"];
	if ([extra isKindOfClass:[NSArray class]]) {
		for (id name in extra) if ([name isKindOfClass:[NSString class]] && [name length] > 0) [set addObject:name];
	}
	return set;
}

+ (BOOL)argvNeedsApproval:(NSArray *)argv {
	if ([argv count] == 0 || ![self confirmCodeEnabled]) return NO;
	return [[self gatedBinaries] containsObject:[argv objectAtIndex:0]];
}

#pragma mark - Prompt text

/// Replaces control characters (they break alert layout) and caps the length.
static NSString *AGPlain(NSString *text, NSUInteger maxChars) {
	NSMutableString *out = [NSMutableString stringWithCapacity:MIN([text length], maxChars + 8)];
	for (NSUInteger i = 0; i < [text length] && [out length] < maxChars; i++) {
		unichar c = [text characterAtIndex:i];
		if (c == '\n' || c == '\t') { [out appendString:(c == '\n' ? @"\n" : @" ")]; continue; }
		if (c < 0x20 || (c >= 0x7f && c < 0xa0)) { [out appendString:@" "]; continue; }
		[out appendFormat:@"%C", c];
	}
	if ([text length] > maxChars) [out appendString:@" ..."];
	return out;
}

/// First lines of a file, at most AGPreviewMaxChars / AGPreviewMaxLines. Reads a few KB, never the whole file.
static NSString *AGFilePreview(NSString *path) {
	FILE *file = fopen([path fileSystemRepresentation], "rb");
	if (file == NULL) return nil;
	char buffer[2048];
	size_t got = fread(buffer, 1, sizeof(buffer), file);
	fclose(file);
	if (got == 0) return @"(empty file)";
	NSData *data = [NSData dataWithBytes:buffer length:got];
	NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	if (text == nil) text = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
	if (text == nil) return nil;
	NSArray *lines = [text componentsSeparatedByString:@"\n"];
	NSMutableString *head = [NSMutableString string];
	for (NSUInteger i = 0; i < [lines count] && i < AGPreviewMaxLines; i++) {
		[head appendString:[lines objectAtIndex:i]];
		[head appendString:@"\n"];
	}
	BOOL more = ([lines count] > AGPreviewMaxLines) || got == sizeof(buffer);
	NSString *shown = AGPlain(head, AGPreviewMaxChars);
	shown = [shown stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return more ? [shown stringByAppendingString:@"\n[...more not shown]"] : shown;
}

+ (NSString *)describeArgv:(NSArray *)argv cwd:(NSString *)cwd {
	if ([argv count] == 0) return @"";
	NSString *bin = [argv objectAtIndex:0];
	NSMutableString *text = [NSMutableString string];
	[text appendFormat:@"%@\nIn: %@", AGPlain([argv componentsJoinedByString:@" "], 220), cwd];

	NSString *preview = nil, *previewName = nil;
	if ([bin hasPrefix:@"python"]) {
		for (NSUInteger i = 1; i < [argv count]; i++) {
			NSString *arg = [argv objectAtIndex:i];
			if ([arg isEqualToString:@"-c"] && i + 1 < [argv count]) {
				preview = AGPlain([argv objectAtIndex:i + 1], AGPreviewMaxChars);
				previewName = @"Code";
				break;
			}
			if ([arg hasPrefix:@"-"]) continue;   // a flag, not the script
			NSString *reason = nil;
			NSString *canonical = [AGGuardrails authorizePath:arg relativeTo:cwd forWrite:NO reason:&reason];
			if (canonical != nil) { preview = AGFilePreview(canonical); previewName = [arg lastPathComponent]; }
			break;
		}
		[text appendString:@"\nPython can do anything this app can do, not only what you see below."];
	} else if ([bin isEqualToString:@"make"]) {
		NSArray *names = [NSArray arrayWithObjects:@"Makefile", @"makefile", @"GNUmakefile", nil];
		for (NSString *name in names) {
			NSString *candidate = [cwd stringByAppendingPathComponent:name];
			if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) { preview = AGFilePreview(candidate); previewName = name; break; }
		}
		[text appendString:@"\nA Makefile can run any program."];
	}
	if ([preview length] > 0) [text appendFormat:@"\n--- %@ ---\n%@", previewName, preview];
	return AGPlain(text, AGDetailMaxChars);
}

#pragma mark - Per-task allowances

+ (BOOL)taskAllows:(NSString *)key {
	if (key == nil) return NO;
	@synchronized(self) { return [g_taskApprovals containsObject:key]; }
}

+ (void)rememberTask:(NSString *)key {
	if (key == nil) return;
	@synchronized(self) {
		if (g_taskApprovals == nil) g_taskApprovals = [[NSMutableSet alloc] init];
		[g_taskApprovals addObject:key];
	}
}

+ (void)resetTaskApprovals {
	@synchronized(self) { [g_taskApprovals removeAllObjects]; }
}

#pragma mark - Asking

+ (BOOL)requestApprovalForKey:(NSString *)taskKey title:(NSString *)title detail:(NSString *)detail taskLabel:(NSString *)taskLabel
                  isCancelled:(BOOL (^)(void))cancelled denial:(NSString **)denial {
	if ([self taskAllows:taskKey]) return YES;

	// Block_copy/Block_release (not -copy/-release): they work on every blocks runtime.
	AGApprovalHandler handler = NULL;
	@synchronized(self) { if (g_handler != NULL) handler = Block_copy(g_handler); }
	if (handler == NULL) {
		if (denial) *denial = @"[GUARDRAIL] This action needs the user's approval, but no approval screen is available, so it was not done.";
		return NO;
	}

	AGApprovalTicket *ticket = [[[AGApprovalTicket alloc] init] autorelease];
	AGApprovalResponder responder = Block_copy(^(AGApprovalChoice choice) { [ticket setChoiceOnce:(NSInteger)choice]; });
	[self setPendingTitle:title];
	handler(title, detail, (taskKey != nil ? taskLabel : nil), responder);

	BOOL allowed = NO;
	NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + [self timeout];
	for (;;) {
		NSInteger choice = [ticket choice];
		if (choice >= 0) {
			if (choice == AGApprovalDeny) {
				if (denial) *denial = [NSString stringWithFormat:@"[GUARDRAIL] The user denied this action (%@). Do not retry the same thing; explain what you need or choose another approach.", title];
			} else {
				if (choice == AGApprovalAllowForTask) [self rememberTask:taskKey];
				allowed = YES;
			}
			break;
		}
		if (cancelled != nil && cancelled()) {
			if (![ticket setChoiceOnce:AGApprovalDeny]) continue;   // answered at the last moment: honour the answer
			[[NSNotificationCenter defaultCenter] postNotificationName:AGApprovalAbandonedNotification object:nil];
			if (denial) *denial = @"[cancelled]";
			break;
		}
		if ([NSDate timeIntervalSinceReferenceDate] > deadline) {
			if (![ticket setChoiceOnce:AGApprovalDeny]) continue;
			[[NSNotificationCenter defaultCenter] postNotificationName:AGApprovalAbandonedNotification object:nil];
			if (denial) *denial = [NSString stringWithFormat:@"[GUARDRAIL] No answer from the user within %d minutes, so the action was not done (%@).", (int)([self timeout] / 60.0), title];
			break;
		}
		[NSThread sleepForTimeInterval:0.1];
	}
	Block_release(responder);
	Block_release(handler);
	[self setPendingTitle:nil];
	return allowed;
}

@end
