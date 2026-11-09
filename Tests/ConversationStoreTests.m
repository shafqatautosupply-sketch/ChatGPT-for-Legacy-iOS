#import <Foundation/Foundation.h>
#include <unistd.h>
#import "AGConversationStore.h"
#import "AGConversation.h"
#import "AGMessage.h"
static int fails=0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
int main(){ @autoreleasepool {
  AGMessage *u=[AGMessage messageWithRole:@"user" content:@"hello there"]; AGMessage *a=[AGMessage messageWithRole:@"assistant" content:@"hi"];
  AGMessage *call=[AGMessage messageWithRole:@"assistant" content:@""]; call.toolCalls=[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"c",@"id",[NSDictionary dictionaryWithObjectsAndKeys:@"readFile",@"name",@"{}",@"arguments",nil],@"function",nil]];
  AGMessage *tool=[AGMessage messageWithRole:@"tool" content:@"x"]; tool.toolName=@"readFile"; tool.compacted=YES; AGMessage *note=[AGMessage messageWithRole:@"assistant" content:@"HTTP 429"]; note.localOnly=YES; a.omitted=NO;
  NSArray *msgs=[NSArray arrayWithObjects:u,a,call,tool,note,nil];
  [AGConversationStore saveMessages:msgs conversationID:@"conv-1" title:nil];
  sleep(1);
  [AGConversationStore saveMessages:msgs conversationID:@"conv-1" title:nil];
  AGConversation *c=[AGConversationStore conversationWithIdentifier:@"conv-1"];
  CHECK("round trip keeps all 5 messages incl. call-only message", [c.messages count]==5);
  AGMessage *rt=[c.messages objectAtIndex:2]; CHECK("call-only message (empty text) persisted with its toolCalls", [rt.toolCalls count]==1);
  CHECK("compacted / localOnly flags persisted", ((AGMessage*)[c.messages objectAtIndex:3]).compacted && ((AGMessage*)[c.messages objectAtIndex:4]).localOnly);
  AGConversation *listed=[[AGConversationStore loadConversations] objectAtIndex:0];
  CHECK("list uses index, has title+count without loading messages", [listed.title isEqual:@"hello there"] && listed.messageCount==5 && [listed.messages count]==0);
  CHECK("createdAt is preserved across saves (was reset every save)", ![c.creationDate isEqual:c.lastTimeEdited]);
  printf("   created=%s updated=%s\n",[c.creationDate UTF8String],[c.lastTimeEdited UTF8String]);
  // ordering: async burst must leave the NEWEST snapshot
  NSMutableArray *grow=[NSMutableArray arrayWithObject:u];
  for(int i=0;i<30;i++){ [grow addObject:[AGMessage messageWithRole:@"assistant" content:[NSString stringWithFormat:@"m%d",i]]]; [AGConversationStore saveMessagesAsync:grow conversationID:@"conv-2" title:nil]; }
  [AGConversationStore saveMessages:[NSArray arrayWithObject:u] conversationID:@"conv-3" title:nil]; // sync call drains the serial queue behind the async ones
  AGConversation *c2=[AGConversationStore conversationWithIdentifier:@"conv-2"]; CHECK("burst of async saves ends with the newest snapshot (31 msgs)", [c2.messages count]==31);
  // index self-heals when a file is deleted outside the app
  [[NSFileManager defaultManager] removeItemAtPath:[AGConversationStore pathForConversationIdentifier:@"conv-3"] error:nil];
  CHECK("index rebuilds when files change behind its back", [[AGConversationStore loadConversations] count]==2);
  [AGConversationStore deleteConversationWithIdentifier:@"conv-1"]; CHECK("delete updates index", [[AGConversationStore loadConversations] count]==1);
  // an only-local-notice conversation is not saved
  [AGConversationStore saveMessages:[NSArray arrayWithObject:note] conversationID:@"conv-9" title:nil]; CHECK("notice-only chat is not persisted", [AGConversationStore conversationWithIdentifier:@"conv-9"]==nil);
  CHECK("token saver defaults to ON, budget 24000", [AGConversationStore isTokenSaverEnabled] && [AGConversationStore contextTokenBudget]==24000);
  [AGConversationStore setTokenSaverEnabled:NO]; CHECK("disabling token saver = unlimited", [AGConversationStore contextTokenBudget]==0);
  printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
