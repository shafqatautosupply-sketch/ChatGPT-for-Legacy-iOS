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
#import "AGInfoCell.h"

// Every row on this screen, so sections can be rearranged by editing one table.
typedef enum {
	AGRowModelConfigs, AGRowSystemPrompt, AGRowThinking,
	AGRowAgentMode, AGRowAgentGuardrails,
	AGRowTerminalMode, AGRowMarkdown, AGRowChatLimits,
	AGRowTokenSaver, AGRowUsage,
	AGRowWebSwitch, AGRowWebDevices,
	AGRowRawJSON, AGRowAbout
} AGSettingsRow;

static NSArray *AGSettingsLayout(void) {
	static NSArray *layout = nil;
	if (layout == nil) {
		#define SEC(t, ...) [NSDictionary dictionaryWithObjectsAndKeys:t, @"title", [NSArray arrayWithObjects:__VA_ARGS__, nil], @"rows", nil]
		#define ROW(r) [NSNumber numberWithInt:r]
		layout = [[NSArray alloc] initWithObjects:
			SEC(@"Model",          ROW(AGRowModelConfigs), ROW(AGRowSystemPrompt), ROW(AGRowThinking)),
			SEC(@"Agent",          ROW(AGRowAgentMode), ROW(AGRowAgentGuardrails)),
			SEC(@"Chat",           ROW(AGRowTerminalMode), ROW(AGRowMarkdown), ROW(AGRowChatLimits)),
			SEC(@"Token usage",    ROW(AGRowTokenSaver), ROW(AGRowUsage)),
			SEC(@"Other devices",  ROW(AGRowWebSwitch), ROW(AGRowWebDevices)),
			SEC(@"Advanced",       ROW(AGRowRawJSON), ROW(AGRowAbout)),
			nil];
		#undef SEC
		#undef ROW
	}
	return layout;
}

static AGSettingsRow AGRowAt(NSIndexPath *indexPath) {
	NSArray *rows = [[AGSettingsLayout() objectAtIndex:(NSUInteger)indexPath.section] objectForKey:@"rows"];
	return (AGSettingsRow)[[rows objectAtIndex:(NSUInteger)indexPath.row] intValue];
}

static NSString *AGInfoForRow(AGSettingsRow row) {
	switch (row) {
		case AGRowThinking:
			return @"How much a Gemini 3 or newer model reasons before it answers (Agent Mode).\n\nAuto uses Medium on Flash-Lite models, which stop too early at their minimal default, and the model's own default on the others. Higher is slower and costs more.\n\nGemini 2.5 and OpenAI-compatible profiles ignore it.";
		case AGRowAgentMode:
			return @"Turns on the local workspace tools and shell command execution.";
		case AGRowTerminalMode:
			return @"Switches the chat screen to a terminal console view.";
		case AGRowMarkdown:
			return @"Shows rich formatting (headers, bold, code blocks) in chat bubbles.";
		case AGRowTokenSaver:
			return @"Shrinks old tool output and drops old turns from what is sent to the model. Your saved chat is never changed.\n\nThe budget is set under Chat History Limits.";
		case AGRowWebSwitch:
			return @"Shows a chat page on your Wi-Fi that another device (Android TV, tablet, laptop) can open.\n\nEach device has to be allowed on this phone first. There is no password.";
		default:
			return nil;
	}
}

@implementation AGSettingsViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Settings";
	}
	return self;
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

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (NSInteger)[AGSettingsLayout() count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[[[AGSettingsLayout() objectAtIndex:(NSUInteger)section] objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return [[AGSettingsLayout() objectAtIndex:(NSUInteger)section] objectForKey:@"title"];
}

/// A cell with a title, an optional (i) button and either a switch, a value or a chevron.
- (AGInfoCell *)cellWithStyle:(UITableViewCellStyle)style row:(AGSettingsRow)row tableView:(UITableView *)tableView {
	NSString *identifier = [NSString stringWithFormat:@"Row%d-%d", (int)row, (int)style];
	AGInfoCell *cell = (AGInfoCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil) {
		cell = [[[AGInfoCell alloc] initWithStyle:style reuseIdentifier:identifier] autorelease];
	}
	cell.infoText = AGInfoForRow(row);
	return cell;
}

- (AGInfoCell *)switchCellForRow:(AGSettingsRow)row title:(NSString *)title on:(BOOL)on action:(SEL)action tableView:(UITableView *)tableView {
	AGInfoCell *cell = [self cellWithStyle:UITableViewCellStyleDefault row:row tableView:tableView];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	UISwitch *toggle = (UISwitch *)cell.accessoryView;
	if (![toggle isKindOfClass:[UISwitch class]]) {
		toggle = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
		cell.accessoryView = toggle;
	}
	cell.textLabel.text = title;
	[toggle removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
	[toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	toggle.on = on;
	return cell;
}

- (AGInfoCell *)linkCellForRow:(AGSettingsRow)row title:(NSString *)title value:(NSString *)value tableView:(UITableView *)tableView {
	AGInfoCell *cell = [self cellWithStyle:(value != nil ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault) row:row tableView:tableView];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.textLabel.text = title;
	cell.detailTextLabel.text = value;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	AGSettingsRow row = AGRowAt(indexPath);
	switch (row) {
		case AGRowModelConfigs:
			return [self linkCellForRow:row title:@"Model Configurations" value:nil tableView:tableView];
		case AGRowSystemPrompt:
			return [self linkCellForRow:row title:@"System Prompt" value:nil tableView:tableView];
		case AGRowThinking:
			return [self linkCellForRow:row title:@"Thinking" value:[AGProviderConfig displayNameForThinkingLevel:[AGProviderConfig thinkingLevelSetting]] tableView:tableView];
		case AGRowAgentMode:
			return [self switchCellForRow:row title:@"Agent Mode" on:[AGChatClient isAgentModeEnabled] action:@selector(agentSwitchChanged:) tableView:tableView];
		case AGRowAgentGuardrails:
			return [self linkCellForRow:row title:@"Guardrails & Workspace" value:nil tableView:tableView];
		case AGRowTerminalMode:
			return [self switchCellForRow:row title:@"Terminal Mode" on:[AGChatClient isTerminalModeEnabled] action:@selector(terminalSwitchChanged:) tableView:tableView];
		case AGRowMarkdown:
			return [self switchCellForRow:row title:@"Markdown Logic" on:[AGChatClient isMarkdownEnabled] action:@selector(markdownSwitchChanged:) tableView:tableView];
		case AGRowChatLimits:
			return [self linkCellForRow:row title:@"Chat History Limits" value:nil tableView:tableView];
		case AGRowTokenSaver:
			return [self switchCellForRow:row title:@"Token Saver" on:[AGConversationStore isTokenSaverEnabled] action:@selector(compressionSwitchChanged:) tableView:tableView];
		case AGRowUsage: {
			AGInfoCell *cell = [self cellWithStyle:UITableViewCellStyleDefault row:row tableView:tableView];
			cell.accessoryView = nil;
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			NSDictionary *usage = [AGChatClient lastUsage];
			cell.textLabel.text = (usage == nil)
				? @"Last request: no data yet"
				: [NSString stringWithFormat:@"Last request: %@ in (%@ cached), %@ out", [usage objectForKey:@"prompt"], [usage objectForKey:@"cached"], [usage objectForKey:@"output"]];
			cell.textLabel.font = [UIFont systemFontOfSize:14.0f];
			return cell;
		}
		case AGRowWebSwitch:
			return [self switchCellForRow:row title:@"Web Access" on:[AGWebAccess isEnabled] action:@selector(webSwitchChanged:) tableView:tableView];
		case AGRowWebDevices: {
			NSString *value = [AGWebAccess isRunning] ? [NSString stringWithFormat:@"Port %lu", (unsigned long)[AGWebAccess port]] : ([AGWebAccess lastError] != nil ? @"Error" : @"Off");
			return [self linkCellForRow:row title:@"Address & Devices" value:value tableView:tableView];
		}
		case AGRowRawJSON:
			return [self linkCellForRow:row title:@"Raw JSON Chat Debugger" value:nil tableView:tableView];
		case AGRowAbout:
		default:
			return [self linkCellForRow:row title:@"About" value:nil tableView:tableView];
	}
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
	UIViewController *controller = nil;
	switch (AGRowAt(indexPath)) {
		case AGRowModelConfigs:    controller = [[[AGProviderProfilesViewController alloc] init] autorelease]; break;
		case AGRowSystemPrompt:    controller = [[[AGSystemPromptViewController alloc] init] autorelease]; break;
		case AGRowThinking:        [self showThinkingMenu]; return;
		case AGRowAgentGuardrails: controller = [[[AGAgentSettingsViewController alloc] init] autorelease]; break;
		case AGRowChatLimits:      controller = [[[AGChatLimitsViewController alloc] init] autorelease]; break;
		case AGRowWebDevices:      controller = [[[AGWebAccessViewController alloc] init] autorelease]; break;
		case AGRowRawJSON:         controller = [[[AGRawJSONViewController alloc] init] autorelease]; break;
		case AGRowAbout:           controller = [[[AGAboutViewController alloc] init] autorelease]; break;
		default: return;   // switches and the read-only usage row
	}
	[self.navigationController pushViewController:controller animated:YES];
}

@end
