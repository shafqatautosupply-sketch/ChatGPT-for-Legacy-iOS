#import "AGWebAccessViewController.h"
#import "AGWebAccess.h"
#import "AGWebPairing.h"
#import "AGInfoCell.h"

enum { AGSectionSwitch = 0, AGSectionAddress, AGSectionDevices, AGSectionCount };
static const NSInteger AGTagPortAlert = 1;
static const NSInteger AGTagDisconnectAllAlert = 2;

@interface AGWebAccessViewController ()
@property (nonatomic, retain) NSArray *devices;
@end

@implementation AGWebAccessViewController

@synthesize devices = _devices;

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) self.title = @"Web Access";
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) self.tableView.rowHeight = 56.0f;
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(refresh:) name:AGWebAccessChangedNotification object:nil];
	[center addObserver:self selector:@selector(refresh:) name:AGWebDevicesChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self refresh:nil];
}

- (void)refresh:(NSNotification *)note {
	self.devices = [[AGWebPairing sharedPairing] devices];
	[self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return AGSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == AGSectionSwitch) return 1;
	if (section == AGSectionAddress) {
		if (![AGWebAccess isEnabled]) return 0;
		NSInteger rows = (NSInteger)MAX([[AGWebAccess addressURLs] count], (NSUInteger)1) + 1;   // addresses (or "no network") + Port
		return rows;
	}
	return (NSInteger)[self.devices count] + ([self.devices count] > 0 ? 1 : 0);   // devices + "Disconnect all"
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == AGSectionAddress && [AGWebAccess isEnabled]) return @"Open this on the other device";
	if (section == AGSectionDevices) return @"Allowed devices";
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == AGSectionDevices && [self.devices count] == 0) return @"No device has been allowed yet.";
	return nil;
}

/// What the (i) on a row says (nil = no button).
- (NSString *)infoForRow:(NSIndexPath *)indexPath {
	if (indexPath.section == AGSectionSwitch) {
		return @"Shows a chat page that any browser on the same Wi-Fi can open (Android TV, tablet, laptop).\n\nA device must be allowed first: a message appears on this phone and nothing happens until you tap Allow. There is no password.\n\nQuestions about make, python and deleting files are asked on this phone, never on the web page.\n\nThe connection is plain HTTP, so only use it on a network you trust.";
	}
	if (indexPath.section == AGSectionAddress) {
		NSInteger addressRows = (NSInteger)MAX([[AGWebAccess addressURLs] count], (NSUInteger)1);
		if (indexPath.row >= addressRows) {
			return @"To keep the page answering while the app is not on screen, leave \"Keep running in background\" on (Agent Guardrails & Workspace). To see the Allow question over other apps, leave \"Ask over other apps\" on there too.";
		}
	}
	return nil;
}

- (UITableViewCell *)plainCell:(UITableView *)tableView style:(UITableViewCellStyle)style identifier:(NSString *)identifier {
	AGInfoCell *cell = (AGInfoCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil) cell = [[[AGInfoCell alloc] initWithStyle:style reuseIdentifier:identifier] autorelease];
	cell.infoText = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.accessoryView = nil;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.textColor = [UIColor blackColor];
	cell.textLabel.textAlignment = UITextAlignmentLeft;
	cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0f];
	cell.detailTextLabel.text = nil;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == AGSectionSwitch) {
		UITableViewCell *cell = [self plainCell:tableView style:UITableViewCellStyleSubtitle identifier:@"WebSwitch"];
		cell.textLabel.text = @"Web Access";
		((AGInfoCell *)cell).infoText = [self infoForRow:indexPath];
		UISwitch *toggle = [[[UISwitch alloc] initWithFrame:CGRectZero] autorelease];
		toggle.on = [AGWebAccess isEnabled];
		[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		NSString *error = [AGWebAccess lastError];
		cell.detailTextLabel.text = [AGWebAccess isRunning] ? @"On" : (error != nil ? error : @"Off");
		cell.detailTextLabel.textColor = (error != nil) ? [UIColor redColor] : [UIColor grayColor];
		cell.detailTextLabel.numberOfLines = 0;
		return cell;
	}

	if (indexPath.section == AGSectionAddress) {
		NSArray *urls = [AGWebAccess addressURLs];
		NSInteger addressRows = (NSInteger)MAX([urls count], (NSUInteger)1);
		if (indexPath.row < addressRows) {
			UITableViewCell *cell = [self plainCell:tableView style:UITableViewCellStyleDefault identifier:@"WebAddress"];
			cell.textLabel.font = [UIFont systemFontOfSize:16.0f];
			if ([urls count] == 0) {
				cell.textLabel.text = @"No Wi-Fi address (connect to a network)";
				cell.textLabel.textColor = [UIColor grayColor];
			} else {
				cell.textLabel.text = [urls objectAtIndex:(NSUInteger)indexPath.row];
				cell.selectionStyle = UITableViewCellSelectionStyleBlue;   // tap = copy
			}
			return cell;
		}
		UITableViewCell *cell = [self plainCell:tableView style:UITableViewCellStyleValue1 identifier:@"WebPort"];
		cell.textLabel.text = @"Port";
		((AGInfoCell *)cell).infoText = [self infoForRow:indexPath];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0f];
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[AGWebAccess port]];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	if ((NSUInteger)indexPath.row < [self.devices count]) {
		NSDictionary *device = [self.devices objectAtIndex:(NSUInteger)indexPath.row];
		UITableViewCell *cell = [self plainCell:tableView style:UITableViewCellStyleSubtitle identifier:@"WebDevice"];
		cell.textLabel.text = [device objectForKey:@"name"];
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - last used %@", [device objectForKey:@"address"], [self agoText:[[device objectForKey:@"lastSeen"] doubleValue]]];
		cell.detailTextLabel.textColor = [UIColor grayColor];
		return cell;
	}
	UITableViewCell *cell = [self plainCell:tableView style:UITableViewCellStyleDefault identifier:@"WebDisconnectAll"];
	cell.textLabel.text = @"Disconnect all devices";
	cell.textLabel.textColor = [UIColor redColor];
	cell.textLabel.textAlignment = UITextAlignmentCenter;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	return cell;
}

- (NSString *)agoText:(double)timestamp {
	double seconds = [[NSDate date] timeIntervalSince1970] - timestamp;
	if (seconds < 90) return @"just now";
	if (seconds < 3600) return [NSString stringWithFormat:@"%d min ago", (int)(seconds / 60)];
	if (seconds < 86400) return [NSString stringWithFormat:@"%d h ago", (int)(seconds / 3600)];
	return [NSString stringWithFormat:@"%d days ago", (int)(seconds / 86400)];
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch *)sender {
	[AGWebAccess setEnabled:sender.isOn];
	[self refresh:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == AGSectionAddress) {
		NSArray *urls = [AGWebAccess addressURLs];
		NSInteger addressRows = (NSInteger)MAX([urls count], (NSUInteger)1);
		if (indexPath.row < addressRows) {
			if ([urls count] > 0) {
				[UIPasteboard generalPasteboard].string = [urls objectAtIndex:(NSUInteger)indexPath.row];
				[[[[UIAlertView alloc] initWithTitle:@"Address copied" message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
			}
			return;
		}
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Port" message:@"A number from 1024 to 65535."
			delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Save", nil] autorelease];
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		alert.tag = AGTagPortAlert;
		UITextField *field = [alert textFieldAtIndex:0];
		field.keyboardType = UIKeyboardTypeNumberPad;
		field.text = [NSString stringWithFormat:@"%lu", (unsigned long)[AGWebAccess port]];
		[alert show];
		return;
	}

	if (indexPath.section == AGSectionDevices && (NSUInteger)indexPath.row >= [self.devices count] && [self.devices count] > 0) {
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Disconnect all devices?" message:@"Each one has to ask again and be allowed on this phone."
			delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Disconnect all", nil] autorelease];
		alert.tag = AGTagDisconnectAllAlert;
		[alert show];
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == AGSectionDevices && (NSUInteger)indexPath.row < [self.devices count];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self tableView:tableView canEditRowAtIndexPath:indexPath] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete || (NSUInteger)indexPath.row >= [self.devices count]) return;
	[[AGWebPairing sharedPairing] revokeDeviceWithID:[[self.devices objectAtIndex:(NSUInteger)indexPath.row] objectForKey:@"id"]];
	[self refresh:nil];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex) return;
	if (alertView.tag == AGTagDisconnectAllAlert) {
		[[AGWebPairing sharedPairing] revokeAllDevices];
		[self refresh:nil];
	} else if (alertView.tag == AGTagPortAlert) {
		NSInteger port = [[[alertView textFieldAtIndex:0] text] integerValue];
		if (port < 1024 || port > 65535 || ![AGWebAccess setPort:(NSUInteger)port]) {
			[[[[UIAlertView alloc] initWithTitle:@"Invalid port" message:@"Use a number from 1024 to 65535." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
		}
		[self refresh:nil];
	}
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_devices release];
	[super dealloc];
}

@end
