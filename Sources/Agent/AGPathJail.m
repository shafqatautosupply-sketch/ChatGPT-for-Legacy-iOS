#import "AGPathJail.h"
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>
#include <errno.h>

@implementation AGPathJail

+ (NSString *)canonicalPath:(NSString *)path relativeTo:(NSString *)base {
	if ([path length] == 0) return nil;
	if ([path rangeOfString:@"\0"].location != NSNotFound) return nil;

	NSString *full = path;
	if (![path hasPrefix:@"/"]) {
		if ([base length] == 0 || ![base hasPrefix:@"/"]) return nil;
		full = [base stringByAppendingPathComponent:path];
	}

	// Work queue of path components still to be processed.
	NSMutableArray *pending = [NSMutableArray arrayWithArray:[full componentsSeparatedByString:@"/"]];
	NSString *current = @"/";
	int linkBudget = 40; // same order of magnitude as the kernel's MAXSYMLINKS

	while ([pending count] > 0) {
		NSString *component = [pending objectAtIndex:0];
		[pending removeObjectAtIndex:0];

		if ([component length] == 0 || [component isEqualToString:@"."]) continue;

		if ([component isEqualToString:@".."]) {
			// `current` is already canonical, so folding textually is correct.
			if (![current isEqualToString:@"/"]) {
				current = [current stringByDeletingLastPathComponent];
				if ([current length] == 0) current = @"/";
			}
			continue;
		}

		NSString *candidate = [current isEqualToString:@"/"]
			? [@"/" stringByAppendingString:component]
			: [[current stringByAppendingString:@"/"] stringByAppendingString:component];

		struct stat st;
		if (lstat([candidate fileSystemRepresentation], &st) != 0) {
			// Does not exist (yet): nothing to resolve, keep it verbatim.
			current = candidate;
			continue;
		}

		if (S_ISLNK(st.st_mode)) {
			if (--linkBudget < 0) return nil;
			char linkBuffer[PATH_MAX + 1];
			ssize_t length = readlink([candidate fileSystemRepresentation], linkBuffer, PATH_MAX);
			if (length <= 0) return nil;
			linkBuffer[length] = '\0';
			NSString *target = [NSString stringWithUTF8String:linkBuffer];
			if (target == nil) return nil;
			if ([target hasPrefix:@"/"]) current = @"/";
			// Re-queue the link target in front of what is left to process.
			NSArray *targetParts = [target componentsSeparatedByString:@"/"];
			NSRange range = NSMakeRange(0, 0);
			[pending replaceObjectsInRange:range withObjectsFromArray:targetParts];
			continue;
		}

		current = candidate;
	}
	return current;
}

+ (BOOL)canonicalPath:(NSString *)canonical isWithinRoot:(NSString *)root {
	if ([canonical length] == 0 || [root length] == 0) return NO;
	if ([root isEqualToString:@"/"]) return [canonical hasPrefix:@"/"];
	if ([canonical isEqualToString:root]) return YES;
	return [canonical hasPrefix:[root stringByAppendingString:@"/"]];
}

+ (BOOL)canonicalPath:(NSString *)canonical isWithinAnyRoot:(NSArray *)roots {
	for (NSString *root in roots) {
		if ([self canonicalPath:canonical isWithinRoot:root]) return YES;
	}
	return NO;
}

+ (NSArray *)canonicalRoots:(NSArray *)paths {
	NSMutableArray *result = [NSMutableArray array];
	for (NSString *path in paths) {
		if (![path isKindOfClass:[NSString class]] || ![path hasPrefix:@"/"]) continue;
		NSString *canonical = [self canonicalPath:path relativeTo:@"/"];
		if ([canonical length] > 0 && ![result containsObject:canonical]) [result addObject:canonical];
	}
	return result;
}

@end
