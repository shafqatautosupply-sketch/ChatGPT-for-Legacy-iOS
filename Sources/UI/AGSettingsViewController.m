#import "AGSettingsViewController.h"
#import "AGProviderProfilesViewController.h"
#import "AGSystemPromptViewController.h"
#import "AGAboutViewController.h"
#import "AGAgentSettingsViewController.h"
#import "AGRawJSONViewController.h"
#import "AGChatLimitsViewController.h"
#import "AGConversationStore.h"
#import "AGProviderConfig.h"
#import "AGChatClient.h"
#import "AGWebAccess.h"
#import "AGWebAccessViewController.h"

@implementation AGSettingsViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Settings";
	}
	return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
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
	if (section == 0) return 3;
	if (section == 1) return 3;
	if (section == 3) return 2;
	return 6;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Model";
	if (section == 1) return @"Mode";
	if (section == 3) return @"Other devices";
	return @"Agent & Debugging";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return @"Manage providers and the optional system prompt sent before each request. Thinking is how much a Gemini 3 or newer model reasons before it answers (Agent Mode). Auto uses Medium on Flash-Lite models, which stop too early at their minimal default, and the model's own default on the others. Higher is slower and costs more. Gemini 2.5 and OpenAI-compatible profiles ignore it.";
	} else if (section == 3) {
		return @"Web Access shows a chat page on your Wi-Fi for another device (Android TV, tablet, laptop). Each device has to be allowed on this phone first. No password.";
	} else if (section == 1) {
		return @"Agent Mode enables local workspace tools and shell command execution. Terminal Mode switches the chat interface to a terminal console view. Markdown Logic enables rich formatting (headers, bold, code blocks) in chat bubbles.";
	}
	return @"Token Saver shrinks old tool output and drops old turns from what is sent to the model (your saved chat is never changed). The usage row shows what the last request cost.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"SettingsCell";

	if (indexPath.section == 3) {
		if (indexPath.row == 0) {
			static NSString *WebCellID = @"WebSwitchCell";
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:WebCellID];
			if (cell == nil) {
				cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:WebCellID] autorelease];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cell.accessoryView = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
			}
			cell.textLabel.text = @"Web Access";
			UISwitch *webSwitch = (UISwitch *)cell.accessoryView;
			[webSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
			[webSwitch addTarget:self action:@selector(webSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			webSwitch.on = [AGWebAccess isEnabled];
			return cell;
		}
		static NSString *WebDetailID = @"WebDetailCell";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:WebDetailID];
		if (cell == nil) {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:WebDetailID] autorelease];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		cell.textLabel.text = @"Address & Devices";
		cell.detailTextLabel.text = [AGWebAccess isRunning] ? [NSString stringWithFormat:@"Port %lu", (unsigned long)[AGWebAccess port]] : ([AGWebAccess lastError] != nil ? @"Error" : @"Off");
		return cell;
	}

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
			agentSwitch.on = [AGChatClient isAgentModeEnabled];
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
			terminalSwitch.on = [AGChatClient isTerminalModeEnabled];
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
			markdownSwitch.on = [AGChatClient isMarkdownEnabled];
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
		cell.textLabel.text = @"Token Saver";
		UISwitch *compressionSwitch = (UISwitch *)cell.accessoryView;
		[compressionSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
		[compressionSwitch addTarget:self action:@selector(compressionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
		compressionSwitch.on = [AGConversationStore isTokenSaverEnabled];
		return cell;
	}

	if (indexPath.section == 0 && indexPath.row == 2) {
		static NSString *ThinkingCellID = @"ThinkingCell";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ThinkingCellID];
		if (cell == nil) {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ThinkingCellID] autorelease];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		cell.textLabel.text = @"Thinking";
		cell.detailTextLabel.text = [AGProviderConfig displayNameForThinkingLevel:[AGProviderConfig thinkingLevelSetting]];
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
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			NSDictionary *usage = [AGChatClient lastUsage];
			if (usage == nil) {
				cell.textLabel.text = @"Last request: no data yet";
			} else {
				cell.textLabel.text = [NSString stringWithFormat:@"Last request: %@ in (%@ cached), %@ out",
					[usage objectForKey:@"prompt"], [usage objectForKey:@"cached"], [usage objectForKey:@"output"]];
			}
			cell.textLabel.font = [UIFont systemFontOfSize:14.0f];
		} else if (indexPath.row == 4) {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.textLabel.text = @"Raw JSON Chat Debugger";
		} else if (indexPath.row == 5) {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.textLabel.text = @"About";
		}
	}

	return cell;
}

- (void)webSwitchChanged:(UISwitch *)sender {
	BOOL on = sender.isOn;
	[AGWebAccess setEnabled:on];
	[self.tableView reloadData];   // shows the port or the error
	if (on && ![AGWebAccess isRunning]) {   // could not start (port in use...)
		[[[[UIAlertView alloc] initWithTitle:@"Web Access could not start" message:([AGWebAccess lastError] ?: @"Unknown error.")
			delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
	}
}

- (void)agentSwitchChanged:(UISwitch *)sender {
	[AGChatClient setAgentModeEnabled:sender.isOn];
}

- (void)terminalSwitchChanged:(UISwitch *)sender {
	[AGChatClient setTerminalModeEnabled:sender.isOn];
}

- (void)markdownSwitchChanged:(UISwitch *)sender {
	[AGChatClient setMarkdownEnabled:sender.isOn];
}

- (void)showThinkingMenu {
	UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Thinking level" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil] autorelease];
	NSString *current = [AGProviderConfig thinkingLevelSetting];
	for (NSString *choice in [AGProviderConfig thinkingLevelChoices]) {
		NSString *name = [AGProviderConfig displayNameForThinkingLevel:choice];
		[sheet addButtonWithTitle:[choice isEqualToString:current] ? [@"\u2713 " stringByAppendingString:name] : name];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	NSArray *choices = [AGProviderConfig thinkingLevelChoices];
	if (buttonIndex == sheet.cancelButtonIndex || buttonIndex < 0 || (NSUInteger)buttonIndex >= [choices count]) return;
	[AGProviderConfig setThinkingLevelSetting:[choices objectAtIndex:(NSUInteger)buttonIndex]];
	[self.tableView reloadData];
}

- (void)compressionSwitchChanged:(UISwitch *)sender {
	[AGConversationStore setTokenSaverEnabled:sender.isOn];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 3) {
		if (indexPath.row == 1) [self.navigationController pushViewController:[[[AGWebAccessViewController alloc] init] autorelease] animated:YES];
		return;
	}
	if (indexPath.section == 0) {
		if (indexPath.row == 2) {
			[self showThinkingMenu];
			return;
		}
		if (indexPath.row == 0) {
			AGProviderProfilesViewController *controller = [[[AGProviderProfilesViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
		} else {
			AGSystemPromptViewController *controller = [[[AGSystemPromptViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
		}
		return;
	}

	if (indexPath.section == 2) {
		if (indexPath.row == 0) {
			AGAgentSettingsViewController *controller = [[[AGAgentSettingsViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		} else if (indexPath.row == 1) {
			AGChatLimitsViewController *controller = [[[AGChatLimitsViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		} else if (indexPath.row == 3) {
			return; // read-only usage row
		} else if (indexPath.row == 4) {
			AGRawJSONViewController *controller = [[[AGRawJSONViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		} else if (indexPath.row == 5) {
			AGAboutViewController *controller = [[[AGAboutViewController alloc] init] autorelease];
			[self.navigationController pushViewController:controller animated:YES];
			return;
		}
	}

}

@end
