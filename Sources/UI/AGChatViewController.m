#import "AGChatViewController.h"
#import "AGGeminiClient.h"
#import "AGProviderConfig.h"
#import "AGConversation.h"
#import "AGMessage.h"
#import "AGMessageRenderer.h"
#import "AGConversationsViewController.h"
#import "AGConversationStore.h"
#import "AGSettingsViewController.h"
#import <QuartzCore/QuartzCore.h>

// UITextView on iOS 6 insets its text by 8pt on each side.
static const CGFloat AGTextViewHorizontalPadding = 16.0f;
static const CGFloat AGTextViewTopPadding = 8.0f;

@interface AGChatViewController () <UITextViewDelegate, AGConversationsViewControllerDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, retain) UITextView *chatTextView;
@property (nonatomic, retain) UIToolbar *toolbar;
@property (nonatomic, retain) UITextField *inputField;
@property (nonatomic, retain) UIBarButtonItem *sendButton;
@property (nonatomic, retain) NSString *currentConversationIdentifier;
@property (nonatomic, retain) NSMutableAttributedString *fullChatAttributedString;
/// One entry per displayed message, in step with `messages`: character length and
/// laid-out height of its segment. They let us append, trim the oldest message and
/// find "where does the newest message start" without re-measuring the whole log.
@property (nonatomic, retain) NSMutableArray *segmentLengths;
@property (nonatomic, retain) NSMutableArray *segmentHeights;
@property (nonatomic, assign) double totalHeight;
@property (nonatomic, assign) NSUInteger rebuildGeneration;
@property (nonatomic, assign) CGFloat keyboardOverlapHeight;
@property (nonatomic, assign) BOOL requestInFlight;
@property (nonatomic, assign) BOOL isFullScreenMode;
@property (nonatomic, assign) BOOL lastTerminalState;
@property (nonatomic, assign) BOOL lastMarkdownState;
@property (nonatomic, assign) NSInteger lastLimit;
@property (nonatomic, retain) UITapGestureRecognizer *tapGesture;

@end

@implementation AGChatViewController

@synthesize chatTextView = _chatTextView;
@synthesize toolbar = _toolbar;
@synthesize inputField = _inputField;
@synthesize sendButton = _sendButton;
@synthesize messages = _messages;
@synthesize allMessages = _allMessages;
@synthesize currentConversationIdentifier = _currentConversationIdentifier;
@synthesize fullChatAttributedString = _fullChatAttributedString;
@synthesize segmentLengths = _segmentLengths;
@synthesize segmentHeights = _segmentHeights;
@synthesize totalHeight = _totalHeight;
@synthesize rebuildGeneration = _rebuildGeneration;
@synthesize keyboardOverlapHeight = _keyboardOverlapHeight;
@synthesize requestInFlight = _requestInFlight;
@synthesize isFullScreenMode = _isFullScreenMode;
@synthesize lastTerminalState = _lastTerminalState;
@synthesize lastMarkdownState = _lastMarkdownState;
@synthesize lastLimit = _lastLimit;
@synthesize tapGesture = _tapGesture;

- (id)init {
	self = [super init];
	if (self) {
		_messages = [[NSMutableArray alloc] init];
		_allMessages = [[NSMutableArray alloc] init];
		_fullChatAttributedString = [[NSMutableAttributedString alloc] init];
		_segmentLengths = [[NSMutableArray alloc] init];
		_segmentHeights = [[NSMutableArray alloc] init];
		_lastLimit = -1;
		self.title = [AGGeminiClient isAgentModeEnabled] ? @"Agent" : @"Chat";
	}
	return self;
}

- (void)loadView {
	[super loadView];
	
	self.view = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
	[self updateThemeStyling];

	UITextView *chatTextView = [[[UITextView alloc] initWithFrame:CGRectZero] autorelease];
	chatTextView.editable = NO;
	chatTextView.alwaysBounceVertical = YES;
	self.chatTextView = chatTextView;
	[self.view addSubview:self.chatTextView];

	UIToolbar *toolbar = [[[UIToolbar alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - 44, self.view.frame.size.width, 44)] autorelease];
	toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	toolbar.barStyle = UIBarStyleDefault;
    toolbar.translucent = NO;
	self.toolbar = toolbar;
	[self.view addSubview:self.toolbar];

	UITextField *inputField = [[[UITextField alloc] initWithFrame:CGRectMake(0, 0, 248, 30)] autorelease];
	inputField.borderStyle = UITextBorderStyleRoundedRect;
	inputField.font = [UIFont systemFontOfSize:15.0f];
	inputField.placeholder = @"";
    inputField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	self.inputField = inputField;
    
    UIBarButtonItem *leftSpace = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil] autorelease];
    leftSpace.width = -4.0;
    
	UIBarButtonItem *inputItem = [[[UIBarButtonItem alloc] initWithCustomView:inputField] autorelease];
    
    UIBarButtonItem *spacer = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease];
    
	self.sendButton = [[[UIBarButtonItem alloc] initWithTitle:@"Send" 
                                                       style:UIBarButtonItemStyleBordered 
                                                      target:self 
                                                      action:@selector(sendOrStopTapped)] autorelease];
    
	self.toolbar.items = [NSArray arrayWithObjects:leftSpace, inputItem, spacer, self.sendButton, nil];
    
    UILongPressGestureRecognizer *longPress = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleFullscreenGesture:)] autorelease];
    longPress.minimumPressDuration = 0.5;
    [self.toolbar addGestureRecognizer:longPress];

    [self updateThemeStyling];
}

- (void)updateThemeStyling {
    BOOL isTerminal = [AGGeminiClient isTerminalModeEnabled];
    BOOL isAgent = [AGGeminiClient isAgentModeEnabled];
    self.title = isAgent ? @"Agent" : @"Chat";

    if (isTerminal) {
        self.view.backgroundColor = [UIColor blackColor];
        if (self.chatTextView) {
            self.chatTextView.backgroundColor = [UIColor blackColor];
            self.chatTextView.textColor = [UIColor colorWithRed:0.15f green:0.95f blue:0.15f alpha:1.0f];
            UIFont *terminalFont = [UIFont fontWithName:@"Menlo" size:13.0f];
            if (!terminalFont) terminalFont = [UIFont fontWithName:@"Courier" size:13.0f];
            if (!terminalFont) terminalFont = [UIFont boldSystemFontOfSize:13.0f];
            self.chatTextView.font = terminalFont;
        }
        if (self.toolbar) {
            self.toolbar.barStyle = UIBarStyleDefault;
        }
        if (self.inputField) {
            self.inputField.backgroundColor = [UIColor whiteColor];
            self.inputField.textColor = [UIColor blackColor];
        }
    } else {
        self.view.backgroundColor = [UIColor colorWithRed:220/255.0 green:230/255.0 blue:240/255.0 alpha:1.0];
        if (self.chatTextView) {
            self.chatTextView.backgroundColor = [UIColor colorWithRed:220/255.0 green:230/255.0 blue:240/255.0 alpha:1.0];
            self.chatTextView.textColor = [UIColor blackColor];
            self.chatTextView.font = [UIFont systemFontOfSize:14.0f];
        }
        if (self.toolbar) {
            self.toolbar.barStyle = UIBarStyleDefault;
        }
        if (self.inputField) {
            self.inputField.backgroundColor = [UIColor whiteColor];
            self.inputField.textColor = [UIColor blackColor];
        }
    }
}

- (void)handleFullscreenGesture:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.isFullScreenMode = !self.isFullScreenMode;
        [[UIApplication sharedApplication] setStatusBarHidden:self.isFullScreenMode withAnimation:UIStatusBarAnimationSlide];
        [self.navigationController setNavigationBarHidden:self.isFullScreenMode animated:YES];
    }
}

#pragma mark - Rendering

- (CGFloat)textWidth {
    CGFloat width = self.chatTextView.bounds.size.width;
    if (width <= 0) width = [UIScreen mainScreen].bounds.size.width;
    return width - AGTextViewHorizontalPadding;
}

/// Scrolls so the START of the newest message is at the top (reads naturally for
/// long answers), without ever scrolling past the end of the content.
- (void)scrollToOffsetY:(double)startY animated:(BOOL)animated {
    [self.chatTextView setNeedsLayout];
    [self.chatTextView layoutIfNeeded];
    CGFloat maxOffset = MAX(0.0f, self.chatTextView.contentSize.height - self.chatTextView.bounds.size.height + self.chatTextView.contentInset.bottom);
    CGFloat target = (CGFloat)MIN(MAX(0.0, startY + AGTextViewTopPadding - 4.0), (double)maxOffset);
    CGPoint offset = CGPointMake(0.0f, target);
    if (animated) [UIView animateWithDuration:0.25f animations:^{ self.chatTextView.contentOffset = offset; }];
    else self.chatTextView.contentOffset = offset;
}

/// Adds a message to the transcript and to the screen. O(size of this message):
/// the old code copied the whole log and re-measured all of it for every message.
- (void)addMessage:(AGMessage *)message {
    [self.allMessages addObject:message];
    [self.messages addObject:message];
    [self appendSegmentForMessage:message];
}

- (void)appendSegmentForMessage:(AGMessage *)message {
    BOOL terminal = [AGGeminiClient isTerminalModeEnabled];
    BOOL markdown = [AGGeminiClient isMarkdownEnabled];
    NSAttributedString *segment = [AGMessageRenderer segmentForMessage:message terminal:terminal markdown:markdown];
    double height = [AGMessageRenderer heightForMessage:message segment:segment width:[self textWidth]];

    double startY = self.totalHeight;
    [self.fullChatAttributedString appendAttributedString:segment];
    [self.segmentLengths addObject:[NSNumber numberWithUnsignedInteger:[segment length]]];
    [self.segmentHeights addObject:[NSNumber numberWithDouble:height]];
    self.totalHeight += height;

    // Keep only the newest `limit` messages on screen: drop the oldest segment in place.
    NSInteger limit = [AGConversationStore loadedMessageLimit];
    while (limit > 0 && (NSInteger)[self.messages count] > limit) {
        [self.messages removeObjectAtIndex:0];
        NSUInteger dropLength = [[self.segmentLengths objectAtIndex:0] unsignedIntegerValue];
        double dropHeight = [[self.segmentHeights objectAtIndex:0] doubleValue];
        [self.fullChatAttributedString deleteCharactersInRange:NSMakeRange(0, dropLength)];
        [self.segmentLengths removeObjectAtIndex:0];
        [self.segmentHeights removeObjectAtIndex:0];
        self.totalHeight -= dropHeight;
        startY -= dropHeight;
    }

    self.chatTextView.attributedText = self.fullChatAttributedString;
    [self scrollToOffsetY:startY animated:YES];
}

/// Rebuilds the screen from `allMessages` (chat loaded, theme/markdown/limit changed).
/// Segment rendering is warmed on a background thread; assembly happens on the main
/// thread from the CURRENT window, and only the newest rebuild is applied, so
/// quick successive changes can no longer show stale content.
- (void)rebuildLog {
    NSInteger limit = [AGConversationStore loadedMessageLimit];
    NSUInteger total = [self.allMessages count];
    NSArray *window = (limit > 0 && (NSInteger)total > limit)
        ? [self.allMessages subarrayWithRange:NSMakeRange(total - (NSUInteger)limit, (NSUInteger)limit)]
        : [NSArray arrayWithArray:self.allMessages];
    self.messages = [NSMutableArray arrayWithArray:window];

    BOOL terminal = [AGGeminiClient isTerminalModeEnabled];
    BOOL markdown = [AGGeminiClient isMarkdownEnabled];
    NSUInteger generation = ++self.rebuildGeneration;
    NSArray *snapshot = window;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (AGMessage *message in snapshot) [AGMessageRenderer segmentForMessage:message terminal:terminal markdown:markdown];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.rebuildGeneration) return; // a newer rebuild superseded this one

            NSMutableAttributedString *log = [[[NSMutableAttributedString alloc] init] autorelease];
            [self.segmentLengths removeAllObjects];
            [self.segmentHeights removeAllObjects];
            double total = 0, lastHeight = 0;
            CGFloat width = [self textWidth];
            for (AGMessage *message in self.messages) {
                NSAttributedString *segment = [AGMessageRenderer segmentForMessage:message terminal:terminal markdown:markdown];
                double height = [AGMessageRenderer heightForMessage:message segment:segment width:width];
                [log appendAttributedString:segment];
                [self.segmentLengths addObject:[NSNumber numberWithUnsignedInteger:[segment length]]];
                [self.segmentHeights addObject:[NSNumber numberWithDouble:height]];
                total += height; lastHeight = height;
            }
            self.fullChatAttributedString = log;
            self.totalHeight = total;
            self.chatTextView.text = nil;
            self.chatTextView.attributedText = log;

            if ([self.messages count] > 0) [self scrollToOffsetY:(total - lastHeight) animated:NO];
        });
    });
}

- (void)sendOrStopTapped {
    NSString *trimmedText = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (self.requestInFlight) {
        [AGGeminiClient cancelCurrentAgentTask];
        self.requestInFlight = NO;
        [self updateSendButtonTitle];
        return;
    }

    if ([trimmedText length] == 0) return;

    self.inputField.text = @"";
    [self dismissKeyboard];

    AGMessage *outgoing = [AGMessage messageWithRole:@"user" content:trimmedText];
    [self addMessage:outgoing];
    [self persistCurrentConversation];

    self.requestInFlight = YES;
    [self updateSendButtonTitle];
    [AGGeminiClient createChatCompletionWithMessages:self.allMessages];
}

- (void)updateSendButtonTitle {
    self.sendButton.title = self.requestInFlight ? @"Stop" : @"Send";
}

- (void)viewDidLoad {
	[super viewDidLoad];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiResponseReceived:) name:AGAPIResponseNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiStatusDidChange:) name:AGAPIStatusDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(terminalModeChanged:) name:AGTerminalModeChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(agentModeChanged:) name:AGAgentModeChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(markdownModeChanged:) name:AGMarkdownModeChangedNotification object:nil];

	self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Chats" style:UIBarButtonItemStyleBordered target:self action:@selector(showConversations)] autorelease];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Settings" style:UIBarButtonItemStyleBordered target:self action:@selector(showSettings)] autorelease];

	self.tapGesture = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleViewTap:)] autorelease];
	self.tapGesture.cancelsTouchesInView = NO;
    self.tapGesture.delegate = self;
	[self.view addGestureRecognizer:self.tapGesture];

	[self resetToNewConversation];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.tapGesture) {
        CGPoint location = [touch locationInView:self.view];
        if (CGRectContainsPoint(self.toolbar.frame, location)) return NO;
    }
    return YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateThemeStyling];

    BOOL terminal = [AGGeminiClient isTerminalModeEnabled];
    BOOL markdown = [AGGeminiClient isMarkdownEnabled];
    NSInteger limit = [AGConversationStore loadedMessageLimit];
    if (self.lastLimit == -1) { self.lastLimit = limit; self.lastTerminalState = terminal; self.lastMarkdownState = markdown; }

    // Rebuild only if a setting that changes the rendering actually changed.
    if (terminal != self.lastTerminalState || markdown != self.lastMarkdownState || limit != self.lastLimit) {
        self.lastTerminalState = terminal;
        self.lastMarkdownState = markdown;
        self.lastLimit = limit;
        if ([self.allMessages count] > 0) [self rebuildLog];
    }
}

- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self layoutForCurrentBounds]; }

- (void)layoutForCurrentBounds {
    CGRect bounds = self.view.bounds;
    CGFloat toolbarHeight = 44.0f;
    CGFloat bottomInset = self.keyboardOverlapHeight;
    
    self.toolbar.frame = CGRectMake(0.0f, bounds.size.height - bottomInset - toolbarHeight, bounds.size.width, toolbarHeight);
    self.chatTextView.frame = CGRectMake(0.0f, 0.0f, bounds.size.width, bounds.size.height - toolbarHeight - bottomInset);
    
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0f, 0.0f, toolbarHeight, 0.0f);
    self.chatTextView.contentInset = contentInsets;
    self.chatTextView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    CGFloat contentHeight = self.chatTextView.contentSize.height;
    CGFloat visibleHeight = self.chatTextView.bounds.size.height;
    if (contentHeight > visibleHeight) {
        CGPoint bottomOffset = CGPointMake(0.0f, contentHeight - visibleHeight + 44.0f);
        if (animated) [UIView animateWithDuration:0.25f animations:^{ self.chatTextView.contentOffset = bottomOffset; }];
        else self.chatTextView.contentOffset = bottomOffset;
    }
}

- (void)resetToNewConversation {
    [self stopRunningRequest];
    [self.messages removeAllObjects];
    [self.allMessages removeAllObjects];
    [self.segmentLengths removeAllObjects];
    [self.segmentHeights removeAllObjects];
    self.totalHeight = 0;
    self.rebuildGeneration++;
    [self.fullChatAttributedString replaceCharactersInRange:NSMakeRange(0, [self.fullChatAttributedString length]) withString:@""];
    self.chatTextView.text = @"";
    self.chatTextView.attributedText = nil;
    self.currentConversationIdentifier = [AGConversationStore nextConversationIdentifier];
    [AGConversationStore setCurrentConversationIdentifier:nil];
}

/// Switching or clearing a chat must stop the agent: its replies would otherwise
/// be appended to whichever chat is on screen when they arrive.
- (void)stopRunningRequest {
    [AGGeminiClient cancelCurrentAgentTask];
    self.requestInFlight = NO;
    [self updateSendButtonTitle];
}

- (void)persistCurrentConversation {
    // The snapshot is taken here (main thread); the store writes it on its own serial queue.
    [AGConversationStore saveMessagesAsync:self.allMessages conversationID:self.currentConversationIdentifier title:nil];
}

- (void)dismissKeyboard { [self.inputField resignFirstResponder]; }
- (void)handleViewTap:(UITapGestureRecognizer *)sender { [self dismissKeyboard]; }
- (void)showConversations { AGConversationsViewController *controller = [[[AGConversationsViewController alloc] init] autorelease]; controller.delegate = self; [self.navigationController pushViewController:controller animated:YES]; }
- (void)showSettings { AGSettingsViewController *controller = [[[AGSettingsViewController alloc] init] autorelease]; [self.navigationController pushViewController:controller animated:YES]; }
- (void)conversationsViewControllerDidRequestNewChat:(AGConversationsViewController *)controller { [self.navigationController popViewControllerAnimated:YES]; [self resetToNewConversation]; }

- (void)conversationsViewController:(AGConversationsViewController *)controller didSelectConversation:(AGConversation *)conversation {
    [self.navigationController popViewControllerAnimated:YES];
    if (conversation == nil) return;
    [self stopRunningRequest];

    // The Chats list only carries metadata; load the real transcript now.
    AGConversation *full = [AGConversationStore conversationWithIdentifier:conversation.uuid];
    if (full == nil) return;

    self.currentConversationIdentifier = full.uuid;
    [AGConversationStore setCurrentConversationIdentifier:full.uuid];
    [self.allMessages removeAllObjects];
    [self.allMessages addObjectsFromArray:full.messages];
    [self rebuildLog];
}

- (void)apiResponseReceived:(NSNotification *)notification {
    AGMessage *message = [notification object];
    if (![message isKindOfClass:[AGMessage class]]) return;
    // Ignore output of a run that was stopped or replaced (e.g. the user switched chats).
    NSNumber *run = [[notification userInfo] objectForKey:AGAPIRunUserInfoKey];
    if (run != nil && [run unsignedIntegerValue] != [AGGeminiClient currentRunID]) return;

    [self addMessage:message];
    [self persistCurrentConversation];
}

- (void)apiStatusDidChange:(NSNotification *)notification {
    NSNumber *run = [[notification userInfo] objectForKey:AGAPIRunUserInfoKey];
    if (run != nil && [run unsignedIntegerValue] != [AGGeminiClient currentRunID]) return;
    self.requestInFlight = [[notification object] boolValue];
    [self updateSendButtonTitle];
}

- (void)terminalModeChanged:(NSNotification *)notification {
    [self updateThemeStyling];
    self.lastTerminalState = [AGGeminiClient isTerminalModeEnabled];
    if ([self.allMessages count] > 0) [self rebuildLog];
}

- (void)markdownModeChanged:(NSNotification *)notification {
    self.lastMarkdownState = [AGGeminiClient isMarkdownEnabled];
    if ([self.allMessages count] > 0) [self rebuildLog];
}

- (void)agentModeChanged:(NSNotification *)notification {
    [self updateThemeStyling];
}

- (void)keyboardWillShow:(NSNotification *)notification {
	CGRect keyboardFrame = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	id durationObj = [[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey];
	NSTimeInterval duration = [durationObj respondsToSelector:@selector(doubleValue)] ? [durationObj doubleValue] : 0.25;
	self.keyboardOverlapHeight = self.view.bounds.size.height - [self.view convertRect:keyboardFrame fromView:nil].origin.y;
	[UIView animateWithDuration:duration animations:^{ 
        [self layoutForCurrentBounds]; 
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
	id durationObj = [[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey];
	NSTimeInterval duration = [durationObj respondsToSelector:@selector(doubleValue)] ? [durationObj doubleValue] : 0.25;
	[UIView animateWithDuration:duration animations:^{ self.keyboardOverlapHeight = 0.0f; [self layoutForCurrentBounds]; }];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_chatTextView release]; [_toolbar release]; [_inputField release]; [_sendButton release]; [_messages release]; [_allMessages release]; [_currentConversationIdentifier release];
	[_fullChatAttributedString release];
	[_segmentLengths release]; [_segmentHeights release];
	[_tapGesture release];
	[super dealloc];
}

@end
