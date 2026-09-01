#import "CGAgentGuardrails.h"
#import <Foundation/Foundation.h>

@implementation CGAgentGuardrails

+ (NSSet *)allowedBinaries {
	NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"agent_allowed_binaries"];
	if (saved != nil) {
		return [NSSet setWithArray:saved];
	}
	return [NSSet setWithObjects:
		@"make", @"clang", @"clang-3.7", @"cc", @"c++", @"as", @"ld", @"lipo", @"strip",
		@"dpkg-deb", @"dpkg-query", @"dpkg-split", @"dpkg-trigger", @"redeb",
		@"ldid", @"codesign_allocate", @"class-dump", @"classdump-dyld", @"machocheck",
		@"echo", @"cat", @"ls", @"cp", @"mv", @"mkdir", @"touch", @"ln",
		@"grep", @"egrep", @"fgrep", @"find", @"sed", @"awk", @"gawk", @"tar", @"zip", @"unzip",
		@"7z", @"7za", @"gzip", @"gunzip", @"bzip2", @"xz", @"diff", @"patch", @"date", @"uname", @"basename", @"dirname", @"head", @"cycript", @"tail", nil];
}

+ (NSArray *)hardBlockPaths {
	NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"agent_hard_block_paths"];
	if (saved != nil) {
		return saved;
	}
	return [NSArray arrayWithObjects:
		@"/System", @"/usr/lib", @"/usr/libexec", @"/usr/sbin",
		@"/sbin", @"/bin", @"/boot", @"/var/stash",
		@"/usr/share/firmware", @"/usr/standalone", nil];
}

+ (NSArray *)secretPaths {
	NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"agent_secret_paths"];
	if (saved != nil) {
		return saved;
	}
	return [NSArray arrayWithObjects:
		@"/var/Keychains", @"/var/mobile/Library/Mail",
		@"/private/var/db", @"/var/mobile/Library/Accounts", nil];
}

+ (NSArray *)obfuscationBlocks {
	NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"agent_obfuscation_blocks"];
	if (saved != nil) {
		return saved;
	}
	return [NSArray arrayWithObjects:
		@"base64", @"xxd", @"openssl", @"eval", @"exec", 
		@"python", @"perl", @"ruby", @"nc", @"netcat", @"curl", @"wget", nil];
}

+ (BOOL)isCommandSafe:(NSString *)command reason:(NSString **)reasonOut {
	NSString *trimmedCommand = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmedCommand length] == 0) {
		if (reasonOut) *reasonOut = @"Command rejected: No command provided";
		return NO;
	}

	// Strip quoted substrings ('...' and "...") so semicolons/pipes inside code/regex strings don't trigger false positives
	NSString *unquotedCommand = trimmedCommand;
	NSRegularExpression *regexSingle = [NSRegularExpression regularExpressionWithPattern:@"'[^']*'" options:0 error:nil];
	unquotedCommand = [regexSingle stringByReplacingMatchesInString:unquotedCommand options:0 range:NSMakeRange(0, [unquotedCommand length]) withTemplate:@"''"];

	NSRegularExpression *regexDouble = [NSRegularExpression regularExpressionWithPattern:@"\"[^\"]*\"" options:0 error:nil];
	unquotedCommand = [regexDouble stringByReplacingMatchesInString:unquotedCommand options:0 range:NSMakeRange(0, [unquotedCommand length]) withTemplate:@"\"\""];

	// 1. Chaining Check on unquoted command
	if ([unquotedCommand rangeOfString:@"&&"].location != NSNotFound ||
		[unquotedCommand rangeOfString:@"||"].location != NSNotFound ||
		[unquotedCommand rangeOfString:@";"].location != NSNotFound ||
		[unquotedCommand rangeOfString:@"|"].location != NSNotFound) {
		if (reasonOut) *reasonOut = @"BLOCKED (Guardrails): use one command at a time.";
		return NO;
	}

	// 2. Obfuscation Block Check
	NSString *lowerCmd = [trimmedCommand lowercaseString];
	for (NSString *block in [self obfuscationBlocks]) {
		if ([lowerCmd rangeOfString:[block lowercaseString]].location != NSNotFound) {
			if (reasonOut) *reasonOut = [NSString stringWithFormat:@"BLOCKED (Guardrails): Command contains restricted/obfuscated token '%@'.", block];
			return NO;
		}
	}

	// 3. Whitelist Binary Check (robust whitespace handling)
	NSArray *components = [trimmedCommand componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSMutableArray *tokens = [NSMutableArray array];
	for (NSString *comp in components) {
		if ([comp length] > 0) {
			[tokens addObject:comp];
		}
	}

	if ([tokens count] == 0) {
		if (reasonOut) *reasonOut = @"Command rejected: No command provided";
		return NO;
	}

	NSString *baseBin = [[tokens objectAtIndex:0] lastPathComponent];

	if (![[self allowedBinaries] containsObject:baseBin]) {
		if (reasonOut) *reasonOut = [NSString stringWithFormat:@"BLOCKED (Guardrails): Command '%@' is not in the allowed execution whitelist.", baseBin];
		return NO;
	}

    return YES;
}

+ (BOOL)isPathAllowed:(NSString *)pathstr {
	@try {
		NSString *absolutePath = [pathstr stringByStandardizingPath];

		// Check Hardblock paths & Secret paths
		for (NSString *hb in [self hardBlockPaths]) {
			if ([absolutePath hasPrefix:hb]) {
				return NO;
			}
		}
		for (NSString *sp in [self secretPaths]) {
			if ([absolutePath hasPrefix:sp]) {
				return NO;
			}
		}

		NSString *workspace = [[NSUserDefaults standardUserDefaults] stringForKey:@"agent_workspace_dir"];
		if ([workspace length] == 0) {
			workspace = @"/var/mobile/Documents/SandBox";
		}
		NSString *theos = @"/var/mobile/theos";
		return ([absolutePath hasPrefix:workspace] || [absolutePath hasPrefix:theos]);
	} @catch (NSException *exception) {
		return FALSE;
	}
}

@end
