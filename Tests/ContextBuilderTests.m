#import <Foundation/Foundation.h>
#import "AGContextBuilder.h"
#import "AGMessage.h"
static int fails=0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)

static AGMessage *U(NSString *t){ return [AGMessage messageWithRole:@"user" content:t]; }
static AGMessage *A(NSString *t){ return [AGMessage messageWithRole:@"assistant" content:t]; }
static AGMessage *Call(NSString *name, NSDictionary *args, NSString *sig){
  NSData *j=[NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
  NSString *s=[[[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] autorelease];
  AGMessage *m=[AGMessage messageWithRole:@"assistant" content:[NSString stringWithFormat:@"Tool Call: %@\nArguments: %@",name,s]]; // legacy synthetic display text
  NSMutableDictionary *tc=[NSMutableDictionary dictionaryWithObjectsAndKeys:@"c1",@"id",@"function",@"type",[NSDictionary dictionaryWithObjectsAndKeys:name,@"name",s,@"arguments",nil],@"function",nil];
  if(sig)[tc setObject:sig forKey:@"thoughtSignature"];
  m.toolCalls=[NSArray arrayWithObject:tc]; return m; }
static AGMessage *T(NSString *name, NSString *out){ AGMessage *m=[AGMessage messageWithRole:@"tool" content:out]; m.toolName=name; return m; }

// Structural validity as Gemini enforces it.
static BOOL Valid(NSArray *contents, NSString **why){
  if([contents count]==0){*why=@"empty";return NO;}
  if(![[[contents objectAtIndex:0] objectForKey:@"role"] isEqualToString:@"user"]){*why=@"first not user";return NO;}
  for(NSUInteger i=0;i<[contents count];i++){ NSDictionary *c=[contents objectAtIndex:i]; NSArray *parts=[c objectForKey:@"parts"];
    if([parts count]==0){*why=@"empty parts";return NO;}
    NSUInteger calls=0,resps=0; for(NSDictionary *p in parts){ if([p objectForKey:@"functionCall"])calls++; if([p objectForKey:@"functionResponse"])resps++; }
    if(calls>0){ if(![[c objectForKey:@"role"] isEqualToString:@"model"]){*why=@"call in non-model";return NO;}
      if(i+1>=[contents count]){*why=@"call without response";return NO;}
      NSArray *np=[[contents objectAtIndex:i+1] objectForKey:@"parts"]; NSUInteger nr=0; for(NSDictionary *p in np) if([p objectForKey:@"functionResponse"])nr++;
      if(nr!=calls||[np count]!=nr){*why=@"call/response count mismatch";return NO;} }
    if(resps>0){ if(i==0||![[[contents objectAtIndex:i-1] objectForKey:@"role"] isEqualToString:@"model"]){*why=@"orphan response";return NO;} } }
  return YES; }
static NSString *J(id o){ NSData *d=[NSJSONSerialization dataWithJSONObject:o options:0 error:nil]; return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease]; }
static NSDictionary *Build(NSArray *m, BOOL pure, NSUInteger budget){ return [AGContextBuilder payloadForMessages:m pureChat:pure systemPrompt:@"sys" toolDeclarations:[NSArray arrayWithObject:[NSDictionary dictionaryWithObject:@"x" forKey:@"y"]] tokenBudget:budget generationConfig:nil]; }

int main(){ @autoreleasepool {
 NSString *why=@"";
 printf("=== repair: cases that used to make Gemini return HTTP 400 forever ===\n");
 { // user pressed Stop between call and response -> unanswered call
   NSArray *m=[NSArray arrayWithObjects:U(@"build it"), Call(@"runShellCommand",[NSDictionary dictionaryWithObject:@"make" forKey:@"command"],nil), U(@"never mind, do X"), nil];
   NSDictionary *p=Build(m,NO,0); CHECK("unanswered tool call gets a filler response", Valid([p objectForKey:@"contents"],&why)); if(!Valid([p objectForKey:@"contents"],&why))printf("   why: %s\n",[why UTF8String]); }
 { // orphan tool message at start (history trimmed) + a local error notice
   AGMessage *err=A(@"HTTP 429 quota exceeded"); err.localOnly=YES;
   NSArray *m=[NSArray arrayWithObjects:T(@"readFile",@"orphan"), U(@"hi"), err, A(@"hello"), nil];
   NSDictionary *p=Build(m,NO,0); NSString *js=J(p);
   CHECK("orphan tool response dropped", Valid([p objectForKey:@"contents"],&why) && [js rangeOfString:@"orphan"].location==NSNotFound);
   CHECK("local-only error notice NOT sent to model", [js rangeOfString:@"quota"].location==NSNotFound); }
 { // call with 2 calls but only 1 response
   AGMessage *two=Call(@"runShellCommand",[NSDictionary dictionaryWithObject:@"ls" forKey:@"command"],nil);
   NSMutableArray *tcs=[NSMutableArray arrayWithArray:two.toolCalls]; [tcs addObject:[tcs objectAtIndex:0]]; two.toolCalls=tcs;
   NSArray *m=[NSArray arrayWithObjects:U(@"go"), two, T(@"runShellCommand",@"a"), nil];
   CHECK("2 calls / 1 response is repaired", Valid([Build(m,NO,0) objectForKey:@"contents"],&why)); }
 { // legacy synthetic text not duplicated
   NSArray *m=[NSArray arrayWithObjects:U(@"go"), Call(@"readFile",[NSDictionary dictionaryWithObject:@"a.m" forKey:@"filepath"],@"SIG"), T(@"readFile",@"x"), nil];
   NSString *js=J(Build(m,NO,0)); CHECK("synthetic 'Tool Call:' text not sent as a second copy", [js rangeOfString:@"Tool Call:"].location==NSNotFound);
   { BOOL found=NO; for(NSDictionary *c in [Build(m,NO,0) objectForKey:@"contents"]) for(NSDictionary *pt in [c objectForKey:@"parts"]) if([pt objectForKey:@"functionCall"] && [[pt objectForKey:@"thoughtSignature"] isEqual:@"SIG"]) found=YES; CHECK("thoughtSignature preserved on the functionCall part", found); } }
 { // pure chat after an agent session: no function parts at all
   NSArray *m=[NSArray arrayWithObjects:U(@"go"), Call(@"readFile",[NSDictionary dictionaryWithObject:@"a.m" forKey:@"filepath"],nil), T(@"readFile",@"x"), A(@"done"), U(@"thanks"), nil];
   NSDictionary *p=Build(m,YES,0); NSString *js=J(p);
   CHECK("pure-chat after agent session: valid, no functionCall/Response, no tools", Valid([p objectForKey:@"contents"],&why) && [js rangeOfString:@"function"].location==NSNotFound && ![p objectForKey:@"tools"]); }
 { AGMessage *sys=[AGMessage messageWithRole:@"system" content:@"extra"]; NSDictionary *p=Build([NSArray arrayWithObjects:sys,U(@"hi"),nil],NO,0);
   CHECK("system messages merged into system_instruction", [J([p objectForKey:@"system_instruction"]) rangeOfString:@"extra"].location!=NSNotFound); }

 printf("=== token budget ===\n");
 NSMutableString *bigOut=[NSMutableString string]; for(int i=0;i<200;i++)[bigOut appendString:@"clang: compiling Tweak.xm warning: unused variable foo\n"]; // ~10KB
 NSMutableString *bigFile=[NSMutableString string]; for(int i=0;i<150;i++)[bigFile appendFormat:@"int f%d(void){return %d;}\n",i,i];
 NSMutableArray *conv=[NSMutableArray arrayWithObject:U(@"TASK: build a tweak that hooks SpringBoard and make it install")];
 for(int i=0;i<24;i++){
   [conv addObject:Call(@"writeFile",[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"src/f%d.c",i],@"filepath",bigFile,@"content",nil],nil)]; [conv addObject:T(@"writeFile",@"Success: wrote")];
   [conv addObject:Call(@"runShellCommand",[NSDictionary dictionaryWithObject:@"make" forKey:@"command"],nil)]; [conv addObject:T(@"runShellCommand",bigOut)];
 }
 [conv addObject:A(@"Build finished.")];
 NSUInteger fullTokens=[AGContextBuilder estimateTokensForText:J(Build(conv,NO,0))];
 NSDictionary *p1=Build(conv,NO,20000); NSUInteger t1=[AGContextBuilder estimateTokensForText:J(p1)];
 printf("   unbounded request ~%lu tokens -> with 20k budget ~%lu tokens\n",(unsigned long)fullTokens,(unsigned long)t1);
 CHECK("history shrinks to fit budget", t1 < fullTokens/2 && t1 <= 20000);
 CHECK("compacted history is still structurally valid", Valid([p1 objectForKey:@"contents"],&why));
 { NSArray *c=[p1 objectForKey:@"contents"]; NSString *first=J([c objectAtIndex:0]); CHECK("pinned: original TASK message survives", [first rangeOfString:@"TASK: build a tweak"].location!=NSNotFound); }
 { NSArray *c=[p1 objectForKey:@"contents"]; NSString *lastOut=nil, *firstOldOut=nil; for(NSDictionary *cc in c) for(NSDictionary *pt in [cc objectForKey:@"parts"]){ NSDictionary *fr=[pt objectForKey:@"functionResponse"]; NSString *o=[[fr objectForKey:@"response"] objectForKey:@"output"]; if([o length]>400){ lastOut=o; if(!firstOldOut)firstOldOut=o; } }
   printf("   newest large tool output: %lu chars; oldest large tool output: %lu chars\n",(unsigned long)[lastOut length],(unsigned long)[firstOldOut length]);
   CHECK("newest tool output kept in full, older ones shrunk", [lastOut isEqualToString:[bigOut stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]] && [firstOldOut length] < [bigOut length]); }
 // cache stability
 NSString *a=J(Build(conv,NO,20000)), *b=J(Build(conv,NO,20000)); CHECK("rebuild without new messages is byte-identical", [a isEqualToString:b]);
 NSArray *beforeContents=[Build(conv,NO,20000) objectForKey:@"contents"];
 [conv addObject:U(@"also add a settings bundle")]; [conv addObject:A(@"ok")];
 NSArray *afterContents=[Build(conv,NO,20000) objectForKey:@"contents"];
 BOOL prefixStable=YES; for(NSUInteger i=0;i<[beforeContents count];i++){ if(![J([beforeContents objectAtIndex:i]) isEqualToString:J([afterContents objectAtIndex:i])]){prefixStable=NO;break;} }
 CHECK("adding messages keeps the earlier prefix byte-identical (implicit-cache friendly)", prefixStable && [afterContents count]>[beforeContents count]);
 // multi-turn omission
 NSMutableArray *chat=[NSMutableArray array]; for(int i=0;i<60;i++){ [chat addObject:U([NSString stringWithFormat:@"question %d %@",i,bigFile])]; [chat addObject:A([NSString stringWithFormat:@"answer %d %@",i,bigFile])]; }
 NSDictionary *p2=Build(chat,NO,15000); NSString *js2=J(p2);
 CHECK("old turns dropped, valid", Valid([p2 objectForKey:@"contents"],&why) && [AGContextBuilder estimateTokensForText:js2]<=15000);
 CHECK("pinned first question + latest question kept", [js2 rangeOfString:@"question 0 "].location!=NSNotFound && [js2 rangeOfString:@"question 59 "].location!=NSNotFound && [js2 rangeOfString:@"question 30 "].location==NSNotFound);
 CHECK("omission note present", [js2 rangeOfString:@"left out of this context"].location!=NSNotFound);
 printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
