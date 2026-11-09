#import "AGShellRunner.h"
#import "AGGuardrails.h"
#import "AGPathJail.h"

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <string.h>
#include <glob.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/time.h>

static const NSUInteger AGMaxLineLength = 8000;
static const NSUInteger AGMaxCommandsPerLine = 12;
static const NSUInteger AGMaxGlobMatches = 500;
static const size_t AGHeadKeep = 65536;
static const size_t AGTailWindow = 131072;
static const size_t AGTailKeep = 65536;

static NSString *AGSyntaxHelp(NSString *what) {
	return [NSString stringWithFormat:@"[GUARDRAIL] Unsupported shell syntax: %@. Only simple commands joined by && are supported (plus the cd and pwd builtins). Run one command per call, use the writeFile/editFile tools instead of redirects, and use quotes for arguments with spaces.", what];
}

@implementation AGShellRunner

#pragma mark - Tokenizer

+ (NSArray *)parseCommandLine:(NSString *)line error:(NSString **)error {
	if ([line length] == 0 || [[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
		if (error) *error = @"Command rejected: No command provided";
		return nil;
	}
	if ([line length] > AGMaxLineLength) {
		if (error) *error = @"Command rejected: command line too long";
		return nil;
	}

	NSMutableArray *commands = [NSMutableArray array];
	NSMutableArray *tokens = [NSMutableArray array];
	NSMutableString *current = [NSMutableString string];
	BOOL inToken = NO, hasGlob = NO;
	NSUInteger length = [line length];

	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [line characterAtIndex:i];

		if (c == ' ' || c == '\t') {
			if (inToken) {
				[tokens addObject:[NSDictionary dictionaryWithObjectsAndKeys:[[current copy] autorelease], @"s", [NSNumber numberWithBool:hasGlob], @"glob", nil]];
				[current setString:@""]; inToken = NO; hasGlob = NO;
			}
			continue;
		}
		if (c == '\n' || c == '\r') {
			if (error) *error = AGSyntaxHelp(@"line breaks outside quotes (this would run several commands)");
			return nil;
		}
		if (c == '\'') {
			NSRange close = [line rangeOfString:@"'" options:0 range:NSMakeRange(i + 1, length - i - 1)];
			if (close.location == NSNotFound) { if (error) *error = AGSyntaxHelp(@"unterminated single quote"); return nil; }
			[current appendString:[line substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]];
			inToken = YES; i = close.location;
			continue;
		}
		if (c == '"') {
			NSUInteger j = i + 1; BOOL closed = NO;
			while (j < length) {
				unichar d = [line characterAtIndex:j];
				if (d == '\\' && j + 1 < length) {
					unichar e = [line characterAtIndex:j + 1];
					if (e == '"' || e == '\\' || e == '$' || e == '`') { [current appendFormat:@"%C", e]; j += 2; continue; }
					[current appendString:@"\\"]; j++; continue;
				}
				if (d == '"') { closed = YES; break; }
				[current appendFormat:@"%C", d]; j++;
			}
			if (!closed) { if (error) *error = AGSyntaxHelp(@"unterminated double quote"); return nil; }
			inToken = YES; i = j;
			continue;
		}
		if (c == '\\') {
			if (i + 1 >= length) { if (error) *error = AGSyntaxHelp(@"trailing backslash"); return nil; }
			[current appendFormat:@"%C", [line characterAtIndex:i + 1]];
			inToken = YES; i++;
			continue;
		}
		if (c == '&') {
			if (i + 1 < length && [line characterAtIndex:i + 1] == '&') {
				if (inToken) {
					[tokens addObject:[NSDictionary dictionaryWithObjectsAndKeys:[[current copy] autorelease], @"s", [NSNumber numberWithBool:hasGlob], @"glob", nil]];
					[current setString:@""]; inToken = NO; hasGlob = NO;
				}
				if ([tokens count] == 0) { if (error) *error = AGSyntaxHelp(@"'&&' with no command before it"); return nil; }
				[commands addObject:[NSArray arrayWithArray:tokens]]; [tokens removeAllObjects];
				i++;
				continue;
			}
			if (error) *error = AGSyntaxHelp(@"'&' (background jobs)");
			return nil;
		}
		if (c == ';' || c == '|' || c == '<' || c == '>' || c == '(' || c == ')' || c == '`' || c == '$') {
			NSString *what = (c == '|') ? @"'|' pipes / '||'" :
				(c == ';') ? @"';' command separators" :
				(c == '<' || c == '>') ? @"'<' '>' redirection" :
				(c == '$' || c == '`') ? @"'$' / backtick expansion (quote the character if you need it literally)" :
				@"parentheses / subshells";
			if (error) *error = AGSyntaxHelp(what);
			return nil;
		}
		if (c == '*' || c == '?' || c == '[') hasGlob = YES;
		[current appendFormat:@"%C", c];
		inToken = YES;
	}

	if (inToken) {
		[tokens addObject:[NSDictionary dictionaryWithObjectsAndKeys:[[current copy] autorelease], @"s", [NSNumber numberWithBool:hasGlob], @"glob", nil]];
	}
	if ([tokens count] == 0) {
		if (error) *error = AGSyntaxHelp(@"trailing '&&' with no command after it");
		return nil;
	}
	[commands addObject:[NSArray arrayWithArray:tokens]];
	if ([commands count] > AGMaxCommandsPerLine) {
		if (error) *error = @"[GUARDRAIL] Too many chained commands in one call.";
		return nil;
	}
	return commands;
}

#pragma mark - Globbing

static NSString *AGGlobEscape(NSString *s) {
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < [s length]; i++) {
		unichar c = [s characterAtIndex:i];
		if (c == '*' || c == '?' || c == '[' || c == '\\') [out appendString:@"\\"];
		[out appendFormat:@"%C", c];
	}
	return out;
}

+ (NSArray *)expandGlob:(NSString *)pattern cwd:(NSString *)cwd error:(NSString **)error {
	BOOL absolute = [pattern hasPrefix:@"/"];
	NSString *prefix = [AGGlobEscape(cwd) stringByAppendingString:@"/"];
	NSString *full = absolute ? pattern : [prefix stringByAppendingString:pattern];

	glob_t g;
	memset(&g, 0, sizeof(g));
	int rc = glob([full fileSystemRepresentation], 0, NULL, &g);
	NSMutableArray *results = [NSMutableArray array];
	if (rc == 0) {
		if (g.gl_pathc > AGMaxGlobMatches) {
			globfree(&g);
			if (error) *error = [NSString stringWithFormat:@"[GUARDRAIL] Pattern '%@' matches more than %lu files; narrow it.", pattern, (unsigned long)AGMaxGlobMatches];
			return nil;
		}
		NSString *strip = [cwd stringByAppendingString:@"/"];
		for (size_t i = 0; i < g.gl_pathc; i++) {
			NSString *path = [NSString stringWithUTF8String:g.gl_pathv[i]];
			if (path == nil) continue;
			if (!absolute && [path hasPrefix:strip]) path = [path substringFromIndex:[strip length]];
			[results addObject:path];
		}
	}
	globfree(&g);
	// Like sh: a pattern that matches nothing stays literal.
	if ([results count] == 0) [results addObject:pattern];
	return results;
}

#pragma mark - Rate limit

+ (BOOL)velocityAllowed {
	static NSMutableArray *stamps = nil;
	@synchronized(self) {
		if (stamps == nil) stamps = [[NSMutableArray alloc] init];
		NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
		NSMutableArray *fresh = [NSMutableArray array];
		for (NSNumber *t in stamps) if (now - [t doubleValue] < 60.0) [fresh addObject:t];
		[stamps setArray:fresh];
		if ([stamps count] >= 60) return NO;
		[stamps addObject:[NSNumber numberWithDouble:now]];
	}
	return YES;
}

#pragma mark - Environment

+ (NSArray *)environmentForWorkspace:(NSString *)workspace {
	NSMutableDictionary *env = [NSMutableDictionary dictionary];
	[env setObject:[[AGGuardrails execSearchPath] componentsJoinedByString:@":"] forKey:@"PATH"];
	[env setObject:workspace forKey:@"HOME"];
	[env setObject:@"en_US.UTF-8" forKey:@"LANG"];
	[env setObject:@"dumb" forKey:@"TERM"];
	[env setObject:[AGGuardrails theosDirectory] forKey:@"THEOS"];

	// Settings > Pre-Execution Commands used to be pasted in front of a shell
	// command. Without a shell we honour the only form people use: `export K=V`.
	NSArray *pre = [[NSUserDefaults standardUserDefaults] arrayForKey:@"agent_pre_execution_commands"];
	if (pre == nil) pre = [AGGuardrails defaultPreExecutionCommands];
	for (id item in pre) {
		if (![item isKindOfClass:[NSString class]]) continue;
		NSString *s = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([s hasPrefix:@"export "]) s = [s substringFromIndex:7];
		NSRange eq = [s rangeOfString:@"="];
		if (eq.location == NSNotFound || eq.location == 0) continue;
		NSString *key = [s substringToIndex:eq.location];
		NSString *value = [s substringFromIndex:eq.location + 1];
		if ([value length] >= 2 && (([value hasPrefix:@"\""] && [value hasSuffix:@"\""]) || ([value hasPrefix:@"'"] && [value hasSuffix:@"'"]))) {
			value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];
		}
		NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"] invertedSet];
		if ([key rangeOfCharacterFromSet:bad].location != NSNotFound) continue;
		[env setObject:value forKey:key];
	}

	NSMutableArray *list = [NSMutableArray array];
	for (NSString *key in env) [list addObject:[NSString stringWithFormat:@"%@=%@", key, [env objectForKey:key]]];
	return list;
}

#pragma mark - Process execution

static char **AGCStringArray(NSArray *strings) {
	char **array = (char **)calloc([strings count] + 1, sizeof(char *));
	for (NSUInteger i = 0; i < [strings count]; i++) array[i] = strdup([[strings objectAtIndex:i] UTF8String] ?: "");
	return array;
}
static void AGFreeCStringArray(char **array) {
	if (array == NULL) return;
	for (char **p = array; *p != NULL; p++) free(*p);
	free(array);
}

+ (NSString *)executeBinary:(NSString *)path
                       argv:(NSArray *)argv
                        cwd:(NSString *)cwd
                        env:(NSArray *)env
                    timeout:(NSTimeInterval)timeout
                isCancelled:(BOOL (^)(void))cancelled
                   exitCode:(int *)exitCodeOut {
	int pipeFds[2];
	if (pipe(pipeFds) != 0) { *exitCodeOut = 127; return @"Error: could not create pipe."; }
	int devNull = open("/dev/null", O_RDONLY);

	// Everything the child needs is prepared BEFORE fork(): after fork only
	// async-signal-safe calls are legal in a multi-threaded process.
	char *cPath = strdup([path fileSystemRepresentation]);
	char *cCwd = strdup([cwd fileSystemRepresentation]);
	char **cArgv = AGCStringArray(argv);
	char **cEnv = AGCStringArray(env);

	pid_t pid = fork();
	if (pid == 0) {
		setpgid(0, 0);
		if (chdir(cCwd) != 0) _exit(126);
		if (devNull >= 0) dup2(devNull, 0);
		dup2(pipeFds[1], 1);
		dup2(pipeFds[1], 2);
		close(pipeFds[0]);
		if (pipeFds[1] > 2) close(pipeFds[1]);
		if (devNull > 2) close(devNull);
		execve(cPath, cArgv, cEnv);
		_exit(127);
	}

	close(pipeFds[1]);
	if (devNull >= 0) close(devNull);
	free(cPath); free(cCwd); AGFreeCStringArray(cArgv); AGFreeCStringArray(cEnv);

	if (pid < 0) { close(pipeFds[0]); *exitCodeOut = 127; return @"Error: could not start process."; }
	setpgid(pid, pid); // also from the parent, to close the race with the child

	NSMutableData *head = [NSMutableData data];
	NSMutableData *tail = [NSMutableData data];
	unsigned long long dropped = 0;
	BOOL timedOut = NO, wasCancelled = NO, eof = NO;
	NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + timeout;
	char buffer[4096];

	while (!eof) {
		if (cancelled != nil && cancelled()) { wasCancelled = YES; break; }
		if ([NSDate timeIntervalSinceReferenceDate] > deadline) { timedOut = YES; break; }

		fd_set readSet; FD_ZERO(&readSet); FD_SET(pipeFds[0], &readSet);
		struct timeval tv; tv.tv_sec = 0; tv.tv_usec = 100000;
		int ready = select(pipeFds[0] + 1, &readSet, NULL, NULL, &tv);
		if (ready < 0) { if (errno == EINTR) continue; break; }
		if (ready == 0) continue;

		ssize_t n = read(pipeFds[0], buffer, sizeof(buffer));
		if (n > 0) {
			if ([head length] < AGHeadKeep) {
				size_t room = AGHeadKeep - [head length];
				size_t take = ((size_t)n < room) ? (size_t)n : room;
				[head appendBytes:buffer length:take];
				if ((size_t)n > take) [tail appendBytes:buffer + take length:(size_t)n - take];
			} else {
				[tail appendBytes:buffer length:(size_t)n];
			}
			// Keep only the newest bytes: the END of build output is where errors are.
			if ([tail length] > AGTailWindow) {
				size_t cut = [tail length] - AGTailKeep;
				[tail replaceBytesInRange:NSMakeRange(0, cut) withBytes:NULL length:0];
				dropped += cut;
			}
		} else if (n == 0) {
			eof = YES;
		} else if (errno != EINTR && errno != EAGAIN) {
			break;
		}
	}
	close(pipeFds[0]);

	if (timedOut || wasCancelled) kill(-pid, SIGKILL);

	// Reap. The child may have closed stdout but still be running: bound the wait.
	int status = 0; BOOL reaped = NO;
	while (!reaped) {
		pid_t r = waitpid(pid, &status, WNOHANG);
		if (r == pid) { reaped = YES; break; }
		if (r < 0 && errno != EINTR) { reaped = YES; break; }
		if ([NSDate timeIntervalSinceReferenceDate] > deadline + 2.0 || timedOut || wasCancelled) {
			kill(-pid, SIGKILL);
			waitpid(pid, &status, 0);
			if (!timedOut && !wasCancelled) timedOut = YES;
			reaped = YES;
			break;
		}
		usleep(10000);
	}
	kill(-pid, SIGKILL); // sweep stragglers (background children) of the group

	int code = 0;
	NSString *signalNote = nil;
	if (WIFEXITED(status)) code = WEXITSTATUS(status);
	else if (WIFSIGNALED(status)) { code = 128 + WTERMSIG(status); signalNote = [NSString stringWithFormat:@"terminated by signal %d", WTERMSIG(status)]; }
	*exitCodeOut = code;

	NSMutableData *all = [NSMutableData dataWithData:head];
	if (dropped > 0) {
		NSString *marker = [NSString stringWithFormat:@"\n[... %llu bytes of output omitted ...]\n", dropped];
		[all appendData:[marker dataUsingEncoding:NSUTF8StringEncoding]];
	}
	[all appendData:tail];

	NSString *text = [[[NSString alloc] initWithData:all encoding:NSUTF8StringEncoding] autorelease];
	if (text == nil) text = [[[NSString alloc] initWithData:all encoding:NSISOLatin1StringEncoding] autorelease];
	if (text == nil) text = @"";

	NSMutableString *result = [NSMutableString stringWithString:text];
	if (timedOut) [result appendFormat:@"\n[timed out after %.0fs; process killed]", timeout];
	if (wasCancelled) [result appendString:@"\n[cancelled]"];
	if (signalNote != nil && !timedOut && !wasCancelled) [result appendFormat:@"\n[%@]", signalNote];
	return result;
}

#pragma mark - Public entry point

+ (NSString *)runCommandLine:(NSString *)line workspace:(NSString *)workspace isCancelled:(BOOL (^)(void))cancelled {
	NSString *parseError = nil;
	NSArray *commands = [self parseCommandLine:line error:&parseError];
	if (commands == nil) return parseError;

	if (![self velocityAllowed]) return @"[GUARDRAIL] Velocity limit reached: too many shell commands in the last minute.";

	NSString *reason = nil;
	NSString *cwd = [AGGuardrails authorizePath:workspace relativeTo:@"/" forWrite:NO reason:&reason];
	if (cwd == nil) return [NSString stringWithFormat:@"[GUARDRAIL] Workspace is not usable: %@", reason];
	[[NSFileManager defaultManager] createDirectoryAtPath:cwd withIntermediateDirectories:YES attributes:nil error:nil];

	NSArray *env = [self environmentForWorkspace:workspace];
	id timeoutValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_command_timeout"];
	NSTimeInterval timeout = (timeoutValue != nil) ? [timeoutValue doubleValue] : 120.0;
	if (timeout < 1.0) timeout = 120.0;
	if (timeout > 900.0) timeout = 900.0;

	NSSet *allowed = [AGGuardrails allowedBinaries];
	NSMutableString *output = [NSMutableString string];
	BOOL multi = ([commands count] > 1);

	for (NSArray *tokens in commands) {
		if (cancelled != nil && cancelled()) { [output appendString:@"[cancelled]"]; break; }

		// 1. Glob expansion (never for the command name itself).
		NSMutableArray *argv = [NSMutableArray array];
		for (NSUInteger i = 0; i < [tokens count]; i++) {
			NSDictionary *token = [tokens objectAtIndex:i];
			NSString *value = [token objectForKey:@"s"];
			if (i > 0 && [[token objectForKey:@"glob"] boolValue]) {
				NSString *globError = nil;
				NSArray *expanded = [self expandGlob:value cwd:cwd error:&globError];
				if (expanded == nil) return globError;
				[argv addObjectsFromArray:expanded];
			} else {
				[argv addObject:value];
			}
		}
		NSString *bin = [argv objectAtIndex:0];

		// 2. Builtins.
		if ([bin isEqualToString:@"cd"]) {
			if ([argv count] > 2) return @"[GUARDRAIL] cd takes at most one argument.";
			if ([argv count] == 1) { cwd = [AGGuardrails authorizePath:workspace relativeTo:@"/" forWrite:NO reason:&reason]; continue; }
			NSString *target = [AGGuardrails authorizePath:[argv objectAtIndex:1] relativeTo:cwd forWrite:NO reason:&reason];
			if (target == nil) return [NSString stringWithFormat:@"[GUARDRAIL TRIGGERED] %@", reason];
			BOOL isDir = NO;
			if (![[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&isDir] || !isDir) {
				return [NSString stringWithFormat:@"cd: %@: No such directory", [argv objectAtIndex:1]];
			}
			cwd = target;
			continue;
		}
		if ([bin isEqualToString:@"pwd"]) { [output appendFormat:@"%@\n", cwd]; continue; }

		// 3. Policy.
		if (![allowed containsObject:bin]) {
			return [NSString stringWithFormat:@"[GUARDRAIL TRIGGERED] BLOCKED (Guardrails): Command '%@' is not in the allowed execution whitelist.", bin];
		}
		NSString *binaryPath = [AGGuardrails resolveBinary:bin];
		if (binaryPath == nil) {
			return [NSString stringWithFormat:@"[GUARDRAIL TRIGGERED] '%@' is allowed but was not found in: %@", bin, [[AGGuardrails execSearchPath] componentsJoinedByString:@":"]];
		}
		if (![AGGuardrails validateArgv:argv cwd:cwd reason:&reason]) {
			return [NSString stringWithFormat:@"[GUARDRAIL TRIGGERED] %@", reason];
		}

		// 4. Run.
		if (multi) {
			NSString *shown = [argv componentsJoinedByString:@" "];
			if ([shown length] > 100) shown = [[shown substringToIndex:100] stringByAppendingString:@"..."];
			[output appendFormat:@"$ %@\n", shown];
		}
		int exitCode = 0;
		NSString *text = [self executeBinary:binaryPath argv:argv cwd:cwd env:env timeout:timeout isCancelled:cancelled exitCode:&exitCode];
		[output appendString:text];
		if ([text length] > 0 && ![text hasSuffix:@"\n"]) [output appendString:@"\n"];
		if (exitCode != 0) {
			[output appendFormat:@"[exit code %d]\n", exitCode];
			break; // && semantics
		}
	}

	NSString *final = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return ([final length] > 0) ? final : @"(no output, exit code 0)";
}

@end
