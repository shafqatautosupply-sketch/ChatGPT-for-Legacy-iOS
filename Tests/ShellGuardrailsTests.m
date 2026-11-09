#import <Foundation/Foundation.h>
#import "AGShellRunner.h"
#import "AGGuardrails.h"
#import "AGPathJail.h"
static int fails = 0;
static NSString *R(NSString *c){ return [AGShellRunner runCommandLine:c workspace:@"/tmp/agws/ws" isCancelled:nil]; }
static void EXPECT_BLOCK(NSString *c){ NSString *o=R(c); BOOL b=[o hasPrefix:@"[GUARDRAIL"]; printf("%s block  %-46s %s\n", b?"PASS":"FAIL", [[c stringByReplacingOccurrencesOfString:@"\n" withString:@"<NL>"] UTF8String], b?"":[[@"=> RAN: " stringByAppendingString:o] UTF8String]); if(!b)fails++; }
static void EXPECT_OK(NSString *c, NSString *contains){ NSString *o=R(c); BOOL ok=![o hasPrefix:@"[GUARDRAIL"] && (contains==nil || [o rangeOfString:contains].location!=NSNotFound); printf("%s allow  %-46s %s\n", ok?"PASS":"FAIL", [c UTF8String], ok?"":[[@"=> " stringByAppendingString:o] UTF8String]); if(!ok)fails++; }
int main(){ @autoreleasepool {
  system("rm -rf /tmp/agws; mkdir -p /tmp/agws/ws/proj /tmp/agws/ws-evil /tmp/agws/theos/bin /tmp/agws/theos/projects");
  system("echo 'int function(void){return 1;}' > /tmp/agws/ws/a.m; echo 'since foo bar' > /tmp/agws/ws/b.m; echo 'secret' > /tmp/agws/ws-evil/x; printf '5 x\\n9 y\\n' > /tmp/agws/ws/f.txt; echo hi > /tmp/agws/ws/proj/p.txt");
  system("ln -s /etc /tmp/agws/ws/link; ln -s /tmp/agws/ws-evil /tmp/agws/ws/evil");
  NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
  [d setObject:@"/tmp/agws/ws" forKey:@"agent_workspace_dir"]; [d setObject:@"/tmp/agws/theos" forKey:@"agent_theos_dir"];
  NSMutableArray *al=[NSMutableArray arrayWithArray:[AGGuardrails defaultAllowedBinaries]]; [al addObjectsFromArray:[NSArray arrayWithObjects:@"sleep",@"yes",@"cycript_test",nil]];
  [d setObject:al forKey:@"agent_allowed_binaries"];
  printf("=== legitimate commands (previously some were falsely blocked) ===\n");
  EXPECT_OK(@"echo hello", @"hello");
  EXPECT_OK(@"cd proj && ls", @"p.txt");
  EXPECT_OK(@"cd proj && cat p.txt && pwd", @"hi");
  EXPECT_OK(@"ls *.m", @"a.m");
  EXPECT_OK(@"grep -rn \"function\" .", @"a.m");
  EXPECT_OK(@"grep since b.m", @"since");
  EXPECT_OK(@"sed -n '/foo/p' b.m", @"foo");
  EXPECT_OK(@"sed 's/foo/baz/' b.m", @"baz");
  EXPECT_OK(@"awk '$1 > 5 {print $2}' f.txt", @"y");
  EXPECT_OK(@"awk '/x|y/' f.txt", @"x");
  EXPECT_OK(@"cat -- a.m", @"function");
  EXPECT_OK(@"echo 'a;b|c>d $HOME'", @"a;b|c>d $HOME");
  printf("=== attacks that got through / are now blocked ===\n");
  EXPECT_BLOCK(@"cat $HOME/Library/Safari/History.plist");
  EXPECT_BLOCK(@"echo $(id)");
  EXPECT_BLOCK(@"ls `id`");
  EXPECT_BLOCK(@"echo pwned >/tmp/agws/x");
  EXPECT_BLOCK(@"echo a > b");
  EXPECT_BLOCK(@"cat a.m | head");
  EXPECT_BLOCK(@"echo a; echo b");
  EXPECT_BLOCK(@"echo hi & echo yo");
  EXPECT_BLOCK(@"echo hi\ntouch pwned");
  EXPECT_BLOCK(@"echo a || echo b");
  EXPECT_BLOCK(@"awk 'BEGIN{system(\"id\")}'");
  EXPECT_BLOCK(@"awk 'BEGIN{print \"x\" > \"/tmp/agws/o\"}'");
  EXPECT_BLOCK(@"awk 'BEGIN{\"id\" | getline x}'");
  EXPECT_BLOCK(@"sed 's/a/b/e' a.m");
  EXPECT_BLOCK(@"sed -n 'w /tmp/agws/o' a.m");
  EXPECT_BLOCK(@"sed '1r /etc/passwd' a.m");
  EXPECT_BLOCK(@"find . -exec id {} +");
  EXPECT_BLOCK(@"find . -delete");
  EXPECT_BLOCK(@"tar -cPf x.tar a.m");
  EXPECT_BLOCK(@"tar cPf x.tar a.m");
  EXPECT_BLOCK(@"cycript -p SpringBoard");
  EXPECT_BLOCK(@"./make");
  EXPECT_BLOCK(@"/usr/bin/make");
  EXPECT_BLOCK(@"date -s 2000-01-01");
  EXPECT_BLOCK(@"clang -fplugin=x.dylib a.m");
  printf("=== path jail ===\n");
  EXPECT_BLOCK(@"cat /etc/passwd");
  EXPECT_BLOCK(@"cat ../ws-evil/x");
  EXPECT_BLOCK(@"cat proj/../../ws-evil/x");
  EXPECT_BLOCK(@"cat link/passwd");           // symlink -> /etc
  EXPECT_BLOCK(@"cat evil/x");                // symlink -> sibling dir
  EXPECT_BLOCK(@"cat /tmp/agws/ws-evil/x");   // sibling with same prefix
  EXPECT_BLOCK(@"ls -I/etc");
  EXPECT_BLOCK(@"cd /etc");
  EXPECT_BLOCK(@"cd link");
  EXPECT_BLOCK(@"make DESTDIR=/usr/lib install");
  EXPECT_BLOCK(@"touch /tmp/agws/theos/bin/evil");   // protected theos dir
  EXPECT_BLOCK(@"cp a.m /tmp/agws/theos/bin/ldid");
  EXPECT_OK(@"cp a.m /tmp/agws/theos/projects/a.m", nil);   // other theos dirs stay writable
  printf("=== execution behaviour ===\n");
  { NSString *o=R(@"ls nonexistent_file"); BOOL ok=[o rangeOfString:@"[exit code"].location!=NSNotFound; printf("%s exit code reported: %s\n", ok?"PASS":"FAIL",[[o stringByReplacingOccurrencesOfString:@"\n" withString:@" | "] UTF8String]); if(!ok)fails++; }
  { // mkdir with no output must run exactly ONCE (old code ran it twice)
    NSString *o=R(@"mkdir once_only"); BOOL ok=[o hasPrefix:@"(no output, exit code 0)"]; printf("%s empty-output command runs once: %s\n", ok?"PASS":"FAIL",[o UTF8String]); if(!ok)fails++; }
  [d setObject:[NSNumber numberWithInt:1] forKey:@"agent_command_timeout"];
  { NSDate *t=[NSDate date]; NSString *o=R(@"sleep 20"); double el=-[t timeIntervalSinceNow]; BOOL ok=el<4 && [o rangeOfString:@"timed out"].location!=NSNotFound; printf("%s timeout kills hung command in %.1fs\n", ok?"PASS":"FAIL", el); if(!ok)fails++; }
  { NSDate *t=[NSDate date]; NSString *o=R(@"yes"); double el=-[t timeIntervalSinceNow]; BOOL ok=el<4 && [o length]<200000; printf("%s infinite output capped: %lu chars in %.1fs\n", ok?"PASS":"FAIL",(unsigned long)[o length], el); if(!ok)fails++; }
  { __block int n=0; BOOL (^c)(void)=^BOOL{ return ++n>3; }; NSDate *t=[NSDate date]; NSString *o=[AGShellRunner runCommandLine:@"sleep 20" workspace:@"/tmp/agws/ws" isCancelled:c]; double el=-[t timeIntervalSinceNow]; BOOL ok=el<3 && [o rangeOfString:@"cancelled"].location!=NSNotFound; printf("%s Stop button cancels running command in %.1fs\n", ok?"PASS":"FAIL", el); if(!ok)fails++; }
  system("head -c 3000000 /dev/zero | tr '\\0' 'a' > /tmp/agws/ws/big.txt; echo ENDMARK >> /tmp/agws/ws/big.txt");
  { NSString *o=R(@"cat big.txt"); BOOL ok=[o rangeOfString:@"ENDMARK"].location!=NSNotFound && [o rangeOfString:@"omitted"].location!=NSNotFound; printf("%s 3MB output keeps the END (%lu chars)\n", ok?"PASS":"FAIL",(unsigned long)[o length]); if(!ok)fails++; }
  printf("\n%s (%d failures)\n", fails?"SOME TESTS FAILED":"ALL PASSED", fails);
  return fails; }}
