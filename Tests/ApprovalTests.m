#import <Foundation/Foundation.h>
#import "AGApproval.h"
#import "AGAgentTools.h"
#import "AGShellRunner.h"
#import "AGGuardrails.h"
#include <Block.h>
static int fails = 0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
#define WS @"/tmp/agws/ws"

static NSString *R(NSString *c){ return [AGShellRunner runCommandLine:c workspace:WS isCancelled:nil]; }
static NSString *D(NSString *p, BOOL rec){ return [AGAgentTools deleteFileAtPath:p recursive:rec workspace:WS isCancelled:nil]; }
static BOOL Exists(NSString *p){ struct stat st; return lstat([p fileSystemRepresentation], &st) == 0; }
static void Sh(NSString *c){ system([c UTF8String]); }

// Records every prompt and answers with `answer` (or never, if answer < 0).
static int g_asked = 0; static int g_answer = 1; static NSString *g_lastTitle = nil, *g_lastDetail = nil, *g_lastLabel = nil;
static void Install(int answer){
  g_asked = 0; g_answer = answer;
  [AGApproval setHandler:^(NSString *title, NSString *detail, NSString *label, AGApprovalResponder respond){
    g_asked++; g_lastTitle = [title copy]; g_lastDetail = [detail copy]; g_lastLabel = [label copy];
    if (g_answer >= 0) respond((AGApprovalChoice)g_answer);
  }];
}

// Answers from another thread after a delay, like a person tapping a button.
@interface Later : NSObject { @public AGApprovalResponder r; double s; int c; }
+ (void)answerIn:(NSTimeInterval)seconds with:(AGApprovalResponder)respond choice:(int)choice;
@end
@implementation Later
- (void)run { @autoreleasepool {
  [NSThread sleepForTimeInterval:s];
  r((AGApprovalChoice)c); Block_release(r);
}}
+ (void)answerIn:(NSTimeInterval)seconds with:(AGApprovalResponder)respond choice:(int)choice {
  Later *l=[[Later alloc] init]; l->r=Block_copy(respond); l->s=seconds; l->c=choice;
  [NSThread detachNewThreadSelector:@selector(run) toTarget:l withObject:nil];
}
@end

static int g_abandoned = 0;
@interface Obs : NSObject @end
@implementation Obs - (void)abandoned:(NSNotification *)n { g_abandoned++; } @end

int main(){ @autoreleasepool {
  Sh(@"rm -rf /tmp/agws; mkdir -p /tmp/agws/ws/proj/sub /tmp/agws/ws-evil /tmp/agws/theos/bin /tmp/agws/theos/projects");
  Sh(@"echo secret > /tmp/agws/ws-evil/x; echo hi > /tmp/agws/ws/f.txt; echo a > /tmp/agws/ws/proj/a.txt; echo b > /tmp/agws/ws/proj/sub/b.txt; echo m > /tmp/agws/ws/proj/Makefile");
  Sh(@"printf 'print(\"hello from python\")\\nopen(\"/tmp/agws/ws/marker\",\"w\").write(\"ran\")\\n' > /tmp/agws/ws/hello.py");
  Sh(@"ln -s /etc /tmp/agws/ws/link; ln -s /tmp/agws/ws/proj /tmp/agws/ws/inlink; mkdir -p /tmp/agws/ws/proj/.git; echo g > /tmp/agws/ws/proj/.git/HEAD");
  NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
  [d setObject:WS forKey:@"agent_workspace_dir"]; [d setObject:@"/tmp/agws/theos" forKey:@"agent_theos_dir"];
  Obs *obs=[[Obs alloc] init]; [[NSNotificationCenter defaultCenter] addObserver:obs selector:@selector(abandoned:) name:AGApprovalAbandonedNotification object:nil];

  printf("=== confirmation for make / python ===\n");
  CHECK("python3 is on the default allowed list", [[AGGuardrails defaultAllowedBinaries] containsObject:@"python3"]);
  CHECK("make, python, python3 are gated", [AGApproval argvNeedsApproval:[NSArray arrayWithObjects:@"make",nil]] && [AGApproval argvNeedsApproval:[NSArray arrayWithObjects:@"python",nil]] && [AGApproval argvNeedsApproval:[NSArray arrayWithObjects:@"python3",@"x.py",nil]]);
  CHECK("echo/ls/cat are not gated", ![AGApproval argvNeedsApproval:[NSArray arrayWithObjects:@"echo",@"x",nil]] && ![AGApproval argvNeedsApproval:[NSArray arrayWithObjects:@"cat",nil]]);

  [AGApproval setHandler:nil]; unlink("/tmp/agws/ws/marker");
  NSString *o = R(@"python3 hello.py");
  CHECK("no approval UI => python denied (fail safe)", [o hasPrefix:@"[GUARDRAIL]"] && !Exists(@"/tmp/agws/ws/marker"));
  CHECK("no approval UI => echo still works", [R(@"echo ok") isEqualToString:@"ok"]);

  Install(AGApprovalDeny);
  o = R(@"python3 hello.py");
  CHECK("user taps Deny => script not run, model told not to retry", [o rangeOfString:@"denied"].location!=NSNotFound && [o rangeOfString:@"Do not retry"].location!=NSNotFound && !Exists(@"/tmp/agws/ws/marker") && g_asked==1);
  CHECK("prompt names the binary", [g_lastTitle rangeOfString:@"python3"].location!=NSNotFound);
  CHECK("prompt shows the script's first lines", [g_lastDetail rangeOfString:@"hello from python"].location!=NSNotFound && [g_lastDetail rangeOfString:@"hello.py"].location!=NSNotFound);
  CHECK("prompt warns python can do more than shown", [g_lastDetail rangeOfString:@"anything this app can do"].location!=NSNotFound);
  CHECK("prompt stays short enough for an alert", [g_lastDetail length] <= 710);

  Install(AGApprovalAllowOnce);
  o = R(@"python3 hello.py");
  CHECK("Allow once => script runs and its output comes back", [o rangeOfString:@"hello from python"].location!=NSNotFound && Exists(@"/tmp/agws/ws/marker") && g_asked==1);
  o = R(@"python3 hello.py");
  CHECK("Allow once asks again next time", g_asked==2);
  CHECK("task label is offered", [g_lastLabel rangeOfString:@"python3"].location!=NSNotFound);

  Install(AGApprovalAllowForTask); [AGApproval resetTaskApprovals];
  R(@"python3 hello.py"); R(@"python3 hello.py"); R(@"python3 hello.py");
  CHECK("Allow for this task: asked once, then remembered", g_asked==1);
  [AGApproval resetTaskApprovals]; R(@"python3 hello.py");
  CHECK("allowance ends when the task ends (reset)", g_asked==2);
  [AGApproval resetTaskApprovals];

  // python -c shows the code
  Install(AGApprovalDeny);
  R(@"python3 -c 'import os; os.system(\"id\")'");
  CHECK("python -c: the code itself is shown", [g_lastDetail rangeOfString:@"os.system"].location!=NSNotFound);
  // make shows the Makefile
  R(@"cd proj && make");
  CHECK("make: asks, and shows the Makefile", g_asked==2 && [g_lastTitle rangeOfString:@"make"].location!=NSNotFound && [g_lastDetail rangeOfString:@"Makefile can run any program"].location!=NSNotFound);
  // a denied make in a chain stops the chain
  Install(AGApprovalDeny); R(@"echo a && python3 hello.py && echo b");
  CHECK("denial stops the && chain after the gated command", g_asked==1);

  [d setBool:NO forKey:@"agent_confirm_code"]; [AGApproval setHandler:nil]; unlink("/tmp/agws/ws/marker");
  R(@"python3 hello.py");
  CHECK("confirmation switched off => runs without a prompt", Exists(@"/tmp/agws/ws/marker"));
  [d removeObjectForKey:@"agent_confirm_code"];

  printf("=== waiting behaviour ===\n");
  g_answer=-1; g_asked=0; [AGApproval setHandler:^(NSString *t, NSString *dt, NSString *l, AGApprovalResponder respond){ g_asked++; [Later answerIn:0.4 with:respond choice:AGApprovalAllowOnce]; }];
  NSDate *t0=[NSDate date]; unlink("/tmp/agws/ws/marker"); o=R(@"python3 hello.py"); NSTimeInterval dt=-[t0 timeIntervalSinceNow];
  CHECK("worker thread waits for a late answer, then runs", Exists(@"/tmp/agws/ws/marker") && dt>=0.35 && dt<5);

  [d setDouble:1.0 forKey:@"agent_approval_timeout"]; Install(-1); unlink("/tmp/agws/ws/marker");
  t0=[NSDate date]; o=R(@"python3 hello.py"); dt=-[t0 timeIntervalSinceNow];
  CHECK("no answer => denied after the timeout", [o rangeOfString:@"No answer"].location!=NSNotFound && !Exists(@"/tmp/agws/ws/marker") && dt>=0.9 && dt<6);
  [d removeObjectForKey:@"agent_approval_timeout"];

  g_abandoned=0; Install(-1); __block int polls=0;
  o=[AGShellRunner runCommandLine:@"python3 hello.py" workspace:WS isCancelled:^BOOL{ return ++polls > 3; }];
  CHECK("Stop while waiting => cancelled, prompt withdrawn", [o isEqualToString:@"[cancelled]"] && g_abandoned==1 && !Exists(@"/tmp/agws/ws/marker"));

  printf("=== deleteFile ===\n");
  Install(AGApprovalAllowOnce);
  o = D(@"f.txt", NO);
  CHECK("file is moved to the trash, not destroyed", [o hasPrefix:@"Success"] && !Exists(@"/tmp/agws/ws/f.txt"));
  NSString *trashDir = @"/tmp/agws/ws/.agent-trash"; NSArray *batches=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashDir error:nil];
  NSString *batch = nil; for (NSString *b in batches) if (![b isEqualToString:@"log.txt"]) batch=b;
  CHECK("it is in .agent-trash/<stamp>/f.txt with its content", batch!=nil && [[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/%@/f.txt",trashDir,batch] encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"hi\n"]);
  CHECK("the result tells the model how to restore", [o rangeOfString:@"Restore with: mv"].location!=NSNotFound && [o rangeOfString:@"Nothing was permanently deleted"].location!=NSNotFound);
  CHECK("log.txt records the original path", [[NSString stringWithContentsOfFile:[trashDir stringByAppendingString:@"/log.txt"] encoding:NSUTF8StringEncoding error:nil] rangeOfString:@"f.txt"].location!=NSNotFound);
  CHECK("delete prompt shows the path", g_asked==1 && [g_lastDetail rangeOfString:@"f.txt"].location!=NSNotFound && g_lastLabel==nil);
  o = R([NSString stringWithFormat:@"mv .agent-trash/%@/f.txt f.txt", batch]);
  CHECK("restore with mv works through the normal jail", Exists(@"/tmp/agws/ws/f.txt"));

  o = D(@"proj", NO);
  CHECK("folder needs recursive=true, says how many items", [o hasPrefix:@"Error"] && [o rangeOfString:@"recursive=true"].location!=NSNotFound && Exists(@"/tmp/agws/ws/proj/a.txt"));
  Install(AGApprovalDeny); o = D(@"proj/sub/", YES);
  CHECK("Deny => nothing moved", [o rangeOfString:@"denied"].location!=NSNotFound && Exists(@"/tmp/agws/ws/proj/sub/b.txt"));
  Install(AGApprovalAllowOnce); o = D(@"proj/sub/", YES);
  CHECK("trailing slash + recursive moves the folder with its contents", [o hasPrefix:@"Success"] && !Exists(@"/tmp/agws/ws/proj/sub") && [g_lastDetail rangeOfString:@"folder"].location!=NSNotFound);
  o = D(@"proj/../hello.py", NO); CHECK("a/../b form resolves correctly", [o hasPrefix:@"Success"] && !Exists(@"/tmp/agws/ws/hello.py"));
  o = D(@"nope.txt", NO); CHECK("missing file reported", [o hasPrefix:@"Error"] && [o rangeOfString:@"does not exist"].location!=NSNotFound);

  printf("=== deleteFile: things that must never work ===\n");
  int before = g_asked;
  CHECK("outside the jail (../ws-evil/x)", [D(@"../ws-evil/x", NO) rangeOfString:@"BLOCKED"].location!=NSNotFound && Exists(@"/tmp/agws/ws-evil/x"));
  CHECK("absolute /etc/passwd", [D(@"/etc/passwd", NO) rangeOfString:@"BLOCKED"].location!=NSNotFound);
  CHECK("through a symlink that leaves the jail (link/passwd)", [D(@"link/passwd", NO) rangeOfString:@"BLOCKED"].location!=NSNotFound);
  CHECK("workspace root by '.'", [D(@".", YES) hasPrefix:@"Error"] && Exists(@"/tmp/agws/ws"));
  CHECK("workspace root by absolute path", [D(@"/tmp/agws/ws", YES) rangeOfString:@"BLOCKED"].location!=NSNotFound && Exists(@"/tmp/agws/ws/proj"));
  CHECK("'..' and '/'", [D(@"..", YES) hasPrefix:@"Error"] && [D(@"/", YES) hasPrefix:@"Error"]);
  CHECK("the Theos folder itself", [D(@"/tmp/agws/theos", YES) rangeOfString:@"BLOCKED"].location!=NSNotFound && Exists(@"/tmp/agws/theos/bin"));
  CHECK("the parent of both roots (/tmp/agws)", [D(@"/tmp/agws", YES) rangeOfString:@"BLOCKED"].location!=NSNotFound);
  CHECK("Theos bin (read-only)", [D(@"/tmp/agws/theos/bin", YES) rangeOfString:@"BLOCKED"].location!=NSNotFound && Exists(@"/tmp/agws/theos/bin"));
  CHECK("a file inside Theos bin", [D(@"/tmp/agws/theos/bin/ldid", NO) hasPrefix:@"Error"]);
  CHECK(".git folder", [D(@"proj/.git", YES) rangeOfString:@"protected"].location!=NSNotFound && Exists(@"/tmp/agws/ws/proj/.git/HEAD"));
  CHECK("a file inside .git", [D(@"proj/.git/HEAD", NO) rangeOfString:@"protected"].location!=NSNotFound);
  CHECK("the trash folder and what is in it", [D(@".agent-trash", YES) rangeOfString:@"protected"].location!=NSNotFound && [D([@".agent-trash/" stringByAppendingString:batch], YES) rangeOfString:@"protected"].location!=NSNotFound);
  CHECK("none of the refusals bothered the user with a prompt", g_asked==before);
  CHECK("rm is refused when the kernel sandbox is not active (host has none), and nothing is deleted", [R(@"rm -rf proj") rangeOfString:@"only available while the kernel sandbox is active"].location!=NSNotFound && Exists(@"/tmp/agws/ws/proj"));

  printf("=== deleteFile: symlinks, Theos, switches ===\n");
  o = D(@"inlink", NO);
  CHECK("a symlink to a folder inside the jail: only the LINK moves, the folder stays", [o hasPrefix:@"Success"] && !Exists(@"/tmp/agws/ws/inlink") && Exists(@"/tmp/agws/ws/proj/a.txt"));
  o = D(@"link", NO);
  CHECK("a symlink that points outside: the link moves, /etc is untouched", [o hasPrefix:@"Success"] && !Exists(@"/tmp/agws/ws/link") && Exists(@"/etc/passwd"));
  Sh(@"echo t > /tmp/agws/theos/projects/t.txt");
  o = D(@"/tmp/agws/theos/projects/t.txt", NO);
  CHECK("a file in an unprotected Theos folder may go to the workspace trash", [o hasPrefix:@"Success"] && !Exists(@"/tmp/agws/theos/projects/t.txt"));

  [AGApproval setHandler:nil]; Sh(@"echo z > /tmp/agws/ws/z.txt");
  o = D(@"z.txt", NO); CHECK("no approval UI + confirmation on => not deleted (fail safe)", [o hasPrefix:@"[GUARDRAIL]"] && Exists(@"/tmp/agws/ws/z.txt"));
  [d setBool:NO forKey:@"agent_confirm_delete"];
  o = D(@"z.txt", NO); CHECK("confirmation switched off => still goes to the trash, no prompt", [o hasPrefix:@"Success"] && !Exists(@"/tmp/agws/ws/z.txt"));
  [d removeObjectForKey:@"agent_confirm_delete"];

  printf("=== tool plumbing ===\n");
  Install(AGApprovalAllowOnce); Sh(@"echo q > /tmp/agws/ws/q.txt; mkdir -p /tmp/agws/ws/qd; echo 1 > /tmp/agws/ws/qd/1");
  o = [AGAgentTools executeToolNamed:@"deleteFile" arguments:[NSDictionary dictionaryWithObject:@"q.txt" forKey:@"filepath"] workspace:WS isCancelled:nil];
  CHECK("dispatcher: deleteFile works", [o hasPrefix:@"Success"]);
  o = [AGAgentTools executeToolNamed:@"deleteFile" arguments:[NSDictionary dictionaryWithObjectsAndKeys:@"qd",@"filepath",@"true",@"recursive",nil] workspace:WS isCancelled:nil];
  CHECK("dispatcher: recursive given as the string 'true'", [o hasPrefix:@"Success"]);
  CHECK("dispatcher: missing filepath", [[AGAgentTools executeToolNamed:@"deleteFile" arguments:nil workspace:WS isCancelled:nil] hasPrefix:@"Error"]);
  CHECK("dispatcher: number as filepath doesn't crash", [[AGAgentTools executeToolNamed:@"deleteFile" arguments:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:7] forKey:@"filepath"] workspace:WS isCancelled:nil] hasPrefix:@"Error"]);
  NSString *decl=[[AGAgentTools toolDeclarations] description];
  CHECK("deleteFile is declared to the model", [decl rangeOfString:@"deleteFile"].location!=NSNotFound);
  printf("tool declaration size: %lu chars\n",(unsigned long)[decl length]);


  printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
