// Runs the REAL agent loop (AGChatClient) against a fake server. Run with NSZombieEnabled=YES so that
// any message to a freed object aborts instead of "mostly working".
#import <Foundation/Foundation.h>
#import "AGChatClient.h"
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
  BOOL openAI = [mode hasPrefix:@"openai"];
  [d setObject:[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"p1",@"identifier",@"Fake",@"providerName",
      (openAI ? @"http://127.0.0.1:8082/v1" : @"http://127.0.0.1:8082"),@"baseURL",@"m",@"c-aiModel",
      ([mode isEqual:@"openai-401"] ? @"WRONG" : @"KEY"),@"apiKey",(openAI ? @"openai" : @"gemini"),@"providerType",nil]] forKey:@"providerProfiles"];
  [d setObject:@"p1" forKey:@"activeProviderProfileID"];
  if ([mode isEqual:@"steps"]) [d setInteger:2 forKey:@"agent_max_steps"];
  [AGChatClient setAgentModeEnabled:![mode isEqual:@"openai-pure"]];
  Collector *c = [[Collector alloc] init];
  [[NSNotificationCenter defaultCenter] addObserver:c selector:@selector(onMessage:) name:AGAPIResponseNotification object:nil];
  AGMessage *u = [AGMessage messageWithRole:@"user" content:@"analyse the project"];
  [AGChatClient createChatCompletionWithMessages:[NSArray arrayWithObject:u]];   // test shim runs the loop synchronously
  int calls = 0, tools = 0, texts = 0; for (AGMessage *m in c->got) { if ([m.role isEqual:@"tool"]) tools++; else if ([m.toolCalls count]) calls++; else texts++; }
  printf("   received %lu messages: %d tool calls, %d tool results, %d text\n", (unsigned long)[c->got count], calls, tools, texts);
  AGMessage *last = [c->got lastObject];
  if ([c->got count] <= 1 && last) printf("   (last message%s: %s)\n", last.localOnly ? " [notice]" : "", [last.content UTF8String]);
  if ([mode isEqual:@"same"]) {
    CHECK("stuck model (same call + same result) is stopped after 3 tries", tools == 3 && last.localOnly && [last.content rangeOfString:@"repeated the same tool call"].location != NSNotFound);
  } else if ([mode isEqual:@"steps"]) {
    CHECK("step limit stops the loop with a notice", tools == 2 && last.localOnly && [last.content rangeOfString:@"Stopped after 2 steps"].location != NSNotFound);
  } else if ([mode isEqual:@"openai-401"]) {
    CHECK("OpenAI error body surfaces as a readable notice (HTTP 401 + server message), no crash", [c->got count] == 1 && last.localOnly && [last.content rangeOfString:@"HTTP 401"].location != NSNotFound && [last.content rangeOfString:@"Incorrect API key"].location != NSNotFound);
  } else if ([mode isEqual:@"openai-pure"]) {
    CHECK("pure chat on OpenAI: one text answer, no tools were sent", [c->got count] == 1 && tools == 0 && !last.localOnly && [last.content isEqual:@"All done."]);
  } else if ([mode isEqual:@"openai"]) {
    CHECK("OpenAI-compatible loop: 3 tool calls, 3 results, final answer (server validated every request)", calls == 3 && tools == 3 && texts == 1);
    AGMessage *r = [c->got objectAtIndex:1]; CHECK("tool output is the real command output", [r.content isEqual:@"step1"]);
    AGMessage *a1 = [c->got objectAtIndex:0]; CHECK("tool call id from the server is kept", [[[a1.toolCalls objectAtIndex:0] objectForKey:@"id"] isEqual:@"call_1"] && [r.toolCallID isEqual:@"call_1"]);
    NSDictionary *u = [AGChatClient lastUsage]; CHECK("usage mapped (prompt 100, cached 64, output 5)", [[u objectForKey:@"prompt"] intValue] == 100 && [[u objectForKey:@"cached"] intValue] == 64 && [[u objectForKey:@"output"] intValue] == 5);
  } else {
    CHECK("loop survives several tool calls (3 calls, 3 results, 1 final answer)", calls == 3 && tools == 3 && texts == 1);
    AGMessage *r = [c->got objectAtIndex:1]; CHECK("tool result is the real command output", [r.content isEqual:@"step1"]);
    CHECK("token usage recorded", [[[AGChatClient lastUsage] objectForKey:@"prompt"] intValue] == 100);
  }
  printf("\n%s (%d failures)\n", fails ? "SOME FAILED" : "ALL PASSED", fails); return fails; }}
