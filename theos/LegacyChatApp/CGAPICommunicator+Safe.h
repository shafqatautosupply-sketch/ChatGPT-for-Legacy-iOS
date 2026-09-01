#import "CGAPICommunicator.h"
#import "CGMessage.h"
#import "CGAPIHelper.h"

// Implement safe toolCalls parsing
@implementation CGAPICommunicator (SafeToolCalls)
// Helper to safely extract array
+ (NSArray *)safeToolCallsFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    id obj = [dict objectForKey:@"tool_calls"];
    return [obj isKindOfClass:[NSArray class]] ? obj : nil;
}
@end
