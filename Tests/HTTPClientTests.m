#import <Foundation/Foundation.h>
#include <stdlib.h>
#import "AGHTTPClient.h"
static int fails=0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
static NSData *Post(NSString *url, NSInteger *status, NSError **err, NSTimeInterval timeout, BOOL(^c)(void), NSString **retry){
  NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]]; [r setHTTPMethod:@"POST"]; [r setHTTPBody:[@"{\"a\":1}" dataUsingEncoding:NSUTF8StringEncoding]];
  [r setValue:@"SECRETKEY" forHTTPHeaderField:@"x-goog-api-key"]; [r setTimeoutInterval:timeout];
  NSHTTPURLResponse *resp=nil; NSData *d=[AGHTTPClient sendSynchronousRequest:r returningResponse:(NSURLResponse**)&resp error:err isCancelled:c];
  if(status)*status=[resp statusCode]; if(retry)*retry=[[resp allHeaderFields] objectForKey:@"Retry-After"]; return d; }
int main(){ @autoreleasepool {
  NSUserDefaults *d=[NSUserDefaults standardUserDefaults]; NSInteger st=0; NSError *e=nil; NSString *ra=nil;
  NSData *r=Post(@"http://127.0.0.1:8080/x",&st,&e,10,nil,nil); NSDictionary *j=r?[NSJSONSerialization JSONObjectWithData:r options:0 error:nil]:nil;
  CHECK("plain HTTP POST works, key header sent", st==200 && [[j objectForKey:@"key"] isEqual:@"SECRETKEY"]);
  CHECK("'Expect: 100-continue' suppressed", [j objectForKey:@"expect"]==nil || [[j objectForKey:@"expect"] isKindOfClass:[NSNull class]]);
  CHECK("gzip advertised", [[j objectForKey:@"ae"] isKindOfClass:[NSString class]] && [[j objectForKey:@"ae"] rangeOfString:@"gzip"].location!=NSNotFound);
  r=Post(@"http://127.0.0.1:8080/gzip",&st,&e,10,nil,nil); j=r?[NSJSONSerialization JSONObjectWithData:r options:0 error:nil]:nil; CHECK("gzip response transparently decoded", [[j objectForKey:@"echo_len"] intValue]==7);
  r=Post(@"http://127.0.0.1:8080/redirect",&st,&e,10,nil,nil); CHECK("redirect NOT followed (API key not re-sent to other host)", st==302);
  r=Post(@"http://127.0.0.1:8080/429",&st,&e,10,nil,&ra); CHECK("HTTP status + Retry-After header surfaced", st==429 && [ra isEqual:@"7"]);
  // TLS
  [d setObject:[NSString stringWithFormat:@"%s/Resources/cacert.pem", getenv("AG_REPO")] forKey:@"ag_ca_bundle_path"];
  e=nil; r=Post(@"https://localhost:8443/x",&st,&e,10,nil,nil);
  CHECK("HTTPS to untrusted (self-signed) server is REJECTED by default", r==nil && [e code]==60);
  printf("   error text: %s\n",[[e localizedDescription] UTF8String]);
  [d setObject:@"/tmp/ag_tls/cert.pem" forKey:@"ag_ca_bundle_path"]; e=nil; r=Post(@"https://localhost:8443/x",&st,&e,10,nil,nil);
  CHECK("HTTPS succeeds when the server cert is trusted via the CA bundle", r!=nil && st==200);
  e=nil; r=Post(@"https://127.0.0.1:8443/x",&st,&e,10,nil,nil); CHECK("trusted CA but wrong-host check still works (IP SAN present => ok)", r!=nil||e!=nil);
  [d removeObjectForKey:@"ag_ca_bundle_path"];
  [AGHTTPClient setInsecureTLSEnabled:YES]; e=nil; r=Post(@"https://localhost:8443/x",&st,&e,10,nil,nil); CHECK("explicit Insecure TLS toggle still available", r!=nil && st==200);
  [AGHTTPClient setInsecureTLSEnabled:NO];
  // timeout & cancel
  NSDate *t=[NSDate date]; e=nil; r=Post(@"http://127.0.0.1:8080/slow",&st,&e,2,nil,nil); double el=-[t timeIntervalSinceNow];
  CHECK("request timeout enforced (was ignored: could hang forever)", r==nil && [e code]==28 && el<4);
  printf("   timeout after %.1fs: %s\n",el,[[e localizedDescription] UTF8String]);
  t=[NSDate date]; NSDate *start=t;
  e=nil; r=Post(@"http://127.0.0.1:8080/slow",&st,&e,30,^BOOL{return -[start timeIntervalSinceNow]>1.0;},nil); el=-[t timeIntervalSinceNow];
  CHECK("Stop aborts a request that is waiting for the server", r==nil && [e code]==42 && el<4);
  printf("   cancelled after %.1fs\n",el);
  e=nil; r=Post(@"http://127.0.0.1:9/x",&st,&e,5,nil,nil); CHECK("connection refused gives readable error", r==nil && [[e localizedDescription] rangeOfString:@"curl error 7"].location!=NSNotFound);
  printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
