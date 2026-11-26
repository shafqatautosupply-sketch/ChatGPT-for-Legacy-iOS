#import <Foundation/Foundation.h>
#import "AGSandbox.h"
#import "AGGuardrails.h"
static int fails = 0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
#define HAS(s, sub) ([(s) rangeOfString:(sub)].location != NSNotFound)

// Only the profile text is tested here (the host has no sandbox_init). That the kernel
// really enforces it is checked on the device by the self-test in +prepareForWorkspace and
// by the sbtest probe described in Docs/SECURITY.md.
int main(){ @autoreleasepool {
  NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
  system("rm -rf /tmp/agsb; mkdir -p /tmp/agsb/ws /tmp/agsb/theos /tmp/agsb/extra");
  [d setObject:@"/tmp/agsb/theos" forKey:@"agent_theos_dir"];
  NSString *why = nil;
  NSString *p = [AGSandbox profileForWorkspace:@"/tmp/agsb/ws" reason:&why];
  CHECK("profile is built for a normal workspace", p != nil);
  CHECK("starts with version + allow default", [p hasPrefix:@"(version 1)(allow default)"]);
  CHECK("network is denied", HAS(p, @"(deny network*)"));
  CHECK("writes: deny all, then allow only the workspace and /dev/null",
        HAS(p, @"(deny file-write*)(allow file-write* (subpath \"/tmp/agsb/ws\"))(allow file-write* (literal \"/dev/null\"))"));
  CHECK("reads: home denied, workspace re-allowed AFTER the deny (later rule wins)",
        HAS(p, @"(deny file-read* (subpath \"/private/var/mobile\"))(allow file-read* (subpath \"/tmp/agsb/ws\"))"));
  CHECK("Theos is readable, not writable", HAS(p, @"(allow file-read* (subpath \"/tmp/agsb/theos\"))") && !HAS(p, @"(allow file-write* (subpath \"/tmp/agsb/theos\"))"));
  CHECK("mach lookups and task ports denied", HAS(p, @"(deny mach-lookup)") && HAS(p, @"(deny mach-priv-task-port)"));
  CHECK("no exec rules (this kernel ignores them; do not give false comfort)", !HAS(p, @"process-exec"));

  [d setObject:[NSArray arrayWithObjects:@"/tmp/agsb/extra", @"/tmp/agsb/missing", @"relative/dir", nil] forKey:@"agent_sandbox_read_dirs"];
  p = [AGSandbox profileForWorkspace:@"/tmp/agsb/ws" reason:&why];
  CHECK("extra read dir that exists is added", HAS(p, @"(allow file-read* (subpath \"/tmp/agsb/extra\"))"));
  CHECK("missing and relative extra dirs are ignored", !HAS(p, @"missing") && !HAS(p, @"relative"));

  [d setObject:[NSNumber numberWithBool:NO] forKey:@"agent_sandbox_deny_network"];
  [d setObject:[NSNumber numberWithBool:NO] forKey:@"agent_sandbox_deny_mach"];
  p = [AGSandbox profileForWorkspace:@"/tmp/agsb/ws" reason:&why];
  CHECK("switches: network and mach-lookup denials can be turned off", !HAS(p, @"(deny network*)") && !HAS(p, @"(deny mach-lookup)") && HAS(p, @"(deny mach-priv-task-port)"));
  [d removeObjectForKey:@"agent_sandbox_deny_network"]; [d removeObjectForKey:@"agent_sandbox_deny_mach"];

  why = nil;
  CHECK("workspace '/' is refused", [AGSandbox profileForWorkspace:@"/" reason:&why] == nil && why != nil);
  why = nil;
  CHECK("the home folder itself is refused", [AGSandbox profileForWorkspace:@"/private/var/mobile" reason:&why] == nil && why != nil);
  why = nil;
  CHECK("a parent of the home folder is refused", [AGSandbox profileForWorkspace:@"/private/var" reason:&why] == nil && why != nil);
  system("mkdir -p '/tmp/agsb/we\"ird' '/tmp/agsb/back\\slash'");
  why = nil;
  CHECK("a quote in the workspace path cannot break out of the profile", [AGSandbox profileForWorkspace:@"/tmp/agsb/we\"ird" reason:&why] == nil && why != nil);
  why = nil;
  CHECK("a backslash in the workspace path is refused", [AGSandbox profileForWorkspace:@"/tmp/agsb/back\\slash" reason:&why] == nil && why != nil);

  [d setObject:[NSNumber numberWithBool:NO] forKey:@"agent_sandbox"];
  why = nil; NSString *prof = nil;
  CHECK("setting agent_sandbox=NO turns it off", ![AGSandbox prepareForWorkspace:@"/tmp/agsb/ws" profile:&prof reason:&why] && prof == nil && HAS(why, @"turned off"));
  CHECK("rm is on the default allowed list and gated", [[AGGuardrails defaultAllowedBinaries] containsObject:@"rm"]);
  printf(fails ? "SOME FAILED (%d failures)\n" : "ALL PASSED (%d failures)\n", fails);
  return fails ? 1 : 0;
}}
