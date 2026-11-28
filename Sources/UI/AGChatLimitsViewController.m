#import "AGChatLimitsViewController.h"
#import "AGConversationStore.h"
#import "AGInfoCell.h"

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
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return @"History & context";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *CellIdentifier = [NSString stringWithFormat:@"LimitCell%ld", (long)indexPath.row];
	AGInfoCell *cell = (AGInfoCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[AGInfoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;

		// The title is on the left with its (i); the number sits on the right.
		UITextField *textField = [[[UITextField alloc] initWithFrame:CGRectMake(0, 0, 90, 30)] autorelease];
		textField.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		textField.textAlignment = UITextAlignmentRight;
		textField.keyboardType = UIKeyboardTypeNumberPad;
		textField.delegate = self;
		textField.borderStyle = UITextBorderStyleNone;
		textField.clearButtonMode = UITextFieldViewModeNever;
		CGFloat contentWidth = tableView.bounds.size.width - 20.0f;
		if (contentWidth < 200.0f) contentWidth = 300.0f;
		textField.frame = CGRectMake(contentWidth - 90.0f - 12.0f, 7.0f, 90.0f, 30.0f);

		if (indexPath.row == 0) {
			self.saveLimitTextField = textField;
			NSInteger savedLimit = [AGConversationStore savedMessageLimit];
			textField.text = (savedLimit < 0) ? @"" : [NSString stringWithFormat:@"%ld", (long)savedLimit];
			textField.placeholder = @"0 = all";
		} else if (indexPath.row == 1) {
			self.loadLimitTextField = textField;
			NSInteger loadedLimit = [AGConversationStore loadedMessageLimit];
			textField.text = (loadedLimit < 0) ? @"" : [NSString stringWithFormat:@"%ld", (long)loadedLimit];
			textField.placeholder = @"30";
		} else {
			self.budgetTextField = textField;
			textField.text = [NSString stringWithFormat:@"%ld", (long)[AGConversationStore configuredContextTokenBudget]];
			textField.placeholder = @"24000";
		}
		[cell.contentView addSubview:textField];
	}
	if (indexPath.row == 0) {
		cell.textLabel.text = @"Saved to disk";
		cell.infoText = @"Maximum number of recent messages kept per conversation. 0 means unlimited, which is recommended so history is not lost.";
	} else if (indexPath.row == 1) {
		cell.textLabel.text = @"Shown in chat";
		cell.infoText = @"Maximum number of recent messages loaded into the chat view. 0 means unlimited. Default 30.";
	} else {
		cell.textLabel.text = @"Context budget (tokens)";
		cell.infoText = @"When the estimated size of the history passes this, old tool output and file contents are shrunk, then old turns are left out (the first message is always kept). Your saved chat is not changed.\n\nDefault 24000. 0 means never shrink. Needs Token Saver on.";
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
