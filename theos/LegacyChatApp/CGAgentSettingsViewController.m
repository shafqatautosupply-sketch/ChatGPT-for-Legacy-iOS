#import "CGAgentSettingsViewController.h"
#import "CGAPIHelper.h"
#import <QuartzCore/QuartzCore.h>

@interface CGAgentTextEditorViewController : UITableViewController <UIAlertViewDelegate>
@property (nonatomic, retain) NSMutableArray *items;
@property (nonatomic, copy) NSString *defaultsKey;
@property (nonatomic, assign) NSInteger editingIndex;
@end

@implementation CGAgentTextEditorViewController

@synthesize items = _items;
@synthesize defaultsKey = _defaultsKey;
@synthesize editingIndex = _editingIndex;

- (id)initWithTitle:(NSString *)title defaultsKey:(NSString *)key defaultValueString:(NSString *)defVal {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = title;
        self.defaultsKey = key;
        self.editingIndex = -1;
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray *saved = [defaults arrayForKey:key];
        if (saved != nil) {
            _items = [[NSMutableArray alloc] initWithArray:saved];
        } else {
            NSArray *components = [defVal componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n"]];
            NSMutableArray *parsed = [NSMutableArray array];
            for (NSString *s in components) {
                NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([t length] > 0) [parsed addObject:t];
            }
            _items = [[NSMutableArray alloc] initWithArray:parsed];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)] autorelease];
    // Left bar button is left unset so the native back button automatically appears on the top-left
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
    [super dealloc];
}

@end


@interface CGAgentSettingsViewController () <UITextFieldDelegate>
@property (nonatomic, retain) UITextField *workspaceField;
@property (nonatomic, retain) UITextField *intervalField;
@end

@implementation CGAgentSettingsViewController

@synthesize workspaceField = _workspaceField;
@synthesize intervalField = _intervalField;

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Agent Guardrails";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveTapped)] autorelease];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	self.workspaceField = [[[UITextField alloc] initWithFrame:CGRectMake(12.0f, 10.0f, 260.0f, 24.0f)] autorelease];
	self.workspaceField.borderStyle = UITextBorderStyleNone;
	self.workspaceField.font = [UIFont systemFontOfSize:17.0f];
	self.workspaceField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.workspaceField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.workspaceField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	NSString *savedWs = [defaults stringForKey:@"agent_workspace_dir"];
	self.workspaceField.text = ([savedWs length] > 0 ? savedWs : @"/var/mobile/Documents/SandBox");

	self.intervalField = [[[UITextField alloc] initWithFrame:CGRectMake(12.0f, 10.0f, 260.0f, 24.0f)] autorelease];
	self.intervalField.borderStyle = UITextBorderStyleNone;
	self.intervalField.font = [UIFont systemFontOfSize:17.0f];
	self.intervalField.keyboardType = UIKeyboardTypeDecimalPad;
	self.intervalField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.intervalField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.intervalField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	id savedInterval = [defaults objectForKey:@"agent_min_request_interval"];
	self.intervalField.text = (savedInterval != nil) ? [NSString stringWithFormat:@"%@", savedInterval] : @"1.0";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 1;
    return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Workspace Directory";
	if (section == 1) return @"Intervals between requests (sec)";
	return @"Agent Guardrails";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 44.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat contentWidth = tableView.bounds.size.width - 20.0f;
    if (contentWidth < 200.0f) contentWidth = 300.0f;

	if (indexPath.section == 0) {
        static NSString *WorkspaceCellID = @"WorkspaceCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:WorkspaceCellID];
        if (cell == nil) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:WorkspaceCellID] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            [cell.contentView addSubview:self.workspaceField];
        }
        CGRect f = self.workspaceField.frame;
        f.size.width = contentWidth - 24.0f;
        self.workspaceField.frame = f;
        return cell;
    }
	else if (indexPath.section == 1) {
        static NSString *IntervalCellID = @"IntervalCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:IntervalCellID];
        if (cell == nil) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:IntervalCellID] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            [cell.contentView addSubview:self.intervalField];
        }
        CGRect f = self.intervalField.frame;
        f.size.width = contentWidth - 24.0f;
        self.intervalField.frame = f;
        return cell;
    }
    else {
        static NSString *GuardrailCellID = @"GuardrailCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:GuardrailCellID];
        if (cell == nil) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:GuardrailCellID] autorelease];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0f];
        }
        
        switch (indexPath.row) {
            case 0: cell.textLabel.text = @"Pre-Execution Commands"; break;
            case 1: cell.textLabel.text = @"Allowed Binaries"; break;
            case 2: cell.textLabel.text = @"Hard Block Paths"; break;
            case 3: cell.textLabel.text = @"Secret Paths"; break;
            case 4: cell.textLabel.text = @"Obfuscation Blocks"; break;
            default: cell.textLabel.text = @""; break;
        }
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section < 2) return;
    
    CGAgentTextEditorViewController *editor = nil;
    
    switch (indexPath.row) {
        case 0:
            editor = [[[CGAgentTextEditorViewController alloc] initWithTitle:@"Pre-Execution Commands" defaultsKey:@"agent_pre_execution_commands" defaultValueString:@"export THEOS=/var/mobile/theos"] autorelease];
            break;
        case 1:
            editor = [[[CGAgentTextEditorViewController alloc] initWithTitle:@"Allowed Binaries" defaultsKey:@"agent_allowed_binaries" defaultValueString:@"make, clang, cc, c++, as, ld, lipo, strip, dpkg-deb, ldid, echo, cat, ls, cp, mv, mkdir, touch, grep, find, tar, zip, unzip, date"] autorelease];
            break;
        case 2:
            editor = [[[CGAgentTextEditorViewController alloc] initWithTitle:@"Hard Block Paths" defaultsKey:@"agent_hard_block_paths" defaultValueString:@"/System\n/usr/lib\n/usr/libexec\n/usr/sbin\n/sbin\n/bin\n/boot\n/var/stash"] autorelease];
            break;
        case 3:
            editor = [[[CGAgentTextEditorViewController alloc] initWithTitle:@"Secret Paths" defaultsKey:@"agent_secret_paths" defaultValueString:@"/var/Keychains\n/var/mobile/Library/Mail\n/private/var/db\n/var/mobile/Library/Accounts"] autorelease];
            break;
        case 4:
            editor = [[[CGAgentTextEditorViewController alloc] initWithTitle:@"Obfuscation Blocks" defaultsKey:@"agent_obfuscation_blocks" defaultValueString:@"base64\nxxd\nopenssl\neval\nexec\npython\nperl\nruby\nnc\nnetcat\ncurl\wget"] autorelease];
            break;
        default:
            return;
    }
    
    if (editor) {
        [self.navigationController pushViewController:editor animated:YES];
    }
}

- (void)saveTapped {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:[self.workspaceField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:@"agent_workspace_dir"];
	[defaults setDouble:[self.intervalField.text doubleValue] forKey:@"agent_min_request_interval"];
	[defaults synchronize];
    
	UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Saved" message:@"Settings updated." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
	[alert show];
}

- (void)dealloc {
	[_workspaceField release]; [_intervalField release];
	[super dealloc];
}
@end
