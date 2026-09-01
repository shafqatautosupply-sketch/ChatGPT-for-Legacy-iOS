#import "LCSystemPromptViewController.h"
#import "CGAPIHelper.h"
#import <QuartzCore/QuartzCore.h>

@interface LCSystemPromptViewController ()

@property (nonatomic, retain) UITextView *textView;
@property (nonatomic, retain) UITableViewCell *textCell;

@end

@implementation LCSystemPromptViewController

@synthesize textView = _textView;
@synthesize textCell = _textCell;

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"System Prompt";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)] autorelease];

	self.textCell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
	self.textCell.selectionStyle = UITableViewCellSelectionStyleNone;
	self.textCell.backgroundColor = [UIColor whiteColor];
	self.textCell.clipsToBounds = YES;

	UITextView *textView = [[[UITextView alloc] initWithFrame:CGRectMake(8.0f, 6.0f, 284.0f, 188.0f)] autorelease];
	textView.font = [UIFont systemFontOfSize:15.0f];
	textView.textColor = [UIColor colorWithWhite:0.18f alpha:1.0f];
	textView.backgroundColor = [UIColor clearColor];
	textView.editable = YES;
	textView.scrollEnabled = YES;
	textView.alwaysBounceVertical = YES;
	textView.showsVerticalScrollIndicator = YES;
	textView.clipsToBounds = YES;
	textView.delegate = self;
	textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	textView.text = [CGAPIHelper configuredSystemPrompt];
	self.textView = textView;
	
	[self.textCell.contentView addSubview:self.textView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (section == 0) ? 1 : 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return (indexPath.section == 0) ? 200.0f : 44.0f;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return (section == 0) ? @"Custom System Prompt" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return @"This prompt is sent before each request, but is not saved into chat history. Clear it to disable.";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		CGFloat contentWidth = tableView.bounds.size.width - 20.0f;
		if (contentWidth < 200.0f) contentWidth = 300.0f;
		
		CGRect f = self.textView.frame;
		f.size.width = contentWidth - 16.0f;
		self.textView.frame = f;
		
		return self.textCell;
	} else {
		static NSString *CellIdentifier = @"ResetCell";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
		if (cell == nil) {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
			cell.textLabel.textAlignment = NSTextAlignmentCenter;
			cell.textLabel.textColor = [UIColor colorWithRed:0.0f green:0.4f blue:0.8f alpha:1.0f];
			cell.textLabel.font = [UIFont boldSystemFontOfSize:16.0f];
		}
		cell.textLabel.text = @"Restore Default Prompt";
		return cell;
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 1) {
		self.textView.text = [CGAPIHelper defaultSystemPrompt];
	}
}

- (void)saveTapped {
	[CGAPIHelper saveSystemPrompt:self.textView.text];
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)dealloc {
	[_textView release];
	[_textCell release];
	[super dealloc];
}

@end
