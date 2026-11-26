#import "AGSandbox.h"
#import "AGGuardrails.h"
#import "AGPathJail.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

static NSString * const AGMobileHome = @"/private/var/mobile";

static BOOL AGBoolDefault(NSString *key, BOOL fallback) {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

/// Quotes a path for the profile language, or nil if it contains something that could
/// break out of the string (quote, backslash, control characters) or is not absolute.
static NSString *AGQuote(NSString *path) {
	if ([path length] == 0 || ![path hasPrefix:@"/"]) return nil;
	for (NSUInteger i = 0; i < [path length]; i++) {
		unichar c = [path characterAtIndex:i];
		if (c == '"' || c == '\\' || c < 0x20 || c == 0x7f) return nil;
	}
	return [NSString stringWithFormat:@"\"%@\"", path];
}

@implementation AGSandbox

+ (AGSandboxInitFn)initFunction {
	static void *function = NULL;
	static BOOL resolved = NO;
	@synchronized(self) {
		if (!resolved) {
			resolved = YES;
			function = dlsym(RTLD_DEFAULT, "sandbox_init");
			if (function == NULL) {
				void *handle = dlopen("/usr/lib/libsandbox.1.dylib", RTLD_NOW);
				if (handle != NULL) function = dlsym(handle, "sandbox_init");
			}
		}
	}
	return (AGSandboxInitFn)function;
}

+ (NSString *)profileForWorkspace:(NSString *)workspace reason:(NSString **)reason {
	NSString *work = [AGPathJail canonicalPath:workspace relativeTo:@"/"];
	NSString *home = [AGPathJail canonicalPath:AGMobileHome relativeTo:@"/"];
	if (home == nil) home = AGMobileHome;
	NSString *workQ = AGQuote(work);
	NSString *homeQ = AGQuote(home);
	if (workQ == nil || homeQ == nil) {
		if (reason) *reason = @"the workspace path cannot be written into a sandbox profile.";
		return nil;
	}
	if ([work isEqualToString:@"/"] || [work isEqualToString:home] || [home hasPrefix:[work stringByAppendingString:@"/"]]) {
		if (reason) *reason = @"the workspace is too broad (it is, or contains, the whole home folder).";
		return nil;
	}

	NSMutableString *profile = [NSMutableString stringWithString:@"(version 1)(allow default)"];
	if (AGBoolDefault(@"agent_sandbox_deny_network", YES)) [profile appendString:@"(deny network*)"];
	// Writes: only the workspace (and /dev/null). /var/tmp is exempt on this kernel.
	[profile appendFormat:@"(deny file-write*)(allow file-write* (subpath %@))(allow file-write* (literal \"/dev/null\"))", workQ];
	// Reads: the home folder is off limits except the workspace and the read-only extras.
	// Later rules win, so the allows come after the deny.
	[profile appendFormat:@"(deny file-read* (subpath %@))(allow file-read* (subpath %@))", homeQ, workQ];

	NSMutableArray *readDirs = [NSMutableArray arrayWithObject:[AGGuardrails theosDirectory]];
	id extra = [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_sandbox_read_dirs"];
	if ([extra isKindOfClass:[NSArray class]]) {
		for (id entry in extra) if ([entry isKindOfClass:[NSString class]] && [entry hasPrefix:@"/"]) [readDirs addObject:entry];
	}
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *dir in readDirs) {
		NSString *canonical = [AGPathJail canonicalPath:dir relativeTo:@"/"];
		NSString *quoted = AGQuote(canonical);
		if (quoted == nil || ![fm fileExistsAtPath:canonical]) continue;
		[profile appendFormat:@"(allow file-read* (subpath %@))", quoted];
	}

	if (AGBoolDefault(@"agent_sandbox_deny_mach", YES)) [profile appendString:@"(deny mach-lookup)"];
	[profile appendString:@"(deny mach-priv-task-port)"];
	return profile;
}

/// A throw-away child applies the profile and tries to create a file in the home folder
/// (outside the workspace). Refused = the kernel enforces it. Cached per profile.
+ (BOOL)verifyProfile:(NSString *)profile reason:(NSString **)reason {
	static NSMutableDictionary *cache = nil;
	@synchronized(self) {
		if (cache == nil) cache = [[NSMutableDictionary alloc] init];
		NSNumber *known = [cache objectForKey:profile];
		if (known != nil) {
			if (![known boolValue] && reason) *reason = @"the kernel did not enforce the profile (self-test failed earlier).";
			return [known boolValue];
		}
	}

	AGSandboxInitFn apply = [self initFunction];
	if (apply == NULL) { if (reason) *reason = @"this system has no sandbox_init()."; return NO; }
	char *cProfile = strdup([profile UTF8String]);
	char probe[160];
	snprintf(probe, sizeof(probe), "%s/.agentic_sandbox_probe_%d", [AGMobileHome fileSystemRepresentation], (int)getpid());

	// The test only proves something if the same write WORKS without the sandbox.
	int control = open(probe, O_WRONLY | O_CREAT | O_EXCL, 0600);
	if (control < 0) {
		free(cProfile);
		if (reason) *reason = @"the sandbox self-test is inconclusive (the home folder is not writable).";
		return NO;
	}
	close(control); unlink(probe);

	pid_t pid = fork();
	if (pid == 0) {
		char *err = NULL;
		if (apply(cProfile, 0, &err) != 0) _exit(2);
		int fd = open(probe, O_WRONLY | O_CREAT | O_TRUNC, 0600);
		if (fd >= 0) { close(fd); unlink(probe); _exit(1); }          // not refused: NOT enforced
		_exit((errno == EPERM || errno == EACCES) ? 0 : 3);
	}
	free(cProfile);
	int status = 0;
	if (pid < 0 || waitpid(pid, &status, 0) < 0) status = 0xff00;
	unlink(probe);

	int code = WIFEXITED(status) ? WEXITSTATUS(status) : 255;
	BOOL ok = (code == 0);
	@synchronized(self) { [cache setObject:[NSNumber numberWithBool:ok] forKey:profile]; }
	if (!ok && reason) {
		*reason = (code == 1) ? @"the kernel did not enforce the profile (a write outside the workspace succeeded)."
			: (code == 2) ? @"sandbox_init() rejected the profile on this system."
			: @"the sandbox self-test could not be completed.";
	}
	return ok;
}

+ (BOOL)isExpected {
	return AGBoolDefault(@"agent_sandbox", YES) && [self initFunction] != NULL;
}

+ (BOOL)prepareForWorkspace:(NSString *)workspace profile:(NSString **)profileOut reason:(NSString **)reason {
	if (!AGBoolDefault(@"agent_sandbox", YES)) {
		if (reason) *reason = @"the sandbox is turned off (agent_sandbox = NO).";
		return NO;
	}
	if ([self initFunction] == NULL) {
		if (reason) *reason = @"this system has no sandbox_init().";
		return NO;
	}
	NSString *profile = [self profileForWorkspace:workspace reason:reason];
	if (profile == nil) return NO;
	if (![self verifyProfile:profile reason:reason]) return NO;
	if (profileOut) *profileOut = profile;
	return YES;
}

@end
