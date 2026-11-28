#import "AGInfoCell.h"

@interface AGInfoCell ()
@property (nonatomic, retain) UIButton *infoButton;
@end

@implementation AGInfoCell

@synthesize infoText = _infoText;
@synthesize infoButton = _infoButton;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		UIButton *button = [UIButton buttonWithType:UIButtonTypeInfoDark];
		button.frame = CGRectMake(0.0f, 0.0f, 32.0f, 32.0f);   // finger-sized tap area
		// The (i) sits in a slot before the title. Every row of this class keeps the slot,
		// with or without a button, so the titles of a section line up.
		self.indentationWidth = 28.0f;
		self.indentationLevel = 1;
		button.hidden = YES;
		[button addTarget:self action:@selector(infoTapped) forControlEvents:UIControlEventTouchUpInside];
		[self.contentView addSubview:button];
		self.infoButton = button;
	}
	return self;
}

- (void)setInfoText:(NSString *)infoText {
	if (infoText != _infoText) {
		[_infoText release];
		_infoText = [infoText copy];
	}
	self.infoButton.hidden = ([_infoText length] == 0);
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	// On iOS 6 the title label is opaque white and, in a plain cell, as wide as the whole
	// row, so it covers anything added to the cell before it. Make it see-through and put
	// our own views (the (i) button and any text field) on top.
	self.textLabel.backgroundColor = [UIColor clearColor];
	self.detailTextLabel.backgroundColor = [UIColor clearColor];
	for (UIView *view in [[self.contentView.subviews copy] autorelease]) {
		if (view == self.infoButton || [view isKindOfClass:[UITextField class]]) {
			[self.contentView bringSubviewToFront:view];
		}
	}

	if (self.infoButton.hidden) return;

	CGRect frame = self.infoButton.frame;
	frame.origin.x = 2.0f;
	frame.origin.y = floorf((self.contentView.bounds.size.height - frame.size.height) / 2.0f);
	self.infoButton.frame = frame;
}

- (void)infoTapped {
	[[[[UIAlertView alloc] initWithTitle:self.textLabel.text message:self.infoText delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
}

- (void)dealloc {
	[_infoText release];
	[_infoButton release];
	[super dealloc];
}

@end
