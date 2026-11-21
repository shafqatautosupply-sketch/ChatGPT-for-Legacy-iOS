#import <Foundation/Foundation.h>
#import "AGContextBuilder.h"
#import "AGAgentTools.h"
#import "AGMessage.h"
static int fails=0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
static AGMessage *U(NSString *t){ return [AGMessage messageWithRole:@"user" content:t]; }
static AGMessage *A(NSString *t){ return [AGMessage messageWithRole:@"assistant" content:t]; }
static AGMessage *CallN(NSString *text, NSArray *specs /* [name, argsDict, id-or-null, sig-or-null] */){
  AGMessage *m=[AGMessage messageWithRole:@"assistant" content:text]; NSMutableArray *tcs=[NSMutableArray array];
  for(NSArray *sp in specs){ NSData *j=[NSJSONSerialization dataWithJSONObject:[sp objectAtIndex:1] options:0 error:nil]; NSString *s=[[[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] autorelease];
    NSMutableDictionary *tc=[NSMutableDictionary dictionaryWithObjectsAndKeys:@"function",@"type",[NSDictionary dictionaryWithObjectsAndKeys:[sp objectAtIndex:0],@"name",s,@"arguments",nil],@"function",nil];
    if(![[sp objectAtIndex:2] isKindOfClass:[NSNull class]])[tc setObject:[sp objectAtIndex:2] forKey:@"id"]; if(![[sp objectAtIndex:3] isKindOfClass:[NSNull class]])[tc setObject:[sp objectAtIndex:3] forKey:@"thoughtSignature"]; [tcs addObject:tc]; }
  m.toolCalls=tcs; return m; }
static AGMessage *Call1(NSString *name, NSDictionary *args, id cid){ return CallN(@"", [NSArray arrayWithObject:[NSArray arrayWithObjects:name,args,(cid?:[NSNull null]),[NSNull null],nil]]); }
static AGMessage *T(NSString *out){ AGMessage *m=[AGMessage messageWithRole:@"tool" content:out]; m.toolName=@"x"; return m; }

// Structure rules of the OpenAI Chat Completions API.
static BOOL Valid(NSArray *msgs, NSString **why){
  if([msgs count]==0){*why=@"empty";return NO;}
  for(NSUInteger i=0;i<[msgs count];i++){ NSDictionary *m=[msgs objectAtIndex:i]; NSString *role=[m objectForKey:@"role"];
    if(![[m objectForKey:@"content"] isKindOfClass:[NSString class]]){*why=@"content not a string";return NO;}
    if([role isEqual:@"system"] && i!=0){*why=@"system not first";return NO;}
    NSArray *calls=[m objectForKey:@"tool_calls"];
    if(calls){ if(![role isEqual:@"assistant"]){*why=@"tool_calls on non-assistant";return NO;}
      for(NSUInteger k=0;k<[calls count];k++){ NSDictionary *c=[calls objectAtIndex:k]; NSString *args=[[c objectForKey:@"function"] objectForKey:@"arguments"];
        if(![[c objectForKey:@"id"] length]||![[[c objectForKey:@"function"] objectForKey:@"name"] length]||![args isKindOfClass:[NSString class]]||![NSJSONSerialization JSONObjectWithData:[args dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]){*why=@"bad call";return NO;}
        if(i+1+k>=[msgs count]){*why=@"call without tool message";return NO;}
        NSDictionary *t=[msgs objectAtIndex:i+1+k]; if(![[t objectForKey:@"role"] isEqual:@"tool"]||![[t objectForKey:@"tool_call_id"] isEqual:[c objectForKey:@"id"]]){*why=@"tool message does not answer its call";return NO;} }
      if(i+1+[calls count]<[msgs count] && [[[msgs objectAtIndex:i+1+[calls count]] objectForKey:@"role"] isEqual:@"tool"]){*why=@"extra tool message";return NO;} }
    if([role isEqual:@"tool"]){ BOOL answered=NO; for(NSInteger k=(NSInteger)i-1;k>=0;k--){ NSDictionary *p=[msgs objectAtIndex:k]; if([[p objectForKey:@"role"] isEqual:@"tool"])continue; for(NSDictionary *c in [p objectForKey:@"tool_calls"]) if([[c objectForKey:@"id"] isEqual:[m objectForKey:@"tool_call_id"]]) answered=YES; break; }
      if(!answered){*why=@"orphan tool message";return NO;} } }
  return YES; }
static NSString *J(id o){ NSData *d=[NSJSONSerialization dataWithJSONObject:o options:0 error:nil]; return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease]; }
static NSDictionary *B(NSArray *m, BOOL pure, NSUInteger budget){ return [AGContextBuilder openAIPayloadForMessages:m pureChat:pure systemPrompt:@"sys" tools:[AGAgentTools openAIToolDeclarations] tokenBudget:budget model:@"gpt-x"]; }

int main(){ @autoreleasepool {
 NSString *why=@"";
 { NSArray *m=[NSArray arrayWithObjects:U(@"hi"),A(@"hello"),nil]; NSDictionary *p=B(m,NO,0);
   CHECK("basic: model, system first, user/assistant roles, tools present", [[p objectForKey:@"model"] isEqual:@"gpt-x"] && Valid([p objectForKey:@"messages"],&why) && [[[[p objectForKey:@"messages"] objectAtIndex:0] objectForKey:@"role"] isEqual:@"system"] && [[p objectForKey:@"tools"] count]==4); }
 { NSArray *m=[NSArray arrayWithObjects:U(@"go"),Call1(@"runShellCommand",[NSDictionary dictionaryWithObject:@"ls" forKey:@"command"],@"call_abc"),T(@"a.m"),A(@"done"),nil]; NSDictionary *p=B(m,NO,0);
   NSArray *o=[p objectForKey:@"messages"]; CHECK("call + result: assistant has tool_calls, tool message carries the same id", Valid(o,&why) && [[[o objectAtIndex:3] objectForKey:@"tool_call_id"] isEqual:@"call_abc"]);
   if(!Valid(o,&why))printf("   why: %s\n",[why UTF8String]); }
 { // Gemini-origin chat: legacy synthetic text, thoughtSignature, tool message without id -> positional ids
   AGMessage *g=CallN(@"Tool Call: runShellCommand\nArguments: {}",[NSArray arrayWithObject:[NSArray arrayWithObjects:@"runShellCommand",[NSDictionary dictionaryWithObject:@"ls" forKey:@"command"],[NSNull null],@"SIG",nil]]);
   NSArray *m=[NSArray arrayWithObjects:U(@"go"),g,T(@"out"),nil]; NSDictionary *p=B(m,NO,0); NSString *js=J(p);
   CHECK("chat started on Gemini converts: valid, ids generated, no signature, no synthetic text", Valid([p objectForKey:@"messages"],&why) && [js rangeOfString:@"thoughtSignature"].location==NSNotFound && [js rangeOfString:@"Tool Call:"].location==NSNotFound); }
 { AGMessage *err=A(@"HTTP 429"); err.localOnly=YES; NSArray *m=[NSArray arrayWithObjects:T(@"orphan"),U(@"hi"),err,A(@"yo"),nil]; NSDictionary *p=B(m,NO,0);
   CHECK("orphan tool message dropped, local notice not sent", Valid([p objectForKey:@"messages"],&why) && [J(p) rangeOfString:@"orphan"].location==NSNotFound && [J(p) rangeOfString:@"429"].location==NSNotFound); }
 { NSArray *m=[NSArray arrayWithObjects:U(@"go"),CallN(@"",[NSArray arrayWithObjects:[NSArray arrayWithObjects:@"readFile",[NSDictionary dictionary],@"c1",[NSNull null],nil],[NSArray arrayWithObjects:@"readFile",[NSDictionary dictionary],@"c2",[NSNull null],nil],nil]),T(@"only one"),U(@"stop"),nil];
   NSDictionary *p=B(m,NO,0); CHECK("2 calls with 1 result (Stop pressed): filler answers the missing id", Valid([p objectForKey:@"messages"],&why)); if(!Valid([p objectForKey:@"messages"],&why))printf("   why: %s\n",[why UTF8String]); }
 { NSArray *m=[NSArray arrayWithObjects:U(@"go"),Call1(@"readFile",[NSDictionary dictionary],@"c1"),T(@"x"),A(@"done"),U(@"thanks"),nil]; NSDictionary *p=B(m,YES,0);
   CHECK("pure chat after agent session: no tool_calls/tool messages/tools", Valid([p objectForKey:@"messages"],&why) && [J(p) rangeOfString:@"tool_call"].location==NSNotFound && [p objectForKey:@"tools"]==nil && [J(p) rangeOfString:@"\"tool\""].location==NSNotFound); }
 { AGMessage *c=Call1(@"runShellCommand",[NSDictionary dictionaryWithObject:@"x" forKey:@"command"],@"c1"); NSMutableDictionary *tc=[NSMutableDictionary dictionaryWithDictionary:[c.toolCalls objectAtIndex:0]]; [tc setObject:[NSDictionary dictionaryWithObjectsAndKeys:@"runShellCommand",@"name",@"{not json",@"arguments",nil] forKey:@"function"]; c.toolCalls=[NSArray arrayWithObject:tc];
   NSDictionary *p=B([NSArray arrayWithObjects:U(@"go"),c,T(@"e"),nil],NO,0); CHECK("invalid argument JSON from the model is replaced by {} (servers validate it)", Valid([p objectForKey:@"messages"],&why)); }
 // token saver parity with the Gemini path
 NSMutableString *bigOut=[NSMutableString string]; for(int i=0;i<200;i++)[bigOut appendString:@"clang: compiling Tweak.xm warning: unused variable foo\n"];
 NSMutableString *bigFile=[NSMutableString string]; for(int i=0;i<150;i++)[bigFile appendFormat:@"int f%d(void){return %d;}\n",i,i];
 NSMutableArray *conv=[NSMutableArray arrayWithObject:U(@"TASK: build a tweak")];
 for(int i=0;i<24;i++){ [conv addObject:Call1(@"writeFile",[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"f%d.c",i],@"filepath",bigFile,@"content",nil],[NSString stringWithFormat:@"w%d",i])]; [conv addObject:T(@"Success")];
   [conv addObject:Call1(@"runShellCommand",[NSDictionary dictionaryWithObject:@"make" forKey:@"command"],[NSString stringWithFormat:@"m%d",i])]; [conv addObject:T(bigOut)]; }
 [conv addObject:A(@"Build finished.")];
 NSUInteger full=[AGContextBuilder estimateTokensForText:J(B(conv,NO,0))]; NSDictionary *p1=B(conv,NO,20000); NSUInteger t1=[AGContextBuilder estimateTokensForText:J(p1)];
 printf("   unbounded ~%lu tokens -> budget 20k ~%lu tokens\n",(unsigned long)full,(unsigned long)t1);
 CHECK("token saver works for OpenAI format and stays valid", t1<full/2 && t1<=20000 && Valid([p1 objectForKey:@"messages"],&why));
 { NSArray *c=[p1 objectForKey:@"messages"]; CHECK("pinned TASK kept", [J([c objectAtIndex:1]) rangeOfString:@"TASK: build a tweak"].location!=NSNotFound); }
 NSArray *before=[B(conv,NO,20000) objectForKey:@"messages"]; [conv addObject:U(@"more")]; [conv addObject:A(@"ok")]; NSArray *after=[B(conv,NO,20000) objectForKey:@"messages"];
 BOOL stable=YES; for(NSUInteger i=0;i<[before count];i++) if(![J([before objectAtIndex:i]) isEqualToString:J([after objectAtIndex:i])]){stable=NO;break;}
 CHECK("earlier prefix stays byte-identical when messages are added (provider-side caching)", stable && [after count]>[before count]);
 printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
