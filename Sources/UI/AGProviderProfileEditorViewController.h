#import <UIKit/UIKit.h>

@interface AGProviderProfileEditorViewController : UITableViewController <UITextFieldDelegate>

/// New profile of AGProviderTypeGemini or AGProviderTypeOpenAI (defaults and hints follow the type).
- (id)initForNewProfileOfType:(NSString *)providerType;
- (id)initForNewProfile; // Gemini
- (id)initWithProfile:(NSDictionary *)profile;

@end
