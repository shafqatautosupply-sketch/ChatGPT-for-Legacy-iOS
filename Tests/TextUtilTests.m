#import <Foundation/Foundation.h>
#import "AGTextUtil.h"
static int fails=0;
#define CHECK(name, ...) do{ BOOL ok=(__VA_ARGS__); printf("%s %s\n", ok?"PASS":"FAIL", name); if(!ok)fails++; }while(0)
static NSString *S(NSString *x){ return [AGTextUtil sanitizedText:x]; }
int main(){ @autoreleasepool {
  CHECK("plain text untouched", [S(@"hello\n\tworld é ü 日本") isEqualToString:@"hello\n\tworld é ü 日本"]);
  CHECK("ANSI colour codes removed", [S(@"\x1b[31merror\x1b[0m: bad\x1b[2K") isEqualToString:@"error: bad"]);
  CHECK("NUL and control chars removed", [S([NSString stringWithFormat:@"a%Cb%Cc%C", (unichar)0, (unichar)7, (unichar)0x7F]) isEqualToString:@"abc"]);
  CHECK("C1 control chars (what Latin-1 decoding of binary yields) removed", [S([NSString stringWithFormat:@"x%Cy%Cz", (unichar)0x85, (unichar)0x9F]) isEqualToString:@"xyz"]);
  CHECK("CRLF -> LF, lone CR -> LF (progress bars)", [S(@"a\r\nb\rc") isEqualToString:@"a\nb\nc"]);
  CHECK("BOM and object-replacement char removed", [S([NSString stringWithFormat:@"%Cx%Cy", (unichar)0xFEFF, (unichar)0xFFFC]) isEqualToString:@"xy"]);
  CHECK("unterminated ESC at end does not crash", [S(@"ok\x1b") isEqualToString:@"ok"] && [S(@"ok\x1b[31") isEqualToString:@"ok"]);
  CHECK("empty / nil safe", [S(@"") isEqualToString:@""] && [S(nil) isEqualToString:@""]);
  CHECK("isPlainASCII true for code", [AGTextUtil isPlainASCII:@"int main(void){\n\treturn 0;\n}"]);
  CHECK("isPlainASCII false for arrow, ellipsis, accents", ![AGTextUtil isPlainASCII:@"a \u2192 b"] && ![AGTextUtil isPlainASCII:@"wait\u2026"] && ![AGTextUtil isPlainASCII:@"caf\u00e9"]);
  // 1 MB of binary-looking junk must clean up fast
  NSMutableString *junk=[NSMutableString string]; for(int i=0;i<200000;i++) [junk appendFormat:@"%C", (unichar)(i%0xA0)];
  NSDate *t=[NSDate date]; NSString *r=S(junk); double el=-[t timeIntervalSinceNow];
  BOOL clean=YES; for(NSUInteger i=0;i<[r length];i++){ unichar c=[r characterAtIndex:i]; if((c<0x20&&c!='\n'&&c!='\t')||(c>=0x7F&&c<=0x9F)) clean=NO; }
  CHECK("200k chars of binary-like junk sanitised, fast", clean && el<1.0);
  printf("\n%s (%d failures)\n", fails?"SOME FAILED":"ALL PASSED", fails); return fails; }}
