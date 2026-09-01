#import "LCChatLimitsViewController.h"
#import "LCConversationStore.h"

@interface LCChatLimitsViewController ()
@property (nonatomic, retain) UITextField *saveLimitTextField;
@property (nonatomic, retain) UITextField *loadLimitTextField;
@end

@implementation LCChatLimitsViewController

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
	[super dealloc];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.allowsSelection = NO;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Messages Saved to Disk";
	return @"Messages Loaded in Interface";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return @"Maximum number of recent messages persisted to JSON per conversation. Set to 0 for unlimited (recommended to prevent history loss).";
	}
	return @"Maximum number of recent messages loaded into the chat view. Set to 0 for unlimited.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"LimitCell";
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
			NSInteger savedLimit = [LCConversationStore savedMessageLimit];
			textField.text = (savedLimit < 0) ? @"" : [NSString stringWithFormat:@"%ld", (long)savedLimit];
			textField.placeholder = @"Default (0 - Unlimited)";
		} else {
			self.loadLimitTextField = textField;
			NSInteger loadedLimit = [LCConversationStore loadedMessageLimit];
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
		[LCConversationStore setSavedMessageLimit:value];
	} else if (textField == self.loadLimitTextField) {
		NSInteger value = [text length] > 0 ? [text integerValue] : 30;
		[LCConversationStore setLoadedMessageLimit:value];
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

@end
