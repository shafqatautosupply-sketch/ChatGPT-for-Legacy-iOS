#import <Foundation/Foundation.h>
#import "AGProviderConfig.h"
static int fails=0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
int main(){ @autoreleasepool {
  NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
  // simulate legacy data: two Gemini profiles with identical name|url ids (the old collision), one active
  NSDictionary *a=[NSDictionary dictionaryWithObjectsAndKeys:@"Google Gemini|https://x",@"identifier",@"Google Gemini",@"providerName",@"https://x",@"baseURL",@"gemini-2.5-flash",@"c-aiModel",@"KEY_A",@"apiKey",nil];
  NSDictionary *b=[NSDictionary dictionaryWithObjectsAndKeys:@"Google Gemini|https://x",@"identifier",@"Google Gemini",@"providerName",@"https://x",@"baseURL",@"gemini-2.5-pro",@"c-aiModel",@"KEY_B",@"apiKey",nil];
  [d setObject:[NSArray arrayWithObjects:a,b,nil] forKey:@"providerProfiles"]; [d setObject:@"Google Gemini|https://x" forKey:@"activeProviderProfileID"];
  [AGProviderConfig registerProviderDefaults];
  NSArray *ps=[AGProviderConfig providerProfiles];
  CHECK("legacy duplicate identifiers repaired on launch", [ps count]==2 && ![[[ps objectAtIndex:0] objectForKey:@"identifier"] isEqual:[[ps objectAtIndex:1] objectForKey:@"identifier"]]);
  CHECK("legacy active profile still resolves to the first", [[AGProviderConfig currentAPIKey] isEqual:@"KEY_A"]);
  NSString *idB=[[ps objectAtIndex:1] objectForKey:@"identifier"]; [AGProviderConfig activateProviderProfileWithIdentifier:idB];
  CHECK("second same-name profile is now selectable", [[AGProviderConfig currentAPIKey] isEqual:@"KEY_B"] && [[AGProviderConfig configuredChatModel] isEqual:@"gemini-2.5-pro"]);
  [AGProviderConfig saveActiveProviderProfileWithValues:[NSDictionary dictionaryWithObjectsAndKeys:@"Renamed",@"providerName",@"https://other",@"baseURL",@"gemini-2.5-pro",@"c-aiModel",@"KEY_B",@"apiKey",nil]];
  CHECK("renaming/changing URL of the active profile keeps it active", [[AGProviderConfig providerDisplayName] isEqual:@"Renamed"] && [[AGProviderConfig currentAPIKey] isEqual:@"KEY_B"] && [[AGProviderConfig providerProfiles] count]==2);
  [AGProviderConfig createProviderProfileWithValues:[NSDictionary dictionaryWithObjectsAndKeys:@"Renamed",@"providerName",@"https://other",@"baseURL",@"m3",@"c-aiModel",@"KEY_C",@"apiKey",nil]];
  CHECK("identical name+URL profile can be created and is active", [[AGProviderConfig providerProfiles] count]==3 && [[AGProviderConfig currentAPIKey] isEqual:@"KEY_C"]);
  [AGProviderConfig deleteProviderProfileWithIdentifier:[AGProviderConfig activeProviderProfileIdentifier]];
  CHECK("deleting the active profile falls back to another", [[AGProviderConfig providerProfiles] count]==2 && [[AGProviderConfig currentAPIKey] length]>0);
  CHECK("no thinkingConfig sent by default (2.5 models reject thinkingLevel)", [AGProviderConfig generationConfigForCurrentModel]==nil);
  [d setObject:@"low" forKey:@"ag_thinking_level"]; CHECK("thinking level is opt-in", [[[[AGProviderConfig generationConfigForCurrentModel] objectForKey:@"thinkingConfig"] objectForKey:@"thinkingLevel"] isEqual:@"low"]);
  CHECK("URL builds", [[[AGProviderConfig configuredChatCompletionURL] absoluteString] rangeOfString:@"/v1beta/models/gemini-2.5-"].location!=NSNotFound && [[[AGProviderConfig configuredChatCompletionURL] absoluteString] hasSuffix:@":generateContent"]);
  printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
