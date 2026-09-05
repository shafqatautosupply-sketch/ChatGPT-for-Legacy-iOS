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

	NSString *unquotedCommand = trimmedCommand;
	NSRegularExpression *regexSingle = [NSRegularExpression regularExpressionWithPattern:@"'[^']*'" options:0 error:nil];
	unquotedCommand = [regexSingle stringByReplacingMatchesInString:unquotedCommand options:0 range:NSMakeRange(0, [unquotedCommand length]) withTemplate:@"''"];

	NSRegularExpression *regexDouble = [NSRegularExpression regularExpressionWithPattern:@"\"[^\"]*\"" options:0 error:nil];
	unquotedCommand = [regexDouble stringByReplacingMatchesInString:unquotedCommand options:0 range:NSMakeRange(0, [unquotedCommand length]) withTemplate:@"\"\""];

	if ([unquotedCommand rangeOfString:@"&&"].location != NSNotFound ||
		[unquotedCommand rangeOfString:@"||"].location != NSNotFound ||
		[unquotedCommand rangeOfString:@";"].location != NSNotFound ||
		[unquotedCommand rangeOfString:@"|"].location != NSNotFound) {
		if (reasonOut) *reasonOut = @"BLOCKED (Guardrails): use one command at a time.";
		return NO;
	}

	NSString *lowerCmd = [trimmedCommand lowercaseString];
	for (NSString *block in [self obfuscationBlocks]) {
		if ([lowerCmd rangeOfString:[block lowercaseString]].location != NSNotFound) {
			if (reasonOut) *reasonOut = [NSString stringWithFormat:@"BLOCKED (Guardrails): Command contains restricted/obfuscated token '%@'.", block];
			return NO;
		}
	}

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

	// Inspect arguments for hardblock and secret paths
	for (NSUInteger i = 1; i < [tokens count]; i++) {
		NSString *token = [tokens objectAtIndex:i];
		NSString *standardToken = [token stringByStandardizingPath];
		for (NSString *hb in [self hardBlockPaths]) {
			if ([standardToken hasPrefix:hb] || [token rangeOfString:hb].location != NSNotFound) {
				if (reasonOut) *reasonOut = [NSString stringWithFormat:@"BLOCKED (Guardrails): Access to hardblocked path '%@' is forbidden.", hb];
				return NO;
			}
		}
		for (NSString *sp in [self secretPaths]) {
			if ([standardToken hasPrefix:sp] || [token rangeOfString:sp].location != NSNotFound) {
				if (reasonOut) *reasonOut = [NSString stringWithFormat:@"BLOCKED (Guardrails): Access to secret path '%@' is forbidden.", sp];
				return NO;
			}
		}
	}

    return YES;
}

+ (BOOL)isPathAllowed:(NSString *)pathstr {
	@try {
		NSString *absolutePath = [pathstr stringByStandardizingPath];

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
			NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
			if ([docsDir length] == 0) docsDir = @"/var/mobile/Documents";
			workspace = [docsDir stringByAppendingPathComponent:@"SandBox"];
		}
		workspace = [workspace stringByStandardizingPath];
		NSString *theos = @"/var/mobile/theos";
		return ([absolutePath hasPrefix:workspace] || [absolutePath hasPrefix:theos]);
	} @catch (NSException *exception) {
		return FALSE;
	}
}

@end
