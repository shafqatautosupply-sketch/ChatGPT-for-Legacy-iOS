#import "AGAgentSettingsViewController.h"
#import "AGProviderConfig.h"
#import "AGGuardrails.h"
#import "AGHTTPClient.h"
#import <QuartzCore/QuartzCore.h>

@interface AGAgentTextEditorViewController : UITableViewController <UIAlertViewDelegate>
@property (nonatomic, retain) NSMutableArray *items;
@property (nonatomic, copy) NSString *defaultsKey;
@property (nonatomic, assign) NSInteger editingIndex;
@property (nonatomic, copy) NSString *footerNote;
@end

@implementation AGAgentTextEditorViewController

@synthesize items = _items;
@synthesize defaultsKey = _defaultsKey;
@synthesize editingIndex = _editingIndex;
@synthesize footerNote = _footerNote;

/// `items` is what the list starts with when nothing is saved yet. Because it is
/// taken from AGGuardrails, opening and saving a list can no longer silently
/// replace the real defaults with a shorter hand-typed copy (which weakened the
/// guardrails and dropped allowed tools).
- (id)initWithTitle:(NSString *)title defaultsKey:(NSString *)key defaultItems:(NSArray *)defaultItems footerNote:(NSString *)note {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = title;
        self.defaultsKey = key;
        self.footerNote = note;
        self.editingIndex = -1;
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
        _items = [[NSMutableArray alloc] initWithArray:(saved != nil ? saved : defaultItems)];
    }
    return self;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return (section == 0) ? self.footerNote : nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)] autorelease];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return [self.items count];
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return self.title;
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *CellID = @"ItemCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellID];
        if (cell == nil) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellID] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
        cell.textLabel.text = [self.items objectAtIndex:indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:17.0f];
        return cell;
    } else {
        static NSString *AddCellID = @"AddCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:AddCellID];
        if (cell == nil) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:AddCellID] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.textColor = [UIColor colorWithRed:0.0f green:0.4f blue:0.8f alpha:1.0f];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0f];
        }
        cell.textLabel.text = @"+ Add New Item";
        return cell;
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.section == 0);
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        [self.items removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1) {
        self.editingIndex = -1;
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Add Item"
            message:@"Enter new item:"
            delegate:self
            cancelButtonTitle:@"Cancel"
            otherButtonTitles:@"Add", nil] autorelease];
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        [alert show];
    } else {
        self.editingIndex = indexPath.row;
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Edit Item"
            message:@"Modify item:"
            delegate:self
            cancelButtonTitle:@"Cancel"
            otherButtonTitles:@"Save", nil] autorelease];
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        UITextField *tf = [alert textFieldAtIndex:0];
        tf.text = [self.items objectAtIndex:indexPath.row];
        [alert show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        UITextField *tf = [alertView textFieldAtIndex:0];
        NSString *text = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([text length] > 0) {
            if (self.editingIndex == -1) {
                [self.items addObject:text];
                NSIndexPath *newPath = [NSIndexPath indexPathForRow:[self.items count] - 1 inSection:0];
                [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            } else {
                [self.items replaceObjectAtIndex:self.editingIndex withObject:text];
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.editingIndex inSection:0];
                [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
        }
    }
}

- (void)saveTapped {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.items forKey:self.defaultsKey];
    [defaults synchronize];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)dealloc {
    [_items release];
    [_defaultsKey release];
    [_footerNote release];
    [super dealloc];
}

@end


@interface AGAgentSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, retain) UITextField *workspaceField;
@property (nonatomic, retain) UITextField *intervalField;
@property (nonatomic, retain) UITextField *timeoutField;
@property (nonatomic, retain) UITextField *stepsField;
@end

@implementation AGAgentSettingsViewController

@synthesize workspaceField = _workspaceField;
@synthesize intervalField = _intervalField;
@synthesize timeoutField = _timeoutField;
@synthesize stepsField = _stepsField;

enum { AGSectionWorkspace = 0, AGSectionInterval, AGSectionLimits, AGSectionTLS, AGSectionLists, AGSectionCount };

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) self.title = @"Agent Guardrails";
	return self;
}

- (UITextField *)makeFieldWithText:(NSString *)text keyboard:(UIKeyboardType)keyboard {
	UITextField *field = [[[UITextField alloc] initWithFrame:CGRectMake(12.0f, 10.0f, 260.0f, 24.0f)] autorelease];
	field.borderStyle = UITextBorderStyleNone;
	field.font = [UIFont systemFontOfSize:17.0f];
	field.keyboardType = keyboard;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	field.text = text;
	return field;
}

- (NSString *)defaultSandboxPath {
	NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
	if ([docs length] == 0) docs = @"/var/mobile/Documents";
	return [docs stringByAppendingPathComponent:@"SandBox"];
}

- (NSString *)stringForDefaultsKey:(NSString *)key fallback:(NSString *)fallback {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	return (value != nil) ? [NSString stringWithFormat:@"%@", value] : fallback;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)] autorelease];
	NSString *savedWs = [[NSUserDefaults standardUserDefaults] stringForKey:@"agent_workspace_dir"];
	self.workspaceField = [self makeFieldWithText:([savedWs length] > 0 ? savedWs : [self defaultSandboxPath]) keyboard:UIKeyboardTypeDefault];
	// 5.0 is the value the agent really uses when nothing is saved (the screen used to show 1.0).
	self.intervalField = [self makeFieldWithText:[self stringForDefaultsKey:@"agent_min_request_interval" fallback:@"5.0"] keyboard:UIKeyboardTypeDecimalPad];
	self.timeoutField = [self makeFieldWithText:[self stringForDefaultsKey:@"agent_command_timeout" fallback:@"120"] keyboard:UIKeyboardTypeNumberPad];
	self.stepsField = [self makeFieldWithText:[self stringForDefaultsKey:@"agent_max_steps" fallback:@"40"] keyboard:UIKeyboardTypeNumberPad];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return AGSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == AGSectionLimits) return 2;
	if (section == AGSectionLists) return 4;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case AGSectionWorkspace: return @"Workspace Directory";
		case AGSectionInterval: return @"Minimum seconds between requests";
		case AGSectionLimits: return @"Safety limits";
		case AGSectionTLS: return @"Network security";
		default: return @"Agent Guardrails";
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == AGSectionLimits) return @"Row 1: seconds before a running command is killed. Row 2: maximum model requests per task, a guard against runaway loops.";
	if (section == AGSectionTLS) return @"Certificates are verified against the bundled CA list. Turn this on only if a verified connection fails and you accept that anyone on the network could read your API key.";
	if (section == AGSectionLists) return @"Commands run without a shell: pipes, redirects, ; and $() are not available. Hard Block and Secret paths always include the built-in list; entries here are added to it.";
	return nil;
}

- (UITableViewCell *)fieldCellWithID:(NSString *)identifier field:(UITextField *)field label:(NSString *)label tableView:(UITableView *)tableView {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		[cell.contentView addSubview:field];
	}
	CGFloat contentWidth = tableView.bounds.size.width - 20.0f;
	if (contentWidth < 200.0f) contentWidth = 300.0f;
	CGRect frame = field.frame;
	frame.size.width = contentWidth - 24.0f;
	field.frame = frame;
	field.placeholder = label;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	switch (indexPath.section) {
		case AGSectionWorkspace: return [self fieldCellWithID:@"WorkspaceCell" field:self.workspaceField label:@"Workspace path" tableView:tableView];
		case AGSectionInterval: return [self fieldCellWithID:@"IntervalCell" field:self.intervalField label:@"Seconds" tableView:tableView];
		case AGSectionLimits:
			return (indexPath.row == 0)
				? [self fieldCellWithID:@"TimeoutCell" field:self.timeoutField label:@"Command timeout (seconds)" tableView:tableView]
				: [self fieldCellWithID:@"StepsCell" field:self.stepsField label:@"Max agent steps per task" tableView:tableView];
		case AGSectionTLS: {
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TLSCell"];
			if (cell == nil) {
				cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TLSCell"] autorelease];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cell.accessoryView = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
			}
			cell.textLabel.text = @"Allow insecure TLS";
			UISwitch *toggle = (UISwitch *)cell.accessoryView;
			[toggle removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
			[toggle addTarget:self action:@selector(tlsSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			toggle.on = [AGHTTPClient isInsecureTLSEnabled];
			return cell;
		}
		default: {
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GuardrailCell"];
			if (cell == nil) {
				cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"GuardrailCell"] autorelease];
				cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
				cell.selectionStyle = UITableViewCellSelectionStyleBlue;
				cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0f];
			}
			NSArray *titles = [NSArray arrayWithObjects:@"Pre-Execution Commands", @"Allowed Binaries", @"Hard Block Paths", @"Secret Paths", nil];
			cell.textLabel.text = [titles objectAtIndex:(NSUInteger)indexPath.row];
			return cell;
		}
	}
}

- (void)tlsSwitchChanged:(UISwitch *)sender {
	[AGHTTPClient setInsecureTLSEnabled:sender.isOn];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != AGSectionLists) return;

	NSString *builtIn = nil;
	AGAgentTextEditorViewController *editor = nil;
	switch (indexPath.row) {
		case 0:
			editor = [[[AGAgentTextEditorViewController alloc] initWithTitle:@"Pre-Execution Commands" defaultsKey:@"agent_pre_execution_commands"
				defaultItems:[AGGuardrails defaultPreExecutionCommands] footerNote:@"Only 'export NAME=value' lines are used (there is no shell to run anything else)."] autorelease];
			break;
		case 1:
			editor = [[[AGAgentTextEditorViewController alloc] initWithTitle:@"Allowed Binaries" defaultsKey:@"agent_allowed_binaries"
				defaultItems:[AGGuardrails defaultAllowedBinaries] footerNote:@"cycript is not allowed by default: it can run arbitrary code and attach to other processes."] autorelease];
			break;
		case 2:
			builtIn = [[AGGuardrails defaultHardBlockPaths] componentsJoinedByString:@"  "];
			editor = [[[AGAgentTextEditorViewController alloc] initWithTitle:@"Hard Block Paths" defaultsKey:@"agent_hard_block_paths"
				defaultItems:[NSArray array] footerNote:[@"Always blocked: " stringByAppendingString:builtIn]] autorelease];
			break;
		default:
			builtIn = [[AGGuardrails defaultSecretPaths] componentsJoinedByString:@"  "];
			editor = [[[AGAgentTextEditorViewController alloc] initWithTitle:@"Secret Paths" defaultsKey:@"agent_secret_paths"
				defaultItems:[NSArray array] footerNote:[@"Always blocked: " stringByAppendingString:builtIn]] autorelease];
			break;
	}
	[self.navigationController pushViewController:editor animated:YES];
}

- (void)saveTapped {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *workspace = [self.workspaceField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([workspace length] == 0) workspace = [self defaultSandboxPath];
	workspace = [workspace stringByStandardizingPath];

	NSFileManager *fm = [NSFileManager defaultManager];
	NSError *error = nil;
	if (![fm fileExistsAtPath:workspace]) [fm createDirectoryAtPath:workspace withIntermediateDirectories:YES attributes:nil error:&error];
	if (error != nil) { // e.g. Cocoa error 513, no permission
		workspace = [self defaultSandboxPath];
		[fm createDirectoryAtPath:workspace withIntermediateDirectories:YES attributes:nil error:nil];
	}
	self.workspaceField.text = workspace;

	[defaults setObject:workspace forKey:@"agent_workspace_dir"];
	[defaults setDouble:MAX(0.0, [self.intervalField.text doubleValue]) forKey:@"agent_min_request_interval"];
	[defaults setDouble:MIN(900.0, MAX(1.0, [self.timeoutField.text doubleValue])) forKey:@"agent_command_timeout"];
	[defaults setInteger:MIN(200, MAX(1, [self.stepsField.text integerValue])) forKey:@"agent_max_steps"];
	[defaults synchronize];

	NSString *message = (error != nil)
		? [NSString stringWithFormat:@"No permission for that path. Workspace set to: %@", workspace]
		: @"Settings saved.";
	[[[[UIAlertView alloc] initWithTitle:@"Saved" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
}

- (void)dealloc {
	[_workspaceField release]; [_intervalField release]; [_timeoutField release]; [_stepsField release];
	[super dealloc];
}

@end
