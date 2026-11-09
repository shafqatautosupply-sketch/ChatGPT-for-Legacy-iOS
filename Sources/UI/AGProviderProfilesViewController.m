#import "AGProviderProfilesViewController.h"
#import "AGProviderConfig.h"
#import "AGProviderProfileEditorViewController.h"

@interface AGProviderProfilesViewController ()

@property (nonatomic, retain) NSMutableArray *profiles;

@end

@implementation AGProviderProfilesViewController

@synthesize profiles = _profiles;

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Model Configurations";
		self.profiles = [NSMutableArray array];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		self.tableView.rowHeight = 56.0f;
	}
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTapped)] autorelease];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.profiles = [NSMutableArray arrayWithArray:[AGProviderConfig providerProfiles]];
	[self.tableView reloadData];
}

- (void)addTapped {
	AGProviderProfileEditorViewController *controller = [[[AGProviderProfileEditorViewController alloc] initForNewProfile] autorelease];
	[self.navigationController pushViewController:controller animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return MAX((NSInteger)[self.profiles count], 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return @"Tap a configuration row to make it active. Tap the disclosure button to edit an existing configuration.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"ProfileCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier] autorelease];
	}

	if ([self.profiles count] == 0) {
		cell.textLabel.text = @"No model configurations yet";
		cell.detailTextLabel.text = @"Tap + to add your first provider.";
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.imageView.image = nil;
		return cell;
	}

	NSDictionary *profile = [self.profiles objectAtIndex:indexPath.row];
	cell.textLabel.text = [profile objectForKey:@"providerName"];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@",
		([profile objectForKey:@"c-aiModel"] ?: @""),
		([profile objectForKey:@"baseURL"] ?: @"")];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
	cell.editingAccessoryType = UITableViewCellAccessoryDetailDisclosureButton;
	if ([[[profile objectForKey:@"identifier"] description] isEqualToString:[AGProviderConfig activeProviderProfileIdentifier]]) {
		cell.imageView.image = nil;
		cell.textLabel.text = [NSString stringWithFormat:@"✓ %@", [profile objectForKey:@"providerName"]];
	} else {
		cell.imageView.image = nil;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if ([self.profiles count] == 0) {
		return;
	}

	NSDictionary *profile = [self.profiles objectAtIndex:indexPath.row];
	[AGProviderConfig activateProviderProfileWithIdentifier:[profile objectForKey:@"identifier"]];
	self.profiles = [NSMutableArray arrayWithArray:[AGProviderConfig providerProfiles]];
	[self.tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return ([self.profiles count] > 0);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete || [self.profiles count] == 0) {
		return;
	}

	NSDictionary *profile = [self.profiles objectAtIndex:indexPath.row];
	[AGProviderConfig deleteProviderProfileWithIdentifier:[profile objectForKey:@"identifier"]];
	self.profiles = [NSMutableArray arrayWithArray:[AGProviderConfig providerProfiles]];
	[tableView reloadData];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
	if ([self.profiles count] == 0) {
		return;
	}

	NSDictionary *profile = [self.profiles objectAtIndex:indexPath.row];
	AGProviderProfileEditorViewController *controller = [[[AGProviderProfileEditorViewController alloc] initWithProfile:profile] autorelease];
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)dealloc {
	[_profiles release];
	[super dealloc];
}

@end
