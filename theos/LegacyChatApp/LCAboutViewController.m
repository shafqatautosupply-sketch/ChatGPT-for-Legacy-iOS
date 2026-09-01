#import "LCAboutViewController.h"

static NSString * const LCAboutRepositoryURLString = @"https://github.com/wtfllix/ChatGPT-for-Legacy-iOS";

@implementation LCAboutViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"About Agentic";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		self.tableView.rowHeight = 56.0f;
	}
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) {
		return 2; // Name, Version
	}
	return 4; // Agentic Dev, bagxml, Original Chat Client, GitHub Repository
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) {
		return @"Application";
	}
	return @"Lineage & Credits";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1) {
		return @"Agentic is an autonomous AI agent and workspace for iOS 6. It is a major re-engineering and further fork built upon 'ChatGPT for Legacy iOS', whose main developer was bagxml. The original project itself originated from a legacy iOS chat client fork. Agentic was transformed and expanded by creative into a fully-featured autonomous agent with local tool execution.";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"AboutCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier] autorelease];
	}

	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
	cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
	cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.32f alpha:1.0f];

	if (indexPath.section == 0) {
		if (indexPath.row == 0) {
			cell.textLabel.text = @"Name";
			cell.detailTextLabel.text = @"Agentic";
		} else {
			cell.textLabel.text = @"Version";
			cell.detailTextLabel.text = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
		}
	} else {
		if (indexPath.row == 0) {
			cell.textLabel.text = @"Agentic Developer";
			cell.detailTextLabel.text = @"creative";
		} else if (indexPath.row == 1) {
			cell.textLabel.text = @"Core Framework Dev";
			cell.detailTextLabel.text = @"bagxml (ChatGPT for Legacy iOS)";
		} else if (indexPath.row == 2) {
			cell.textLabel.text = @"Original Client Base";
			cell.detailTextLabel.text = @"Legacy iOS Chat Client Fork";
		} else {
			cell.textLabel.text = @"Original Repository";
			cell.detailTextLabel.text = @"GitHub";
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 1 && indexPath.row == 3) {
		NSURL *url = [NSURL URLWithString:LCAboutRepositoryURLString];
		if (url != nil && [[UIApplication sharedApplication] canOpenURL:url]) {
			[[UIApplication sharedApplication] openURL:url];
		}
	}
}

@end
