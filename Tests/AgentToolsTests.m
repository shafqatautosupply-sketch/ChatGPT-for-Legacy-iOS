#import <Foundation/Foundation.h>
#import "AGAgentTools.h"
#import "AGGuardrails.h"
static int fails=0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
int main(){ @autoreleasepool {
 system("rm -rf /tmp/agws; mkdir -p /tmp/agws/ws /tmp/agws/theos/bin /tmp/agws/ws-evil; echo secret > /tmp/agws/ws-evil/x; ln -s /etc /tmp/agws/ws/link");
 NSUserDefaults *d=[NSUserDefaults standardUserDefaults]; [d setObject:@"/tmp/agws/ws" forKey:@"agent_workspace_dir"]; [d setObject:@"/tmp/agws/theos" forKey:@"agent_theos_dir"];
 NSString *ws=@"/tmp/agws/ws"; NSString *r;
 // big file: 400 lines of ~60 chars
 NSMutableString *big=[NSMutableString string]; for(int i=1;i<=400;i++) [big appendFormat:@"line %d: the quick brown fox jumps over the lazy dog 0123456789\n", i];
 r=[AGAgentTools writeFileAtPath:@"src/big.c" content:big workspace:ws]; CHECK("write creates parent dirs", [r hasPrefix:@"Success"]);
 r=[AGAgentTools readFileAtPath:@"src/big.c" lineStart:1 lineEnd:0 workspace:ws];
 printf("--- read header: %s\n", [[[r componentsSeparatedByString:@"\n"] objectAtIndex:0] UTF8String]);
 // verify header honesty: parse 'lines 1-N' and check last numbered line == N, and continuation hint matches
 NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"lines 1-(\\d+) of 400" options:0 error:nil]; NSTextCheckingResult *m=[re firstMatchInString:r options:0 range:NSMakeRange(0,[r length])];
 int N=[[r substringWithRange:[m rangeAtIndex:1]] intValue];
 CHECK("read header N == last line actually shown", [r rangeOfString:[NSString stringWithFormat:@"\n%d: line %d:",N,N]].location!=NSNotFound && [r rangeOfString:[NSString stringWithFormat:@"\n%d: ",N+1]].location==NSNotFound);
 CHECK("read gives accurate continuation hint", [r rangeOfString:[NSString stringWithFormat:@"line_start=%d]",N+1]].location!=NSNotFound);
 CHECK("read result within model budget", [r length] <= [AGAgentTools toolOutputLimit]);
 r=[AGAgentTools readFileAtPath:@"src/big.c" lineStart:399 lineEnd:0 workspace:ws]; CHECK("read tail range ok, no hint", [r rangeOfString:@"399:"].location!=NSNotFound && [r rangeOfString:@"more lines"].location==NSNotFound);
 r=[AGAgentTools readFileAtPath:@"/etc/passwd" lineStart:1 lineEnd:0 workspace:ws]; CHECK("read /etc/passwd blocked", [r rangeOfString:@"BLOCKED"].location!=NSNotFound);
 r=[AGAgentTools readFileAtPath:@"link/passwd" lineStart:1 lineEnd:0 workspace:ws]; CHECK("read via symlink blocked", [r rangeOfString:@"BLOCKED"].location!=NSNotFound);
 r=[AGAgentTools readFileAtPath:@"../ws-evil/x" lineStart:1 lineEnd:0 workspace:ws]; CHECK("read sibling dir blocked", [r rangeOfString:@"BLOCKED"].location!=NSNotFound);
 r=[AGAgentTools writeFileAtPath:@"../ws-evil/y" content:@"x" workspace:ws]; CHECK("write outside blocked", [r rangeOfString:@"BLOCKED"].location!=NSNotFound);
 r=[AGAgentTools writeFileAtPath:@"/tmp/agws/theos/bin/ldid" content:@"#!/bin/sh\nevil" workspace:ws]; CHECK("write into protected theos/bin blocked", [r rangeOfString:@"protected"].location!=NSNotFound);
 r=[AGAgentTools writeFileAtPath:@"/tmp/agws/theos/projects/ok.txt" content:@"fine" workspace:ws]; CHECK("write to other theos dirs allowed", [r hasPrefix:@"Success"]);
 // edit
 [AGAgentTools writeFileAtPath:@"e.m" content:@"a\nfoo();\nb\nfoo();\n" workspace:ws];
 system("chmod 755 /tmp/agws/ws/e.m");
 r=[AGAgentTools editFileAtPath:@"e.m" oldText:@"foo();" newText:@"bar();" replaceAll:NO workspace:ws]; CHECK("edit refuses ambiguous match", [r rangeOfString:@"2 times"].location!=NSNotFound);
 r=[AGAgentTools editFileAtPath:@"e.m" oldText:@"b\nfoo();" newText:@"b\nbar();" replaceAll:NO workspace:ws]; CHECK("edit unique match works", [r hasPrefix:@"Success"]);
 NSString *after=[NSString stringWithContentsOfFile:@"/tmp/agws/ws/e.m" encoding:NSUTF8StringEncoding error:nil]; CHECK("edit result correct", [after isEqualToString:@"a\nfoo();\nb\nbar();\n"]);
 r=[AGAgentTools editFileAtPath:@"e.m" oldText:@"zzz" newText:@"y" replaceAll:NO workspace:ws]; CHECK("edit reports not found", [r rangeOfString:@"not found"].location!=NSNotFound);
 r=[AGAgentTools editFileAtPath:@"e.m" oldText:@"foo();" newText:@"baz();" replaceAll:YES workspace:ws]; CHECK("edit replace_all", [r hasPrefix:@"Success"]);
 struct stat st; stat("/tmp/agws/ws/e.m",&st); CHECK("edit preserves exec bit", (st.st_mode&0111)!=0);
 // dispatcher robustness against hostile/garbled model output
 CHECK("dispatch: args as array doesn't crash", [[AGAgentTools executeToolNamed:@"readFile" arguments:[NSArray array] workspace:ws isCancelled:nil] hasPrefix:@"Error"]);
 CHECK("dispatch: args nil doesn't crash", [[AGAgentTools executeToolNamed:@"runShellCommand" arguments:nil workspace:ws isCancelled:nil] hasPrefix:@"Error"]);
 CHECK("dispatch: numeric command doesn't crash", [[AGAgentTools executeToolNamed:@"runShellCommand" arguments:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:5] forKey:@"command"] workspace:ws isCancelled:nil] hasPrefix:@"Error"]);
 CHECK("dispatch: unknown tool", [[AGAgentTools executeToolNamed:@"rm_rf" arguments:nil workspace:ws isCancelled:nil] hasPrefix:@"Error: Unknown"]);
 // clipping keeps head + tail
 NSMutableString *log=[NSMutableString string]; for(int i=0;i<3000;i++)[log appendFormat:@"compiling file %d\n",i]; [log appendString:@"error: undefined symbol _foo\n"];
 NSString *c=[AGAgentTools clipText:log toLimit:4000 tailFraction:0.7]; CHECK("clip keeps final error", [c rangeOfString:@"undefined symbol _foo"].location!=NSNotFound && [c rangeOfString:@"compiling file 0\n"].location!=NSNotFound && [c length]<4200);
 NSString *decl=[[AGAgentTools toolDeclarations] description]; printf("tool declaration size: %lu chars (~%lu tokens, sent every request)\n",(unsigned long)[decl length],(unsigned long)[decl length]/4);
 printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
