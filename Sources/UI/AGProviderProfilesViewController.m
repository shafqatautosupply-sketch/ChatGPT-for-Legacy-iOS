#import "AGProviderProfilesViewController.h"
#import "AGProviderConfig.h"
#import "AGProviderProfileEditorViewController.h"

enum { AGSectionGemini = 0, AGSectionOpenAI = 1 };

@interface AGProviderProfilesViewController ()

@property (nonatomic, retain) NSArray *geminiProfiles;
@property (nonatomic, retain) NSArray *openAIProfiles;

@end

@implementation AGProviderProfilesViewController

@synthesize geminiProfiles = _geminiProfiles;
@synthesize openAIProfiles = _openAIProfiles;

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Model Configurations";
		self.geminiProfiles = [NSArray array];
		self.openAIProfiles = [NSArray array];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
		self.tableView.rowHeight = 56.0f;
	}
}

- (void)reloadProfiles {
	self.geminiProfiles = [AGProviderConfig providerProfilesOfType:AGProviderTypeGemini];
	self.openAIProfiles = [AGProviderConfig providerProfilesOfType:AGProviderTypeOpenAI];
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadProfiles];
}

- (NSArray *)profilesForSection:(NSInteger)section {
	return (section == AGSectionGemini) ? self.geminiProfiles : self.openAIProfiles;
}

- (NSString *)typeForSection:(NSInteger)section {
	return (section == AGSectionGemini) ? AGProviderTypeGemini : AGProviderTypeOpenAI;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return (section == AGSectionGemini) ? @"Google Gemini" : @"OpenAI Compatible";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == AGSectionGemini) {
		return @"Tap a configuration to make it active (✓). Tap ⓘ to edit, swipe to delete.";
	}
	return @"Any server that speaks the OpenAI Chat Completions API: OpenAI, OpenRouter, DeepSeek, Groq, LM Studio, Ollama and others. Base URL example: https://api.openai.com/v1. The key is sent as a Bearer token.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[[self profilesForSection:section] count] + 1; // + the "Add" row
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *profiles = [self profilesForSection:indexPath.section];
	BOOL isAddRow = (indexPath.row >= (NSInteger)[profiles count]);

	NSString *identifier = isAddRow ? @"AddCell" : @"ProfileCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:(isAddRow ? UITableViewCellStyleDefault : UITableViewCellStyleSubtitle) reuseIdentifier:identifier] autorelease];
	}

	if (isAddRow) {
		cell.textLabel.text = (indexPath.section == AGSectionGemini) ? @"Add Google Gemini…" : @"Add OpenAI Compatible…";
		cell.textLabel.textColor = [UIColor colorWithRed:0.0f green:0.35f blue:0.8f alpha:1.0f];
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		return cell;
	}

	NSDictionary *profile = [profiles objectAtIndex:(NSUInteger)indexPath.row];
	BOOL isActive = [[[profile objectForKey:@"identifier"] description] isEqualToString:[AGProviderConfig activeProviderProfileIdentifier]];
	NSString *name = [profile objectForKey:@"providerName"] ?: @"";
	cell.textLabel.text = isActive ? [NSString stringWithFormat:@"✓ %@", name] : name;
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@", ([profile objectForKey:@"c-aiModel"] ?: @""), ([profile objectForKey:@"baseURL"] ?: @"")];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
	cell.editingAccessoryType = UITableViewCellAccessoryDetailDisclosureButton;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSArray *profiles = [self profilesForSection:indexPath.section];

	if (indexPath.row >= (NSInteger)[profiles count]) {
		AGProviderProfileEditorViewController *controller = [[[AGProviderProfileEditorViewController alloc] initForNewProfileOfType:[self typeForSection:indexPath.section]] autorelease];
		[self.navigationController pushViewController:controller animated:YES];
		return;
	}

	NSDictionary *profile = [profiles objectAtIndex:(NSUInteger)indexPath.row];
	[AGProviderConfig activateProviderProfileWithIdentifier:[profile objectForKey:@"identifier"]];
	[self reloadProfiles];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.row < (NSInteger)[[self profilesForSection:indexPath.section] count];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *profiles = [self profilesForSection:indexPath.section];
	if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row >= (NSInteger)[profiles count]) return;

	NSDictionary *profile = [profiles objectAtIndex:(NSUInteger)indexPath.row];
	[AGProviderConfig deleteProviderProfileWithIdentifier:[profile objectForKey:@"identifier"]];
	[self reloadProfiles];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
	NSArray *profiles = [self profilesForSection:indexPath.section];
	if (indexPath.row >= (NSInteger)[profiles count]) return;

	NSDictionary *profile = [profiles objectAtIndex:(NSUInteger)indexPath.row];
	AGProviderProfileEditorViewController *controller = [[[AGProviderProfileEditorViewController alloc] initWithProfile:profile] autorelease];
	[self.navigationController pushViewController:controller animated:YES];
}

- (void)dealloc {
	[_geminiProfiles release];
	[_openAIProfiles release];
	[super dealloc];
}

@end
