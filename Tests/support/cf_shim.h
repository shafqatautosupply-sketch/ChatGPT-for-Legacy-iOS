#import <Foundation/Foundation.h>
typedef void *CFUUIDRef;
static CFUUIDRef CFUUIDCreate(void *a){ return (void*)1; }
static NSString *CFUUIDCreateString(void *a, CFUUIDRef u){ FILE *f=fopen("/proc/sys/kernel/random/uuid","r"); char b[64]={0}; if(f){fgets(b,64,f);fclose(f);} NSString *s=[NSString stringWithUTF8String:b]; s=[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; return [s retain]; }
static void CFRelease(void *x){}
