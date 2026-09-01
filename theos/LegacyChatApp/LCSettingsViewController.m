#import "LCSettingsViewController.h"
#import "LCProviderProfilesViewController.h"
#import "LCSystemPromptViewController.h"
#import "LCAboutViewController.h"
#import "CGAgentSettingsViewController.h"
#import "LCRAWJSONViewController.h"
#import "LCChatLimitsViewController.h"
#import "LCConversationStore.h"
#import "CGAPIHelper.h"
#import "CGAPICommunicator.h"

@implementation LCSettingsViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Settings";
	}
	return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		self.tableView.rowHeight = 56.0f;
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 2;
	if (section == 1) return 3; // Agent Mode, Terminal Mode, Markdown Logic
	return 7;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Model";
	if (section == 1) return @"Mode";
	return @"Agent & Debugging";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return @"Manage providers and the optional system prompt sent before each request.";
	} else if (section == 1) {
		return @"Agent Mode enables local workspace tools and shell command execution. Terminal Mode switches the chat interface to a terminal console view. Markdown Logic enables rich formatting (headers, bold, code blocks) in chat bubbles.";
	}
	return @"Configure workspace directory, guardrails, message limits, and chat history compression.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"SettingsCell";

	if (indexPath.section == 1) {
		if (indexPath.row == 0) {
			static NSString *AgentCellID = @"AgentSwitchCell";
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:AgentCellID];
			if (cell == nil) {
				cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:AgentCellID] autorelease];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				UISwitch *agentSwitch = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
				cell.accessoryView = agentSwitch;
			}
			cell.textLabel.text = @"Agent Mode";
			UISwitch *agentSwitch = (UISwitch *)cell.accessoryView;
			[agentSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
			[agentSwitch addTarget:self action:@selector(agentSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			agentSwitch.on = [CGAPICommunicator isAgentModeEnabled];
			return cell;
		} else if (indexPath.row == 1) {
			static NSString *TerminalCellID = @"TerminalSwitchCell";
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:TerminalCellID];
			if (cell == nil) {
				cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:TerminalCellID] autorelease];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				UISwitch *terminalSwitch = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
				cell.accessoryView = terminalSwitch;
			}
			cell.textLabel.text = @"Terminal Mode";
			UISwitch *terminalSwitch = (UISwitch *)cell.accessoryView;
			[terminalSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
			[terminalSwitch addTarget:self action:@selector(terminalSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			terminalSwitch.on = [CGAPICommunicator isTerminalModeEnabled];
			return cell;
		} else {
			static NSString *MarkdownCellID = @"MarkdownSwitchCell";
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MarkdownCellID];
			if (cell == nil) {
				cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MarkdownCellID] autorelease];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				UISwitch *markdownSwitch = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
				cell.accessoryView = markdownSwitch;
			}
			cell.textLabel.text = @"Markdown Logic";
			UISwitch *markdownSwitch = (UISwitch *)cell.accessoryView;
			[markdownSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
			[markdownSwitch addTarget:self action:@selector(markdownSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			markdownSwitch.on = [CGAPICommunicator isMarkdownEnabled];
			return cell;
		}
	}

	if (indexPath.section == 2 && indexPath.row == 2) {
		static NSString *CompressionCellID = @"CompressionSwitchCell";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CompressionCellID];
		if (cell == nil) {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CompressionCellID] autorelease];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			UISwitch *compressionSwitch = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
			cell.accessoryView = compressionSwitch;
		}
		cell.textLabel.text = @"Auto-Compress Chat History";
		UISwitch *compressionSwitch = (UISwitch *)cell.accessoryView;
		[compressionSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
		[compressionSwitch addTarget:self action:@selector(compressionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
		compressionSwitch.on = [LCConversationStore isAutoCompressionEnabled];
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}

	if (indexPath.section == 0) {
		if (indexPath.row == 0) {
			cell.textLabel.text = @"Model Configurations";
		} else {
			cell.textLabel.text = @"System Prompt";
		}
	} else if (indexPath.section == 2) {
		if (indexPath.row == 0) {
			cell.textLabel.text = @"Agent Guardrails & Workspace";
		} else if (indexPath.row == 1) {
			cell.textLabel.text = @"Chat History Limits";
		} else if (indexPath.row == 2) {
			// Handled above as switch
		} else if (indexPath.row == 3) {
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.textLabel.text = @"Condense / Summarize Active Chat Now";
		} else if (indexPath.row == 4) {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.textLabel.text = @"Raw JSON Chat Debugger";
		} else if (indexPath.row == 5) {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.textLabel.text = @"Appearance";
		} else if (indexPath.row == 6) {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.textLabel.text = @"About";
		}
	}

	return cell;
}

- (void)agentSwitchChanged:(UISwitch *)sender {
	[CGAPICommunicator setAgentModeEnabled:sender.isOn];
}

- (void)terminalSwitchChanged:(UISwitch *)sender {
	[CGAPICommunicator setTerminalModeEnabled:sender.isOn];
}

- (void)markdownSwitchChanged:(UISwitch *)sender {
	[CGAPICommunicator setMarkdownEnabled:sender.isOn];
}

- (void)compressionSwitchChanged:(UISwitch *)sender {
	[LCConversationStore setAutoCompressionEnabled:sender.isOn];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0) {
		if (indexPath.row == 0) {
			LCProviderProfilesViewController *controller = [[[LCProviderProfilesViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
		} else {
			LCSystemPromptViewController *controller = [[[LCSystemPromptViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
		}
		return;
	}

	if (indexPath.section == 2) {
		if (indexPath.row == 0) {
			CGAgentSettingsViewController *controller = [[[CGAgentSettingsViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		} else if (indexPath.row == 1) {
			LCChatLimitsViewController *controller = [[[LCChatLimitsViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		} else if (indexPath.row == 3) {
			BOOL success = [LCConversationStore compressCurrentConversationInPlace];
			if (success) {
				UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Success"
					message:@"Active chat history has been successfully condensed into an AI-powered summary."
					delegate:nil
					cancelButtonTitle:@"OK"
					otherButtonTitles:nil] autorelease];
				[alert show];
			} else {
				UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"AI Summarization Unavailable"
					message:@"Unable to reach AI model (offline or missing API key). Please check your API configuration and internet connection."
					delegate:nil
					cancelButtonTitle:@"OK"
					otherButtonTitles:nil] autorelease];
				[alert show];
			}
			return;
		} else if (indexPath.row == 0) { // handled above
		} else if (indexPath.row == 4) {
			LCRAWJSONViewController *controller = [[[LCRAWJSONViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		} else if (indexPath.row == 6) {
			LCAboutViewController *controller = [[[LCAboutViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		}
	}

	if (indexPath.section != 1) {
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Coming Soon"
			message:@"This settings section is reserved for a later pass."
			delegate:nil
			cancelButtonTitle:@"OK"
			otherButtonTitles:nil] autorelease];
		[alert show];
	}
}

@end
