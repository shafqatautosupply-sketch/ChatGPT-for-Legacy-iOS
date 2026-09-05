#import "CGAgentTools.h"
#import "CGAgentGuardrails.h"

@implementation CGAgentTools

+ (NSString *)executeShellCommand:(NSString *)command workspaceDirectory:(NSString *)workspaceDir {
	NSString *reason = nil;
	if (![CGAgentGuardrails isCommandSafe:command reason:&reason]) {
		return [NSString stringWithFormat:@"[GUARDRAIL TRIGGERED] %@", reason];
	}

	NSString *targetWorkspace = workspaceDir;
	if ([targetWorkspace length] == 0) {
		NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
		if ([docsDir length] == 0) docsDir = @"/var/mobile/Documents";
		targetWorkspace = [docsDir stringByAppendingPathComponent:@"SandBox"];
	}
	targetWorkspace = [targetWorkspace stringByStandardizingPath];

	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:targetWorkspace]) {
		[fm createDirectoryAtPath:targetWorkspace withIntermediateDirectories:YES attributes:nil error:nil];
	}

	NSMutableString *prefix = [NSMutableString string];
	[prefix appendFormat:@"mkdir -p \"%@\"; cd \"%@\" 2>/dev/null; ", targetWorkspace, targetWorkspace];

	NSArray *preCommands = [[NSUserDefaults standardUserDefaults] arrayForKey:@"agent_pre_execution_commands"];
	for (NSString *preCmd in preCommands) {
		NSString *trimmed = [preCmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([trimmed length] > 0) {
			[prefix appendFormat:@"%@; ", trimmed];
		}
	}

	NSString *fullCmd = [NSString stringWithFormat:@"%@ %@ 2>&1", prefix, command];
	FILE *fp = popen([fullCmd UTF8String], "r");
	if (fp == NULL) {
		return @"Error executing shell command.";
	}

	NSMutableData *data = [NSMutableData data];
	char buffer[256];
	while (fgets(buffer, sizeof(buffer), fp) != NULL) {
		[data appendBytes:buffer length:strlen(buffer)];
	}
	pclose(fp);

	NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];

	if ([output length] == 0) {
		NSMutableString *fPrefix = [NSMutableString string];
		[fPrefix appendFormat:@"mkdir -p \"%@\"; cd \"%@\" 2>/dev/null; ", targetWorkspace, targetWorkspace];
		for (NSString *preCmd in preCommands) {
			NSString *trimmed = [preCmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([trimmed length] > 0) {
				[fPrefix appendFormat:@"%@; ", trimmed];
			}
		}
		NSString *fallbackCmd = [NSString stringWithFormat:@"%@ %@ 2>&1", fPrefix, command];
		FILE *fp2 = popen([fallbackCmd UTF8String], "r");
		if (fp2 != NULL) {
			NSMutableData *data2 = [NSMutableData data];
			while (fgets(buffer, sizeof(buffer), fp2) != NULL) {
				[data2 appendBytes:buffer length:strlen(buffer)];
			}
			pclose(fp2);
			output = [[[NSString alloc] initWithData:data2 encoding:NSUTF8StringEncoding] autorelease];
		}
	}

	return ([output length] > 0 ? output : @"Command executed successfully with empty output.");
}

+ (NSString *)writeFileAtPath:(NSString *)path content:(id)content workspaceDirectory:(NSString *)workspaceDir {
	NSString *targetWorkspace = workspaceDir;
	if ([targetWorkspace length] == 0) {
		NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
		if ([docsDir length] == 0) docsDir = @"/var/mobile/Documents";
		targetWorkspace = [docsDir stringByAppendingPathComponent:@"SandBox"];
	}
	targetWorkspace = [targetWorkspace stringByStandardizingPath];

	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:targetWorkspace]) {
		[fm createDirectoryAtPath:targetWorkspace withIntermediateDirectories:YES attributes:nil error:nil];
	}

	NSString *targetPath = path;
	if (![path isAbsolutePath]) {
		targetPath = [targetWorkspace stringByAppendingPathComponent:path];
	}
	targetPath = [targetPath stringByStandardizingPath];

	if (![CGAgentGuardrails isPathAllowed:targetPath]) {
		return @"Error: Cannot write outside of workspace or Theos directory.";
	}

	@try {
		NSString *stringContent = nil;
		if ([content isKindOfClass:[NSString class]]) {
			stringContent = (NSString *)content;
		} else if ([content isKindOfClass:[NSDictionary class]] || [content isKindOfClass:[NSArray class]]) {
			NSError *jsonError = nil;
			NSData *jsonData = [NSJSONSerialization dataWithJSONObject:content options:NSJSONWritingPrettyPrinted error:&jsonError];
			if (jsonData != nil) {
				stringContent = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
			}
		}
		if (stringContent == nil) {
			stringContent = [content description] ?: @"";
		}

		NSData *data = [stringContent dataUsingEncoding:NSUTF8StringEncoding];
		BOOL success = [data writeToFile:targetPath atomically:YES];
		if (success) {
			return [NSString stringWithFormat:@"Success: File written to %@", path];
		} else {
			return @"Error: Failed to write file to disk.";
		}
	} @catch (NSException *exception) {
		return [NSString stringWithFormat:@"Error writing file: %@", [exception reason]];
	}
}

@end
