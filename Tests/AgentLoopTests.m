// Runs the REAL agent loop (AGGeminiClient) against a fake server. Run with NSZombieEnabled=YES so that
// any message to a freed object aborts instead of "mostly working".
#import <Foundation/Foundation.h>
#import "AGGeminiClient.h"
#import "AGProviderConfig.h"
#import "AGMessage.h"
static int fails = 0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
@interface Collector : NSObject { @public NSMutableArray *got; } @end
@implementation Collector
- (id)init { if ((self = [super init])) got = [[NSMutableArray alloc] init]; return self; }
- (void)onMessage:(NSNotification *)n { [got addObject:[n object]]; }
@end
int main(int argc, char **argv){ @autoreleasepool {
  NSString *mode = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : @"normal";
  system("rm -rf /tmp/agloop; mkdir -p /tmp/agloop/ws /tmp/agloop/theos");
  NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
  [d setObject:@"/tmp/agloop/ws" forKey:@"agent_workspace_dir"]; [d setObject:@"/tmp/agloop/theos" forKey:@"agent_theos_dir"];
  [d setObject:[NSNumber numberWithDouble:0] forKey:@"agent_min_request_interval"];
  [d setObject:[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"p1",@"identifier",@"Fake",@"providerName",@"http://127.0.0.1:8082",@"baseURL",@"m",@"c-aiModel",@"KEY",@"apiKey",nil]] forKey:@"providerProfiles"];
  [d setObject:@"p1" forKey:@"activeProviderProfileID"];
  if ([mode isEqual:@"steps"]) [d setInteger:2 forKey:@"agent_max_steps"];
  [AGGeminiClient setAgentModeEnabled:YES];
  Collector *c = [[Collector alloc] init];
  [[NSNotificationCenter defaultCenter] addObserver:c selector:@selector(onMessage:) name:AGAPIResponseNotification object:nil];
  AGMessage *u = [AGMessage messageWithRole:@"user" content:@"analyse the project"];
  [AGGeminiClient createChatCompletionWithMessages:[NSArray arrayWithObject:u]];   // test shim runs the loop synchronously
  int calls = 0, tools = 0, texts = 0; for (AGMessage *m in c->got) { if ([m.role isEqual:@"tool"]) tools++; else if ([m.toolCalls count]) calls++; else texts++; }
  printf("   received %lu messages: %d tool calls, %d tool results, %d text\n", (unsigned long)[c->got count], calls, tools, texts);
  AGMessage *last = [c->got lastObject];
  if ([mode isEqual:@"same"]) {
    CHECK("stuck model (same call + same result) is stopped after 3 tries", tools == 3 && last.localOnly && [last.content rangeOfString:@"repeated the same tool call"].location != NSNotFound);
  } else if ([mode isEqual:@"steps"]) {
    CHECK("step limit stops the loop with a notice", tools == 2 && last.localOnly && [last.content rangeOfString:@"Stopped after 2 steps"].location != NSNotFound);
  } else {
    CHECK("loop survives several tool calls (3 calls, 3 results, 1 final answer)", calls == 3 && tools == 3 && texts == 1);
    AGMessage *r = [c->got objectAtIndex:1]; CHECK("tool result is the real command output", [r.content isEqual:@"step1"]);
    CHECK("token usage recorded", [[[AGGeminiClient lastUsage] objectForKey:@"prompt"] intValue] == 100);
  }
  printf("\n%s (%d failures)\n", fails ? "SOME FAILED" : "ALL PASSED", fails); return fails; }}
