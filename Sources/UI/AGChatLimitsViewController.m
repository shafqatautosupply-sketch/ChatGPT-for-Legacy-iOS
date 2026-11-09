#import "AGChatLimitsViewController.h"
#import "AGConversationStore.h"

@interface AGChatLimitsViewController ()
@property (nonatomic, retain) UITextField *saveLimitTextField;
@property (nonatomic, retain) UITextField *loadLimitTextField;
@property (nonatomic, retain) UITextField *budgetTextField;
@end

@implementation AGChatLimitsViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Chat History Limits";
	}
	return self;
}

- (void)dealloc {
	[_saveLimitTextField release];
	[_loadLimitTextField release];
	[_budgetTextField release];
	[super dealloc];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.allowsSelection = NO;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Messages Saved to Disk";
	if (section == 1) return @"Messages Loaded in Interface";
	return @"Context Budget Sent to Model (tokens)";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return @"Maximum number of recent messages persisted to JSON per conversation. Set to 0 for unlimited (recommended to prevent history loss).";
	}
	if (section == 1) return @"Maximum number of recent messages loaded into the chat view. Set to 0 for unlimited.";
	return @"When the estimated size of the history passes this, old tool output and file contents are shrunk, then old turns are left out (the first message is always kept). Your saved chat is not changed. Default 24000; 0 = never shrink. Needs Token Saver on.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *CellIdentifier = [NSString stringWithFormat:@"LimitCell%ld", (long)indexPath.section];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
		
		UITextField *textField = [[[UITextField alloc] initWithFrame:CGRectMake(15, 8, [UIScreen mainScreen].bounds.size.width - 60, 30)] autorelease];
		textField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		textField.keyboardType = UIKeyboardTypeNumberPad;
		textField.delegate = self;
		textField.borderStyle = UITextBorderStyleNone;
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;

		if (indexPath.section == 0) {
			self.saveLimitTextField = textField;
			NSInteger savedLimit = [AGConversationStore savedMessageLimit];
			textField.text = (savedLimit < 0) ? @"" : [NSString stringWithFormat:@"%ld", (long)savedLimit];
			textField.placeholder = @"Default (0 - Unlimited)";
		} else if (indexPath.section == 2) {
			self.budgetTextField = textField;
			textField.text = [NSString stringWithFormat:@"%ld", (long)[AGConversationStore configuredContextTokenBudget]];
			textField.placeholder = @"Default (24000)";
		} else {
			self.loadLimitTextField = textField;
			NSInteger loadedLimit = [AGConversationStore loadedMessageLimit];
			textField.text = (loadedLimit < 0) ? @"" : [NSString stringWithFormat:@"%ld", (long)loadedLimit];
			textField.placeholder = @"Default (30)";
		}

		[cell.contentView addSubview:textField];
	}
	return cell;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[self.view endEditing:YES];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	// Allow only numbers
	NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
	if ([string rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
		return NO;
	}
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	NSString *text = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (textField == self.saveLimitTextField) {
		NSInteger value = [text length] > 0 ? [text integerValue] : 0;
		[AGConversationStore setSavedMessageLimit:value];
	} else if (textField == self.loadLimitTextField) {
		NSInteger value = [text length] > 0 ? [text integerValue] : 30;
		[AGConversationStore setLoadedMessageLimit:value];
	} else if (textField == self.budgetTextField) {
		NSInteger value = [text length] > 0 ? [text integerValue] : 24000;
		[AGConversationStore setConfiguredContextTokenBudget:value];
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

@end
