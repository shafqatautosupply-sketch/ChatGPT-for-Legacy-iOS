#import "LCRAWJSONViewController.h"
#import "LCConversationStore.h"
#import "CGConversation.h"
#import "CGMessage.h"
#import <UIKit/UIKit.h>

@implementation LCRAWJSONViewController {
	UITextView *_textView;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Raw JSON Chat Debug";
	self.view.backgroundColor = [UIColor colorWithRed:0.89f green:0.91f blue:0.94f alpha:1.0f];

	_textView = [[[UITextView alloc] initWithFrame:self.view.bounds] autorelease];
	_textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_textView.editable = NO;
	_textView.font = [UIFont fontWithName:@"Courier" size:13.0f] ?: [UIFont systemFontOfSize:13.0f];
	_textView.backgroundColor = [UIColor whiteColor];
	_textView.textColor = [UIColor darkTextColor];

	NSString *currentID = [LCConversationStore currentConversationIdentifier];
	NSDictionary *jsonDict = nil;

	if ([currentID length] > 0) {
		NSString *filePath = [LCConversationStore pathForConversationIdentifier:currentID];
		NSData *data = [NSData dataWithContentsOfFile:filePath];
		if (data != nil) {
			jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		}
	}

	if (jsonDict == nil) {
		jsonDict = [NSDictionary dictionaryWithObjectsAndKeys:
			(currentID ?: @""), @"conversationID",
			@"No active conversation found or conversation is empty.", @"message",
			nil];
	}

	NSError *jsonError = nil;
	NSData *prettyData = [NSJSONSerialization dataWithJSONObject:jsonDict options:NSJSONWritingPrettyPrinted error:&jsonError];
	if (prettyData != nil) {
		NSString *jsonString = [[[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding] autorelease];
		_textView.text = jsonString;
	} else {
		_textView.text = @"Error encoding current chat session to JSON.";
	}

	[self.view addSubview:_textView];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[_textView becomeFirstResponder];
}

@end
