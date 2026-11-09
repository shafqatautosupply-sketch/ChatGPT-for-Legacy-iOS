#import "AGGuardrails.h"
#import "AGPathJail.h"
#include <sys/stat.h>
#include <unistd.h>

static NSString * const AGDefaultTheosDir = @"/var/mobile/theos";

@implementation AGGuardrails

#pragma mark - Defaults

+ (NSArray *)defaultAllowedBinaries {
	// `cycript` (arbitrary code, can inject into other processes) and
	// `dpkg-trigger` are deliberately NOT in the defaults any more. They can be
	// added back under Settings > Agent Guardrails > Allowed Binaries.
	return [NSArray arrayWithObjects:
		@"make", @"clang", @"clang-3.7", @"cc", @"c++", @"as", @"ld", @"lipo", @"strip",
		@"dpkg-deb", @"dpkg-query", @"dpkg-split", @"redeb",
		@"ldid", @"codesign_allocate", @"class-dump", @"classdump-dyld", @"machocheck",
		@"echo", @"cat", @"ls", @"cp", @"mv", @"mkdir", @"touch", @"ln",
		@"grep", @"egrep", @"fgrep", @"find", @"sed", @"awk", @"gawk", @"tar", @"zip", @"unzip",
		@"7z", @"7za", @"gzip", @"gunzip", @"bzip2", @"xz", @"diff", @"patch", @"date", @"uname",
		@"basename", @"dirname", @"head", @"tail", @"wc", @"sort", @"uniq", @"stat", nil];
}

+ (NSArray *)defaultHardBlockPaths {
	return [NSArray arrayWithObjects:
		@"/System", @"/usr/lib", @"/usr/libexec", @"/usr/sbin",
		@"/sbin", @"/bin", @"/boot", @"/var/stash",
		@"/usr/share/firmware", @"/usr/standalone", nil];
}

+ (NSArray *)defaultSecretPaths {
	return [NSArray arrayWithObjects:
		@"/var/Keychains", @"/var/mobile/Library/Mail",
		@"/var/mobile/Library/Preferences", @"/var/mobile/Library/Accounts",
		@"/var/mobile/Library/Cookies", @"/var/mobile/Library/Safari",
		@"/var/mobile/Library/SMS", @"/var/mobile/Library/Keyboard",
		@"/private/var/db", @"/var/db", @"/private/etc", @"/etc", nil];
}

+ (NSArray *)defaultPreExecutionCommands {
	return [NSArray arrayWithObject:@"export THEOS=/var/mobile/theos"];
}

#pragma mark - Config readers

+ (NSArray *)userArrayForKey:(NSString *)key {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	return [value isKindOfClass:[NSArray class]] ? value : nil;
}

+ (NSSet *)allowedBinaries {
	NSArray *saved = [self userArrayForKey:@"agent_allowed_binaries"];
	return [NSSet setWithArray:(saved != nil ? saved : [self defaultAllowedBinaries])];
}

+ (NSArray *)unionOfDefaults:(NSArray *)defaults withKey:(NSString *)key {
	NSMutableArray *result = [NSMutableArray arrayWithArray:defaults];
	for (id entry in [self userArrayForKey:key]) {
		if ([entry isKindOfClass:[NSString class]] && [entry hasPrefix:@"/"] && ![result containsObject:entry]) {
			[result addObject:entry];
		}
	}
	return result;
}

+ (NSArray *)hardBlockPaths { return [self unionOfDefaults:[self defaultHardBlockPaths] withKey:@"agent_hard_block_paths"]; }
+ (NSArray *)secretPaths    { return [self unionOfDefaults:[self defaultSecretPaths] withKey:@"agent_secret_paths"]; }

+ (NSString *)defaultSandbox {
	NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
	if ([docs length] == 0) docs = @"/var/mobile/Documents";
	return [docs stringByAppendingPathComponent:@"SandBox"];
}

+ (NSString *)workspaceDirectory {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"agent_workspace_dir"];
	NSString *candidate = ([saved length] > 0) ? saved : [self defaultSandbox];
	if (![candidate hasPrefix:@"/"]) candidate = [self defaultSandbox];

	if (![fm fileExistsAtPath:candidate]) {
		[fm createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:nil];
	}
	if (![fm isWritableFileAtPath:candidate]) {
		candidate = [self defaultSandbox];
		if (![fm fileExistsAtPath:candidate]) {
			[fm createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:nil];
		}
	}
	return candidate;
}

+ (NSString *)theosDirectory {
	NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"agent_theos_dir"];
	return ([saved hasPrefix:@"/"]) ? saved : AGDefaultTheosDir;
}

+ (NSArray *)allowedRoots {
	return [AGPathJail canonicalRoots:[NSArray arrayWithObjects:[self workspaceDirectory], [self theosDirectory], nil]];
}

#pragma mark - Path authorisation

+ (BOOL)isCanonical:(NSString *)canonical insideAnyOf:(NSArray *)rawPaths {
	return [AGPathJail canonicalPath:canonical isWithinAnyRoot:[AGPathJail canonicalRoots:rawPaths]];
}

+ (BOOL)isProtectedForWrite:(NSString *)canonical {
	// A model that can rewrite Theos' own makefiles/scripts owns every future build.
	NSString *theos = [self theosDirectory];
	NSMutableArray *protectedDirs = [NSMutableArray array];
	NSArray *names = [NSArray arrayWithObjects:@"bin", @"makefiles", @"vendor", @"templates", @"sdks", nil];
	for (NSString *name in names) [protectedDirs addObject:[theos stringByAppendingPathComponent:name]];
	return [self isCanonical:canonical insideAnyOf:protectedDirs];
}

+ (NSString *)authorizePath:(NSString *)path relativeTo:(NSString *)base forWrite:(BOOL)write reason:(NSString **)reason {
	NSString *canonical = [AGPathJail canonicalPath:path relativeTo:base];
	if (canonical == nil) {
		if (reason) *reason = [NSString stringWithFormat:@"BLOCKED (Guardrails): cannot resolve path '%@'.", path];
		return nil;
	}
	if (![AGPathJail canonicalPath:canonical isWithinAnyRoot:[self allowedRoots]]) {
		if (reason) *reason = [NSString stringWithFormat:@"BLOCKED (Guardrails): '%@' is outside the workspace and Theos directory.", path];
		return nil;
	}
	if ([self isCanonical:canonical insideAnyOf:[self hardBlockPaths]] ||
		[self isCanonical:canonical insideAnyOf:[self secretPaths]]) {
		if (reason) *reason = [NSString stringWithFormat:@"BLOCKED (Guardrails): '%@' is a protected system path.", path];
		return nil;
	}
	if (write && [self isProtectedForWrite:canonical]) {
		if (reason) *reason = [NSString stringWithFormat:@"BLOCKED (Guardrails): '%@' is inside a protected Theos directory (read-only).", path];
		return nil;
	}
	return canonical;
}

#pragma mark - Binary resolution

+ (NSArray *)execSearchPath {
	NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"agent_exec_path"];
	if ([saved length] > 0) return [saved componentsSeparatedByString:@":"];
	return [NSArray arrayWithObjects:@"/usr/bin", @"/bin", @"/usr/local/bin", @"/usr/sbin", @"/sbin",
		[[self theosDirectory] stringByAppendingPathComponent:@"bin"], nil];
}

+ (NSString *)resolveBinary:(NSString *)name {
	// Bare names only: "./make" or "/tmp/make" would let a file the model wrote
	// impersonate a whitelisted tool.
	if ([name length] == 0 || [name rangeOfString:@"/"].location != NSNotFound) return nil;
	for (NSString *dir in [self execSearchPath]) {
		NSString *candidate = [dir stringByAppendingPathComponent:name];
		struct stat st;
		if (stat([candidate fileSystemRepresentation], &st) == 0 && S_ISREG(st.st_mode) &&
			access([candidate fileSystemRepresentation], X_OK) == 0) {
			return candidate;
		}
	}
	return nil;
}

#pragma mark - Argument validation

static BOOL AGArgMatches(NSString *arg, NSArray *exact, NSArray *prefixes) {
	for (NSString *flag in exact) {
		if ([arg isEqualToString:flag]) return YES;
		if ([flag hasPrefix:@"--"] && [arg hasPrefix:[flag stringByAppendingString:@"="]]) return YES;
	}
	for (NSString *prefix in prefixes) {
		if ([arg hasPrefix:prefix]) return YES;
	}
	return NO;
}

static BOOL AGRegexMatches(NSString *pattern, NSString *text) {
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
	return re != nil && [re numberOfMatchesInString:text options:0 range:NSMakeRange(0, [text length])] > 0;
}

/// Flags that turn an ordinary tool into a command runner or a file writer
/// that the path jail cannot see.
+ (NSString *)dangerousUsageOfBinary:(NSString *)bin argv:(NSArray *)argv {
	NSArray *exact = nil, *prefixes = nil;

	if ([bin isEqualToString:@"find"]) {
		exact = [NSArray arrayWithObjects:@"-exec", @"-execdir", @"-ok", @"-okdir", @"-delete",
			@"-fprint", @"-fprint0", @"-fprintf", @"-fls", nil];
	} else if ([bin isEqualToString:@"tar"]) {
		exact = [NSArray arrayWithObjects:@"--to-command", @"--checkpoint-action", @"--use-compress-program",
			@"--rsh-command", @"--info-script", @"--new-volume-script", @"--volno-file",
			@"--absolute-names", @"-I", @"-F", @"-P", nil];
	} else if ([bin isEqualToString:@"zip"]) {
		exact = [NSArray arrayWithObject:@"-TT"];
	} else if ([bin isEqualToString:@"date"]) {
		exact = [NSArray arrayWithObjects:@"-s", @"--set", nil];
	} else if ([bin isEqualToString:@"clang"] || [bin isEqualToString:@"clang-3.7"] ||
			   [bin isEqualToString:@"cc"] || [bin isEqualToString:@"c++"]) {
		// Compiler plugins and wrappers execute arbitrary code at compile time.
		exact = [NSArray arrayWithObjects:@"-load", @"-wrapper", @"-Xclang", nil];
		prefixes = [NSArray arrayWithObjects:@"-fplugin", @"-fpass-plugin", @"-specs", nil];
	} else if ([bin isEqualToString:@"awk"] || [bin isEqualToString:@"gawk"]) {
		exact = [NSArray arrayWithObjects:@"-f", @"--file", @"-i", @"--include", @"-l", @"--load", @"-E", @"--exec", nil];
	} else if ([bin isEqualToString:@"sed"]) {
		exact = [NSArray arrayWithObjects:@"-f", @"--file", nil];
	}

	for (NSUInteger i = 1; i < [argv count]; i++) {
		NSString *arg = [argv objectAtIndex:i];
		if (AGArgMatches(arg, exact, prefixes)) {
			return [NSString stringWithFormat:@"'%@' is not allowed with %@ (it can execute code or write outside the jail).", arg, bin];
		}

		// tar bundles flags: "tar xPf a.tar" / "tar -xIf ..." must not sneak P/I/F in.
		if ([bin isEqualToString:@"tar"] && [arg length] > 1 && ![arg hasPrefix:@"--"] &&
			(i == 1 || [arg hasPrefix:@"-"]) && AGRegexMatches(@"^-?[A-Za-z]+$", arg) &&
			AGRegexMatches(@"[PIF]", arg)) {
			return [NSString stringWithFormat:@"tar flag cluster '%@' contains a forbidden option (P, I or F).", arg];
		}

		if ([arg hasPrefix:@"-"] && ![bin isEqualToString:@"awk"] && ![bin isEqualToString:@"gawk"] && ![bin isEqualToString:@"sed"]) continue;

		if ([bin isEqualToString:@"sed"]) {
			// e/E (execute) and w/W/r/R (write/read arbitrary files) as sed commands or s///flags.
			if (AGRegexMatches(@"(^|[\\s;{}!0-9$,/\\\\])[wWeErR](\\s|$|;|\\})", arg)) {
				return @"this sed script uses e/w/r commands, which can run programs or touch files outside the jail. Use s///, d, p, a, i, c, y only.";
			}
		}
		if ([bin isEqualToString:@"awk"] || [bin isEqualToString:@"gawk"]) {
			if (AGRegexMatches(@"system\\s*\\(", arg) || AGRegexMatches(@"getline", arg) ||
				AGRegexMatches(@"\\bprintf?\\b[^;}\\n]*[|>]", arg) || AGRegexMatches(@"\\|&", arg) ||
				AGRegexMatches(@"@(include|load)", arg)) {
				return @"this awk program uses system()/getline/print-redirection, which can run programs or write outside the jail.";
			}
		}
	}
	return nil;
}

+ (BOOL)checkArgumentValue:(NSString *)value cwd:(NSString *)cwd write:(BOOL)write reason:(NSString **)reason {
	if ([value length] == 0 || [value isEqualToString:@"-"]) return YES;
	if ([value hasPrefix:@"@"]) value = [value substringFromIndex:1]; // response file
	if ([value length] == 0) return YES;
	// Multi-line text is a program/message, not a path.
	if ([value rangeOfString:@"\n"].location != NSNotFound) return YES;

	if ([value hasPrefix:@"/"]) {
		// "/foo/p" in `sed -n '/foo/p'` is a pattern. Only treat an absolute
		// argument as a path if its first component really exists on disk.
		NSArray *parts = [value componentsSeparatedByString:@"/"];
		NSString *first = ([parts count] > 1) ? [parts objectAtIndex:1] : @"";
		if ([first length] > 0) {
			struct stat st;
			if (lstat([[@"/" stringByAppendingString:first] fileSystemRepresentation], &st) != 0) return YES;
		}
	}
	return [self authorizePath:value relativeTo:cwd forWrite:write reason:reason] != nil;
}

+ (BOOL)validateArgv:(NSArray *)argv cwd:(NSString *)cwd reason:(NSString **)reason {
	if ([argv count] == 0) {
		if (reason) *reason = @"Command rejected: No command provided";
		return NO;
	}
	NSString *bin = [argv objectAtIndex:0];

	NSString *danger = [self dangerousUsageOfBinary:bin argv:argv];
	if (danger != nil) {
		if (reason) *reason = [@"BLOCKED (Guardrails): " stringByAppendingString:danger];
		return NO;
	}

	// Which commands write to which argument positions (protects Theos internals).
	NSSet *writesAll = [NSSet setWithObjects:@"mv", @"mkdir", @"touch", nil];
	BOOL writesLast = [bin isEqualToString:@"cp"] || [bin isEqualToString:@"ln"];

	NSUInteger lastNonOption = NSNotFound;
	for (NSUInteger i = [argv count] - 1; i >= 1 && i != NSNotFound; i--) {
		if (![[argv objectAtIndex:i] hasPrefix:@"-"]) { lastNonOption = i; break; }
	}

	// Short options that carry a path glued on: -I/path -L/path -o/path ...
	NSArray *gluedPathOptions = [NSArray arrayWithObjects:@"-I", @"-L", @"-F", @"-o", @"-B", @"-MF", @"-C", nil];

	for (NSUInteger i = 1; i < [argv count]; i++) {
		NSString *arg = [argv objectAtIndex:i];
		BOOL isWriteTarget = [writesAll containsObject:bin] || (writesLast && i == lastNonOption);

		if ([arg hasPrefix:@"-"] && [arg length] > 1) {
			NSString *value = nil;
			NSRange equals = [arg rangeOfString:@"="];
			if (equals.location != NSNotFound) {
				value = [arg substringFromIndex:equals.location + 1];
			} else if (![arg hasPrefix:@"--"]) {
				for (NSString *option in gluedPathOptions) {
					if ([arg length] > [option length] && [arg hasPrefix:option]) { value = [arg substringFromIndex:[option length]]; break; }
				}
			}
			if (value != nil && ![self checkArgumentValue:value cwd:cwd write:NO reason:reason]) return NO;
			continue;
		}

		// KEY=VALUE (make variables, env-style): check the value part as well.
		NSRange equals = [arg rangeOfString:@"="];
		if (equals.location != NSNotFound && equals.location > 0 && [[arg substringToIndex:equals.location] rangeOfString:@"/"].location == NSNotFound) {
			if (![self checkArgumentValue:[arg substringFromIndex:equals.location + 1] cwd:cwd write:NO reason:reason]) return NO;
		}
		if (![self checkArgumentValue:arg cwd:cwd write:isWriteTarget reason:reason]) return NO;
	}
	return YES;
}

@end
