#import "LCProviderProfileEditorViewController.h"
#import "CGAPIHelper.h"

@interface LCProviderProfileEditorViewController ()

@property (nonatomic, retain) NSArray *fieldOrder;
@property (nonatomic, retain) NSMutableDictionary *draftValues;
@property (nonatomic, retain) NSMutableDictionary *textFields;
@property (nonatomic, retain) NSString *editingIdentifier;
@property (nonatomic, assign) BOOL creatingNewProfile;

@end

@implementation LCProviderProfileEditorViewController

@synthesize fieldOrder = _fieldOrder;
@synthesize draftValues = _draftValues;
@synthesize textFields = _textFields;
@synthesize editingIdentifier = _editingIdentifier;
@synthesize creatingNewProfile = _creatingNewProfile;

+ (NSMutableDictionary *)defaultDraftValues {
	NSMutableDictionary *values = [NSMutableDictionary dictionary];
	[values setObject:@"Google Gemini" forKey:@"providerName"];
	[values setObject:@"https://generativelanguage.googleapis.com" forKey:@"baseURL"];
	[values setObject:@"gemini-2.5-flash" forKey:@"c-aiModel"];
	[values setObject:@"" forKey:@"apiKey"];
	return values;
}

- (id)initForNewProfile {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"New Configuration";
		self.creatingNewProfile = YES;
		self.fieldOrder = [NSArray arrayWithObjects:@"providerName", @"baseURL", @"c-aiModel", @"apiKey", nil];
		self.draftValues = [[self class] defaultDraftValues];
		self.textFields = [NSMutableDictionary dictionary];
	}
	return self;
}

- (id)initWithProfile:(NSDictionary *)profile {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Edit Configuration";
		self.creatingNewProfile = NO;
		self.editingIdentifier = [profile objectForKey:@"identifier"];
		self.fieldOrder = [NSArray arrayWithObjects:@"providerName", @"baseURL", @"c-aiModel", @"apiKey", nil];
		self.draftValues = [[self class] defaultDraftValues];
		if ([profile isKindOfClass:[NSDictionary class]]) {
			[self.draftValues addEntriesFromDictionary:profile];
		}
		self.textFields = [NSMutableDictionary dictionary];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		self.tableView.rowHeight = 68.0f;
	}
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)] autorelease];
	[self.tableView reloadData];
}

- (NSString *)titleForFieldKey:(NSString *)fieldKey {
	if ([fieldKey isEqualToString:@"providerName"]) return @"Provider";
	if ([fieldKey isEqualToString:@"baseURL"]) return @"Base URL";
	if ([fieldKey isEqualToString:@"c-aiModel"]) return @"Model";
	if ([fieldKey isEqualToString:@"apiKey"]) return @"API Key";
	return fieldKey;
}

- (NSString *)placeholderForFieldKey:(NSString *)fieldKey {
	if ([fieldKey isEqualToString:@"providerName"]) return @"Google Gemini";
	if ([fieldKey isEqualToString:@"baseURL"]) return @"https://generativelanguage.googleapis.com";
	if ([fieldKey isEqualToString:@"c-aiModel"]) return @"gemini-2.5-flash";
	if ([fieldKey isEqualToString:@"apiKey"]) return @"Paste your key (AIza...)";
	return @"";
}

- (void)saveTapped {
	[self.view endEditing:YES];
	if (self.creatingNewProfile) {
		[CGAPIHelper createProviderProfileWithValues:self.draftValues];
	} else {
		[CGAPIHelper updateProviderProfileWithIdentifier:self.editingIdentifier values:self.draftValues];
	}
	[self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self.fieldOrder count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return @"Configured for Google Gemini Native API. The endpoint URL is automatically constructed using Base URL and Model name.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"FieldCell";
	UITableViewCell *cell = [UITableViewCell alloc];
    cell = [cell initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    [cell autorelease];
    
	UILabel *titleLabel = nil;
	UITextField *textField = nil;
    
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	titleLabel = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
	titleLabel.tag = 9001;
	titleLabel.backgroundColor = [UIColor clearColor];
	titleLabel.textColor = [UIColor blackColor];
	titleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
	[cell.contentView addSubview:titleLabel];

	textField = [[[UITextField alloc] initWithFrame:CGRectZero] autorelease];
	textField.tag = 9002;
	textField.textColor = [UIColor blackColor];
	textField.borderStyle = UITextBorderStyleNone;
	textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	textField.font = [UIFont systemFontOfSize:15.0f];
	textField.delegate = self;
	textField.clearButtonMode = UITextFieldViewModeWhileEditing;
	textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	textField.autocorrectionType = UITextAutocorrectionTypeNo;
	textField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[cell.contentView addSubview:textField];

	if (indexPath.row >= [self.fieldOrder count]) return cell;
	NSString *fieldKey = [self.fieldOrder objectAtIndex:indexPath.row];
	if (!fieldKey) return cell;

	CGFloat rowHeight = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 68.0f : 60.0f);
	titleLabel.text = [self titleForFieldKey:fieldKey];
	titleLabel.frame = CGRectMake(20.0f, 8.0f, tableView.bounds.size.width - 40.0f, 18.0f);
	textField.tag = indexPath.row + 100;
	textField.placeholder = [self placeholderForFieldKey:fieldKey];
    
	NSString *fieldValue = [self.draftValues objectForKey:fieldKey];
	textField.text = ([fieldValue isKindOfClass:[NSString class]] ? fieldValue : @"");
	textField.secureTextEntry = [fieldKey isEqualToString:@"apiKey"];
	textField.keyboardType = ([fieldKey isEqualToString:@"baseURL"] ? UIKeyboardTypeURL : UIKeyboardTypeDefault);
	textField.frame = CGRectMake(20.0f, rowHeight - 33.0f, tableView.bounds.size.width - 40.0f, 26.0f);
    
    if (self.textFields == nil) self.textFields = [NSMutableDictionary dictionary];
    if (fieldKey) [self.textFields setObject:textField forKey:fieldKey];
    
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 68.0f : 60.0f);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= [self.fieldOrder count]) return;
	NSString *fieldKey = [self.fieldOrder objectAtIndex:indexPath.row];
	if (fieldKey) [[self.textFields objectForKey:fieldKey] becomeFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	NSInteger nextTag = textField.tag + 1;
	UIView *nextView = [self.view viewWithTag:nextTag];
	if ([nextView isKindOfClass:[UITextField class]]) [(UITextField *)nextView becomeFirstResponder];
	else [textField resignFirstResponder];
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	NSInteger fieldIndex = textField.tag - 100;
	if (fieldIndex < 0 || fieldIndex >= [self.fieldOrder count]) return;
	NSString *fieldKey = [self.fieldOrder objectAtIndex:fieldIndex];
	if (!fieldKey) return;
    
	if (!self.draftValues) self.draftValues = [NSMutableDictionary dictionary];
	NSString *value = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[self.draftValues setObject:(value ?: @"") forKey:fieldKey];
}

- (void)dealloc {
	[_fieldOrder release]; [_draftValues release]; [_textFields release];
	[_editingIdentifier release];
	[super dealloc];
}

@end
