#import "LCChatViewController.h"
#import "CGAPICommunicator.h"
#import "CGAPIHelper.h"
#import "CGConversation.h"
#import "CGMessage.h"
#import "LCConversationsViewController.h"
#include "LCConversationStore.h"
#import "LCSettingsViewController.h"
#import <QuartzCore/QuartzCore.h>

@interface LCChatViewController () <UITextViewDelegate, LCConversationsViewControllerDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, retain) UITextView *chatTextView;
@property (nonatomic, retain) UIToolbar *toolbar;
@property (nonatomic, retain) UITextField *inputField;
@property (nonatomic, retain) UIBarButtonItem *sendButton;
@property (nonatomic, retain) NSString *currentConversationIdentifier;
@property (nonatomic, retain) NSMutableAttributedString *fullChatAttributedString;
@property (nonatomic, assign) CGFloat keyboardOverlapHeight;
@property (nonatomic, assign) BOOL requestInFlight;
@property (nonatomic, assign) BOOL isFullScreenMode;
@property (nonatomic, retain) UITapGestureRecognizer *tapGesture;
@property (nonatomic, assign) NSInteger lastRenderedMessageCount;

@end

@implementation LCChatViewController

@synthesize chatTextView = _chatTextView;
@synthesize toolbar = _toolbar;
@synthesize inputField = _inputField;
@synthesize sendButton = _sendButton;
@synthesize messages = _messages;
@synthesize allMessages = _allMessages;
@synthesize currentConversationIdentifier = _currentConversationIdentifier;
@synthesize fullChatAttributedString = _fullChatAttributedString;
@synthesize keyboardOverlapHeight = _keyboardOverlapHeight;
@synthesize requestInFlight = _requestInFlight;
@synthesize isFullScreenMode = _isFullScreenMode;
@synthesize tapGesture = _tapGesture;
@synthesize lastRenderedMessageCount = _lastRenderedMessageCount;

- (id)init {
	self = [super init];
	if (self) {
		_messages = [[NSMutableArray alloc] init];
		_allMessages = [[NSMutableArray alloc] init];
		_fullChatAttributedString = [[NSMutableAttributedString alloc] init];
		_lastRenderedMessageCount = -1;
		self.title = [CGAPICommunicator isAgentModeEnabled] ? @"Agent" : @"Chat";
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
    BOOL isTerminal = [CGAPICommunicator isTerminalModeEnabled];
    BOOL isAgent = [CGAPICommunicator isAgentModeEnabled];
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

- (void)addNewMessageAndHandleTerminalUpdate:(CGMessage *)msg {
    [self.allMessages addObject:msg];
    
    NSInteger limit = [LCConversationStore loadedMessageLimit];
    if (limit > 0 && [self.allMessages count] > limit) {
        self.messages = [NSMutableArray arrayWithArray:[self.allMessages subarrayWithRange:NSMakeRange([self.allMessages count] - limit, limit)]];
        [self loadFullConversationIntoTerminal];
    } else {
        [self.messages addObject:msg];
        [self appendMessageToTerminal:msg];
    }
}

- (void)sendOrStopTapped {
    NSString *trimmedText = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
	if (self.requestInFlight) {
		[CGAPICommunicator performSelector:@selector(cancelCurrentAgentTask)];
		self.requestInFlight = NO;
		[self updateSendButtonTitle];
		return;
	}

	if ([trimmedText length] == 0) return;

    self.inputField.text = @"";
    [self.inputField resignFirstResponder]; 

	CGMessage *outgoingMessage = [[[CGMessage alloc] init] autorelease];
	outgoingMessage.role = @"user";
	outgoingMessage.content = trimmedText;
	
	[self addNewMessageAndHandleTerminalUpdate:outgoingMessage];
    
	[self persistCurrentConversation];

    self.requestInFlight = YES;
    [self updateSendButtonTitle];

	[CGAPICommunicator createChatCompletionWithMessages:self.allMessages];
}

- (void)appendMessageToTerminal:(CGMessage *)msg {
    BOOL isTerminal = [CGAPICommunicator isTerminalModeEnabled];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat startOfNewMessageY = self.chatTextView.contentSize.height;

        NSString *role = msg.role ?: @"user";
        NSString *content = [CGAPIHelper displayTextForMessage:msg];
        NSString *divider = @"==================================";
        
        NSMutableParagraphStyle *centerStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        centerStyle.alignment = NSTextAlignmentCenter;
        
        NSMutableParagraphStyle *leftStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        leftStyle.alignment = NSTextAlignmentLeft;

        NSMutableAttributedString *sectionAttrStr = [[[NSMutableAttributedString alloc] init] autorelease];

        if (isTerminal) {
            NSString *headerText = [role isEqualToString:@"user"] ? @"[USER >>]" : ([role isEqualToString:@"tool"] ? @"[TOOL OUTPUT >>]" : @"[AGENT >>]");
            NSString *headerBlock = [NSString stringWithFormat:@"%@\n%@\n%@\n", divider, headerText, divider];
            NSString *contentBlock = [NSString stringWithFormat:@"%@\n\n", content];
            
            UIFont *terminalFont = self.chatTextView.font ?: [UIFont fontWithName:@"Menlo" size:13.0f];
            if (!terminalFont) terminalFont = [UIFont fontWithName:@"Courier" size:13.0f];
            UIColor *terminalColor = [UIColor colorWithRed:0.15f green:0.95f blue:0.15f alpha:1.0f];
            
            NSDictionary *headerAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                terminalFont, NSFontAttributeName,
                terminalColor, NSForegroundColorAttributeName,
                centerStyle, NSParagraphStyleAttributeName,
                nil];
            NSDictionary *contentAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                terminalFont, NSFontAttributeName,
                terminalColor, NSForegroundColorAttributeName,
                leftStyle, NSParagraphStyleAttributeName,
                nil];
                
            NSAttributedString *headerAttrSub = [[[NSAttributedString alloc] initWithString:headerBlock attributes:headerAttrs] autorelease];
            NSAttributedString *contentAttrSub = [[[NSAttributedString alloc] initWithString:contentBlock attributes:contentAttrs] autorelease];
            
            [sectionAttrStr appendAttributedString:headerAttrSub];
            [sectionAttrStr appendAttributedString:contentAttrSub];
        } else {
            NSString *headerText = [role isEqualToString:@"user"] ? @"You" : ([role isEqualToString:@"tool"] ? @"Tool Output" : @"Assistant");
            NSString *headerBlock = [NSString stringWithFormat:@"%@\n%@\n%@\n", divider, headerText, divider];
            NSString *contentBlock = [NSString stringWithFormat:@"%@\n\n", content];
            
            UIFont *baseFont = [UIFont systemFontOfSize:14.0f];
            UIFont *headerFont = [UIFont boldSystemFontOfSize:14.0f];
            UIColor *textColor = [UIColor blackColor];
            UIColor *headerColor = [UIColor colorWithWhite:0.3f alpha:1.0f];
            
            NSDictionary *headerAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                headerFont, NSFontAttributeName,
                headerColor, NSForegroundColorAttributeName,
                centerStyle, NSParagraphStyleAttributeName,
                nil];
            NSDictionary *contentAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                baseFont, NSFontAttributeName,
                textColor, NSForegroundColorAttributeName,
                leftStyle, NSParagraphStyleAttributeName,
                nil];
                
            NSAttributedString *headerAttrSub = [[[NSAttributedString alloc] initWithString:headerBlock attributes:headerAttrs] autorelease];
            NSMutableAttributedString *contentAttrSub = [[[NSMutableAttributedString alloc] initWithString:contentBlock attributes:contentAttrs] autorelease];
            
            if ([CGAPIHelper respondsToSelector:@selector(applyMarkdownAttributesToAttributedString:)]) {
                [CGAPIHelper performSelector:@selector(applyMarkdownAttributesToAttributedString:) withObject:contentAttrSub];
            }
            
            [sectionAttrStr appendAttributedString:headerAttrSub];
            [sectionAttrStr appendAttributedString:contentAttrSub];
        }
        
        if (!self.fullChatAttributedString) {
            self.fullChatAttributedString = [[[NSMutableAttributedString alloc] init] autorelease];
        }
        
        // In-place mutation: only calculate and append the new message!
        [self.fullChatAttributedString appendAttributedString:sectionAttrStr];
        self.chatTextView.attributedText = self.fullChatAttributedString;
        
        // Leave half of previous distance (approx 11 points) between the top edge of screen and the separator bar
        CGPoint targetOffset = CGPointMake(0.0f, MAX(0.0f, startOfNewMessageY - 3.0f));
        [UIView animateWithDuration:0.25f animations:^{
            self.chatTextView.contentOffset = targetOffset;
        }];
    });
}

- (void)loadFullConversationIntoTerminal {
    BOOL isTerminal = [CGAPICommunicator isTerminalModeEnabled];
    NSArray *messagesSnapshot = [NSArray arrayWithArray:self.messages];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableAttributedString *fullLog = [[[NSMutableAttributedString alloc] init] autorelease];
        NSString *divider = @"==================================";
        
        NSMutableParagraphStyle *centerStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        centerStyle.alignment = NSTextAlignmentCenter;
        
        NSMutableParagraphStyle *leftStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        leftStyle.alignment = NSTextAlignmentLeft;

        if (isTerminal) {
            UIFont *terminalFont = [UIFont fontWithName:@"Menlo" size:13.0f];
            if (!terminalFont) terminalFont = [UIFont fontWithName:@"Courier" size:13.0f];
            if (!terminalFont) terminalFont = [UIFont boldSystemFontOfSize:13.0f];
            UIColor *terminalColor = [UIColor colorWithRed:0.15f green:0.95f blue:0.15f alpha:1.0f];
            
            NSDictionary *headerAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                terminalFont, NSFontAttributeName,
                terminalColor, NSForegroundColorAttributeName,
                centerStyle, NSParagraphStyleAttributeName,
                nil];
            NSDictionary *contentAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                terminalFont, NSFontAttributeName,
                terminalColor, NSForegroundColorAttributeName,
                leftStyle, NSParagraphStyleAttributeName,
                nil];

            for (CGMessage *msg in messagesSnapshot) {
                NSString *role = msg.role ?: @"user";
                NSString *content = [CGAPIHelper displayTextForMessage:msg];
                NSString *headerText = [role isEqualToString:@"user"] ? @"[USER >>]" : ([role isEqualToString:@"tool"] ? @"[TOOL OUTPUT >>]" : @"[AGENT >>]");
                NSString *headerBlock = [NSString stringWithFormat:@"%@\n%@\n%@\n", divider, headerText, divider];
                NSString *contentBlock = [NSString stringWithFormat:@"%@\n\n", content];
                
                NSAttributedString *headerAttrSub = [[[NSAttributedString alloc] initWithString:headerBlock attributes:headerAttrs] autorelease];
                NSAttributedString *contentAttrSub = [[[NSAttributedString alloc] initWithString:contentBlock attributes:contentAttrs] autorelease];
                
                [fullLog appendAttributedString:headerAttrSub];
                [fullLog appendAttributedString:contentAttrSub];
            }
        } else {
            UIFont *baseFont = [UIFont systemFontOfSize:14.0f];
            UIFont *headerFont = [UIFont boldSystemFontOfSize:14.0f];
            UIColor *textColor = [UIColor blackColor];
            UIColor *headerColor = [UIColor colorWithWhite:0.3f alpha:1.0f];
            
            NSDictionary *headerAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                headerFont, NSFontAttributeName,
                headerColor, NSForegroundColorAttributeName,
                centerStyle, NSParagraphStyleAttributeName,
                nil];
            NSDictionary *contentAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                baseFont, NSFontAttributeName,
                textColor, NSForegroundColorAttributeName,
                leftStyle, NSParagraphStyleAttributeName,
                nil];

            for (CGMessage *msg in messagesSnapshot) {
                NSString *role = msg.role ?: @"user";
                NSString *content = [CGAPIHelper displayTextForMessage:msg];
                NSString *headerText = [role isEqualToString:@"user"] ? @"You" : ([role isEqualToString:@"tool"] ? @"Tool Output" : @"Assistant");
                NSString *headerBlock = [NSString stringWithFormat:@"%@\n%@\n%@\n", divider, headerText, divider];
                NSString *contentBlock = [NSString stringWithFormat:@"%@\n\n", content];
                
                NSAttributedString *headerAttrSub = [[[NSAttributedString alloc] initWithString:headerBlock attributes:headerAttrs] autorelease];
                NSMutableAttributedString *contentAttrSub = [[[NSMutableAttributedString alloc] initWithString:contentBlock attributes:contentAttrs] autorelease];
                
                if ([CGAPIHelper respondsToSelector:@selector(applyMarkdownAttributesToAttributedString:)]) {
                    [CGAPIHelper performSelector:@selector(applyMarkdownAttributesToAttributedString:) withObject:contentAttrSub];
                }
                
                [fullLog appendAttributedString:headerAttrSub];
                [fullLog appendAttributedString:contentAttrSub];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fullChatAttributedString = fullLog;
            self.chatTextView.text = nil;
            self.chatTextView.attributedText = self.fullChatAttributedString;
            [self scrollToBottomAnimated:YES];
        });
    });
}

- (void)updateSendButtonTitle {
    self.sendButton.title = self.requestInFlight ? @"Stop" : @"Send";
}

- (void)viewDidLoad {
	[super viewDidLoad];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiResponseReceived:) name:LCAPIResponseNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiStatusDidChange:) name:LCAPIStatusDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(terminalModeChanged:) name:LCTerminalModeChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(agentModeChanged:) name:LCAgentModeChangedNotification object:nil];

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
    BOOL isTerminal = [CGAPICommunicator isTerminalModeEnabled];
    static BOOL lastTerminalState = NO;
    if (isTerminal != lastTerminalState) {
        lastTerminalState = isTerminal;
        [self loadFullConversationIntoTerminal];
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
    [self.messages removeAllObjects]; 
    [self.allMessages removeAllObjects]; 
    if (!self.fullChatAttributedString) {
        self.fullChatAttributedString = [[[NSMutableAttributedString alloc] init] autorelease];
    } else {
        [self.fullChatAttributedString replaceCharactersInRange:NSMakeRange(0, [self.fullChatAttributedString length]) withString:@""];
    }
    self.chatTextView.text = @"";
    self.chatTextView.attributedText = nil;
    self.lastRenderedMessageCount = -1; 
    self.currentConversationIdentifier = [LCConversationStore nextConversationIdentifier]; 
    [LCConversationStore setCurrentConversationIdentifier:nil]; 
}

- (void)persistCurrentConversation { 
    NSArray *messagesSnapshot = [[self.allMessages copy] autorelease];
    NSString *convID = [[self.currentConversationIdentifier copy] autorelease];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [LCConversationStore saveMessages:messagesSnapshot conversationID:convID title:nil];
    });
}

- (void)dismissKeyboard { [self.inputField resignFirstResponder]; }
- (void)handleViewTap:(UITapGestureRecognizer *)sender { [self dismissKeyboard]; }
- (void)showConversations { LCConversationsViewController *controller = [[[LCConversationsViewController alloc] init] autorelease]; controller.delegate = self; [self.navigationController pushViewController:controller animated:YES]; }
- (void)showSettings { LCSettingsViewController *controller = [[[LCSettingsViewController alloc] init] autorelease]; [self.navigationController pushViewController:controller animated:YES]; }
- (void)conversationsViewControllerDidRequestNewChat:(LCConversationsViewController *)controller { [self.navigationController popViewControllerAnimated:YES]; [self resetToNewConversation]; }

- (void)conversationsViewController:(LCConversationsViewController *)controller didSelectConversation:(CGConversation *)conversation {
	[self.navigationController popViewControllerAnimated:YES];
	if (!conversation) return;
	self.currentConversationIdentifier = conversation.uuid;
	[LCConversationStore setCurrentConversationIdentifier:conversation.uuid];
    
    [self.allMessages removeAllObjects]; 
    [self.allMessages addObjectsFromArray:conversation.messages];
    
    NSLog(@"[LCChat] Selected conversation uuid=%@ count=%d", conversation.uuid, [self.allMessages count]);
    
    NSInteger limit = [LCConversationStore loadedMessageLimit];
    if (limit > 0 && [self.allMessages count] > limit) {
        self.messages = [NSMutableArray arrayWithArray:[self.allMessages subarrayWithRange:NSMakeRange([self.allMessages count] - limit, limit)]];
    } else {
        self.messages = [NSMutableArray arrayWithArray:self.allMessages];
    }
    
	[self loadFullConversationIntoTerminal];
}

- (int)apiResponseReceived:(NSNotification *)notification {
	CGMessage *message = [notification object];
	if (![message isKindOfClass:[CGMessage class]]) return 0;
	
	NSLog(@"[LCChat] apiResponseReceived: role=%@ content=%@ token count=%ld", message.role, message.content, (long)[message.content length]);
	[self.allMessages addObject:message];
	
	NSInteger limit = [LCConversationStore loadedMessageLimit];
	if (limit > 0 && [self.allMessages count] > limit) {
		self.messages = [NSMutableArray arrayWithArray:[self.allMessages subarrayWithRange:NSMakeRange([self.allMessages count] - limit, limit)]];
		[self loadFullConversationIntoTerminal];
	} else {
		[self.messages addObject:message];
		[self appendMessageToTerminal:message];
	}
	
	[self persistCurrentConversation];
	return 0;
}

- (void)apiStatusDidChange:(NSNotification *)notification { 
    self.requestInFlight = [[notification object] boolValue];
    dispatch_async(dispatch_get_main_queue(), ^{ 
        [self updateSendButtonTitle];
    }); 
}

- (void)terminalModeChanged:(NSNotification *)notification { 
    self.lastRenderedMessageCount = -1;
    [self updateThemeStyling];
    [self loadFullConversationIntoTerminal]; 
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
	[_chatTextView release]; [_toolbar release]; [_inputField release]; [_sendButton release];[_messages release]; [_allMessages release]; [_currentConversationIdentifier release];
	[_fullChatAttributedString release];
	[_tapGesture release];
	[super dealloc];
}

@end
