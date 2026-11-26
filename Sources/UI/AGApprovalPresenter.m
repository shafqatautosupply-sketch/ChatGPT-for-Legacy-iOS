#import "AGApprovalPresenter.h"
#import "AGApproval.h"
#import "AGChatClient.h"
#import "AGBackgroundKeeper.h"
#import "AGMessage.h"
#import "AGWebPairing.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>

// --- System dialog (CFUserNotification) ---------------------------------------------------
// Looked up at run time so the build does not depend on the SDK exposing the header, and so a
// missing symbol just means "no system dialog" instead of a crash at launch.
typedef void *(*AGNoteCreateFn)(CFAllocatorRef, CFTimeInterval, CFOptionFlags, SInt32 *, CFDictionaryRef);
typedef SInt32 (*AGNoteReceiveFn)(void *, CFTimeInterval, CFOptionFlags *);
typedef SInt32 (*AGNoteCancelFn)(void *);
static AGNoteCreateFn g_noteCreate = NULL;
static AGNoteReceiveFn g_noteReceive = NULL;
static AGNoteCancelFn g_noteCancel = NULL;

static BOOL AGSystemDialogsResolved(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		g_noteCreate = (AGNoteCreateFn)dlsym(RTLD_DEFAULT, "CFUserNotificationCreate");
		g_noteReceive = (AGNoteReceiveFn)dlsym(RTLD_DEFAULT, "CFUserNotificationReceiveResponse");
		g_noteCancel = (AGNoteCancelFn)dlsym(RTLD_DEFAULT, "CFUserNotificationCancel");
	});
	return g_noteCreate != NULL && g_noteReceive != NULL && g_noteCancel != NULL;
}

static AGApprovalPresenter *g_presenter = nil;   // set by +install; lives for the whole process

static const int AGMaxSystemDialogAttempts = 3;   // if iOS dismisses it early (lock/unlock), ask again this often

@interface AGApprovalPresenter () <UIAlertViewDelegate> {
	void *_systemNote;               // the CFUserNotificationRef being shown, or NULL
	BOOL _systemNoteCancelledByUs;
	NSTimeInterval _systemNoteShownAt;
}
@property (nonatomic, retain) NSMutableArray *queue;        // of NSMutableDictionary prompts, main thread only
@property (nonatomic, retain) UIAlertView *current;
@property (nonatomic, copy) NSString *lastAssistantText;
@end

@implementation AGApprovalPresenter

@synthesize queue = _queue;
@synthesize current = _current;
@synthesize lastAssistantText = _lastAssistantText;

+ (BOOL)globalDialogsEnabled {
	id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"agent_global_prompts"];
	return (value != nil && [value respondsToSelector:@selector(boolValue)]) ? [value boolValue] : YES;
}

+ (void)install {
	if (g_presenter != nil) return;
	g_presenter = [[AGApprovalPresenter alloc] init];   // lives for the whole process
	[g_presenter start];

	// Web access: "Allow web access?" is asked here, on the phone, never on the web page.
	[[AGWebPairing sharedPairing] setAsk:^id(NSString *title, NSString *detail, NSTimeInterval timeout, void (^answer)(AGPairAnswer)) {
		return [AGApprovalPresenter askQuestionWithTitle:title detail:detail allowTitle:@"Allow" timeout:timeout answer:^(NSInteger result) { answer((AGPairAnswer)result); }];
	} cancel:^(id handle) {
		[AGApprovalPresenter cancelQuestion:handle];
	}];
}

- (void)start {
	self.queue = [NSMutableArray array];
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(appBecameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
	[center addObserver:self selector:@selector(promptAbandoned:) name:AGApprovalAbandonedNotification object:nil];
	[center addObserver:self selector:@selector(statusChanged:) name:AGAPIStatusDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(responseArrived:) name:AGAPIResponseNotification object:nil];

	AGApprovalPresenter *me = self;
	[AGApproval setHandler:^(NSString *title, NSString *detail, NSString *taskLabel, AGApprovalResponder respond) {
		// Runs on the agent's worker thread: hand over to the main thread.
		NSMutableDictionary *prompt = [NSMutableDictionary dictionaryWithObjectsAndKeys:
			title ?: @"", @"title", detail ?: @"", @"detail",
			taskLabel ?: (id)[NSNull null], @"label",
			[[respond copy] autorelease], @"respond", nil];
		dispatch_async(dispatch_get_main_queue(), ^{
			[me.queue addObject:prompt];
			[me pump];
		});
	}];
}

#pragma mark - Showing prompts

- (void)pump {
	if (self.current != nil || _systemNote != NULL || [self.queue count] == 0) return;
	NSMutableDictionary *prompt = [self.queue objectAtIndex:0];

	if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
		// Not visible: first choice is the system dialog, which can be answered right where the person is.
		if ([self presentSystemDialogForPrompt:prompt]) return;
		// Fallback: tell them once; the alert appears when they open the app.
		if (![[prompt objectForKey:@"notified"] boolValue]) {
			[prompt setObject:[NSNumber numberWithBool:YES] forKey:@"notified"];
			NSString *firstLine = [[[prompt objectForKey:@"detail"] componentsSeparatedByString:@"\n"] objectAtIndex:0];
			[self postLocalNotification:[NSString stringWithFormat:@"%@ - tap to review. %@", [prompt objectForKey:@"title"], firstLine]];
		}
		return;
	}

	NSString *label = [prompt objectForKey:@"label"];
	if (![label isKindOfClass:[NSString class]]) label = nil;
	UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:[prompt objectForKey:@"title"] message:[prompt objectForKey:@"detail"]
		delegate:self cancelButtonTitle:@"Deny" otherButtonTitles:([prompt objectForKey:@"allowTitle"] ?: @"Allow once"), nil] autorelease];
	if (label != nil) [alert addButtonWithTitle:label];
	self.current = alert;
	[alert show];
}

/// Answers the oldest prompt and moves on to the next one.
- (void)finishFrontPromptWithChoice:(AGApprovalChoice)choice {
	if ([self.queue count] == 0) return;
	NSMutableDictionary *prompt = [[[self.queue objectAtIndex:0] retain] autorelease];
	[self.queue removeObjectAtIndex:0];
	AGApprovalResponder respond = [prompt objectForKey:@"respond"];
	if (respond != nil) respond(choice);
	[self pump];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (alertView != self.current) return;   // withdrawn by promptAbandoned:, already handled
	self.current = nil;
	AGApprovalChoice choice = AGApprovalDeny;   // the Deny button, or the system cancelling the alert
	if (buttonIndex == 1) choice = AGApprovalAllowOnce;
	else if (buttonIndex == 2) choice = AGApprovalAllowForTask;
	[self finishFrontPromptWithChoice:choice];
}

#pragma mark - Questions (web pairing)

- (NSTimeInterval)timeoutForPrompt:(NSDictionary *)prompt {
	NSNumber *own = [prompt objectForKey:@"timeout"];
	return [own isKindOfClass:[NSNumber class]] ? [own doubleValue] : [AGApproval timeout];
}

+ (id)askQuestionWithTitle:(NSString *)title detail:(NSString *)detail allowTitle:(NSString *)allowTitle timeout:(NSTimeInterval)timeout answer:(void (^)(NSInteger answer))answer {
	AGApprovalPresenter *me = g_presenter;
	if (me == nil) return nil;
	id handle = [NSString stringWithFormat:@"question-%08x", arc4random()];
	AGApprovalResponder respond = [[^(AGApprovalChoice choice) { answer(choice == AGApprovalAllowOnce ? AGPairAnswerAllow : AGPairAnswerDeny); } copy] autorelease];
	void (^onTimeout)(void) = [[^{ answer(AGPairAnswerTimedOut); } copy] autorelease];
	NSMutableDictionary *prompt = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		title ?: @"", @"title", detail ?: @"", @"detail", [NSNull null], @"label",
		respond, @"respond", onTimeout, @"onTimeout", allowTitle ?: @"Allow", @"allowTitle",
		[NSNumber numberWithBool:YES], @"question", [NSNumber numberWithDouble:timeout], @"timeout", handle, @"handle", nil];
	dispatch_async(dispatch_get_main_queue(), ^{
		[me.queue addObject:prompt];
		[me pump];
	});
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		NSMutableDictionary *waiting = [me promptWithHandle:handle];
		if (waiting == nil) return;                    // answered or taken back already
		void (^expired)(void) = [[[waiting objectForKey:@"onTimeout"] retain] autorelease];
		[me removePrompt:waiting];
		if (expired != nil) expired();
	});
	return handle;
}

+ (void)cancelQuestion:(id)handle {
	AGApprovalPresenter *me = g_presenter;
	if (me == nil || handle == nil) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableDictionary *waiting = [me promptWithHandle:handle];
		if (waiting != nil) [me removePrompt:waiting];
	});
}

- (NSMutableDictionary *)promptWithHandle:(id)handle {
	for (NSMutableDictionary *prompt in self.queue) if ([[prompt objectForKey:@"handle"] isEqual:handle]) return prompt;
	return nil;
}

/// Takes one prompt off the queue and, if it is the one on screen, off the screen. No answer is delivered.
- (void)removePrompt:(NSMutableDictionary *)prompt {
	BOOL onScreen = ([self.queue count] > 0 && [self.queue objectAtIndex:0] == prompt);
	[[prompt retain] autorelease];
	[self.queue removeObject:prompt];
	if (onScreen) {
		[self withdrawSystemNote];
		UIAlertView *alert = [[self.current retain] autorelease];
		self.current = nil;   // so the delegate ignores the dismissal below
		[alert dismissWithClickedButtonIndex:alert.cancelButtonIndex animated:NO];
		[[UIApplication sharedApplication] cancelAllLocalNotifications];
	}
	[self pump];
}

#pragma mark - System dialog

/// Deny is the default (bold) button on purpose: an accidental tap must never run code.
- (BOOL)presentSystemDialogForPrompt:(NSMutableDictionary *)prompt {
	if (![AGApprovalPresenter globalDialogsEnabled] || !AGSystemDialogsResolved()) return NO;
	if ([[prompt objectForKey:@"systemFailed"] boolValue]) return NO;

	NSString *label = [prompt objectForKey:@"label"];
	NSMutableDictionary *content = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		[prompt objectForKey:@"title"], @"AlertHeader",
		[prompt objectForKey:@"detail"], @"AlertMessage",
		@"Deny", @"DefaultButtonTitle",
		([prompt objectForKey:@"allowTitle"] ?: @"Allow once"), @"AlternateButtonTitle", nil];
	if ([label isKindOfClass:[NSString class]]) [content setObject:label forKey:@"OtherButtonTitle"];

	SInt32 error = 0;
	// Level 2 = caution icon. The timeout makes iOS withdraw the dialog when the agent stops waiting.
	void *note = g_noteCreate(NULL, [self timeoutForPrompt:prompt], 2, &error, (CFDictionaryRef)content);
	if (note == NULL || error != 0) {
		if (note != NULL) CFRelease((CFTypeRef)note);
		[prompt setObject:[NSNumber numberWithBool:YES] forKey:@"systemFailed"];
		return NO;
	}
	_systemNote = note;
	_systemNoteCancelledByUs = NO;
	_systemNoteShownAt = [NSDate timeIntervalSinceReferenceDate];
	[prompt setObject:[NSNumber numberWithInt:[[prompt objectForKey:@"attempts"] intValue] + 1] forKey:@"attempts"];

	// CFUserNotificationReceiveResponse blocks until a button is tapped or the dialog is withdrawn.
	[NSThread detachNewThreadSelector:@selector(waitForSystemNote:) toTarget:self withObject:[NSValue valueWithPointer:note]];
	return YES;
}

- (void)waitForSystemNote:(NSValue *)box {
	@autoreleasepool {
		void *note = [box pointerValue];
		CFOptionFlags flags = 0;
		SInt32 result = g_noteReceive(note, 0, &flags);
		dispatch_async(dispatch_get_main_queue(), ^{ [self systemNote:note endedWithResult:result flags:flags]; });
	}
}

- (void)systemNote:(void *)note endedWithResult:(SInt32)result flags:(CFOptionFlags)flags {
	if (note != _systemNote) { CFRelease((CFTypeRef)note); return; }
	_systemNote = NULL;
	CFRelease((CFTypeRef)note);
	if ([self.queue count] == 0) return;
	NSMutableDictionary *prompt = [self.queue objectAtIndex:0];

	if (_systemNoteCancelledByUs) {          // the app came to the front (or the agent gave up): re-decide
		_systemNoteCancelledByUs = NO;
		[self pump];
		return;
	}
	if (result != 0) {                        // the system could not show or deliver it
		[prompt setObject:[NSNumber numberWithBool:YES] forKey:@"systemFailed"];
		[self pump];
		return;
	}
	CFOptionFlags button = flags & 0x3;       // 0 default, 1 alternate, 2 other, 3 cancelled/withdrawn
	if (button == 3) {
		BOOL early = ([NSDate timeIntervalSinceReferenceDate] - _systemNoteShownAt) < ([self timeoutForPrompt:prompt] - 5.0);
		if (early && [[prompt objectForKey:@"attempts"] intValue] < AGMaxSystemDialogAttempts) { [self pump]; return; }  // dismissed by iOS (e.g. lock): ask again
		if (early) { [prompt setObject:[NSNumber numberWithBool:YES] forKey:@"systemFailed"]; [self pump]; return; }   // keeps vanishing: fall back to a notification
		[self finishFrontPromptWithChoice:AGApprovalDeny];                                                   // timed out
		return;
	}
	[self finishFrontPromptWithChoice:(button == 1) ? AGApprovalAllowOnce : (button == 2) ? AGApprovalAllowForTask : AGApprovalDeny];
}

- (void)withdrawSystemNote {
	if (_systemNote == NULL) return;
	_systemNoteCancelledByUs = YES;
	g_noteCancel(_systemNote);   // makes the waiting thread return, which then releases it
}

#pragma mark - Events

- (void)appBecameActive:(NSNotification *)note {
	[UIApplication sharedApplication].applicationIconBadgeNumber = 0;
	[[UIApplication sharedApplication] cancelAllLocalNotifications];
	[self withdrawSystemNote];   // the person is in the app now: use the in-app alert instead
	[self pump];
}

/// Posted from the worker thread when it stops waiting (Stop tapped, or timeout).
- (void)promptAbandoned:(NSNotification *)note {
	dispatch_async(dispatch_get_main_queue(), ^{
		// The agent stopped waiting. Questions that are not the agent's (web pairing) stay.
		BOOL frontIsQuestion = ([self.queue count] > 0 && [[[self.queue objectAtIndex:0] objectForKey:@"question"] boolValue]);
		NSMutableArray *keep = [NSMutableArray array];
		for (NSMutableDictionary *prompt in self.queue) if ([[prompt objectForKey:@"question"] boolValue]) [keep addObject:prompt];
		self.queue = keep;   // the worker is not waiting for the others any more
		if (!frontIsQuestion) {
			[self withdrawSystemNote];
			UIAlertView *alert = [[self.current retain] autorelease];
			self.current = nil;               // so the delegate ignores the dismissal below
			[alert dismissWithClickedButtonIndex:alert.cancelButtonIndex animated:NO];
			[[UIApplication sharedApplication] cancelAllLocalNotifications];
			[self pump];
		}
	});
}

- (void)responseArrived:(NSNotification *)note {
	AGMessage *message = [note object];
	if ([message isKindOfClass:[AGMessage class]] && [message.role isEqualToString:@"assistant"] && !message.localOnly && [message.content length] > 0) {
		self.lastAssistantText = message.content;
	}
}

- (void)statusChanged:(NSNotification *)note {
	BOOL sending = [[note object] boolValue];
	if (sending) { self.lastAssistantText = nil; return; }
	if ([note userInfo] == nil) return;   // Stop was tapped: no news for the person who tapped it
	if (![AGBackgroundKeeper enabled] || [UIApplication sharedApplication].applicationState == UIApplicationStateActive) return;

	NSString *text = [self.lastAssistantText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text length] > 110) text = [[text substringToIndex:110] stringByAppendingString:@"..."];
	[self postLocalNotification:([text length] > 0) ? [@"Agent finished: " stringByAppendingString:text] : @"The agent has finished or stopped."];
}

- (void)postLocalNotification:(NSString *)body {
	if ([body length] > 160) body = [[body substringToIndex:160] stringByAppendingString:@"..."];
	UILocalNotification *note = [[[UILocalNotification alloc] init] autorelease];
	note.alertBody = body;
	note.alertAction = @"Open";
	note.soundName = UILocalNotificationDefaultSoundName;
	note.applicationIconBadgeNumber = 1;
	[[UIApplication sharedApplication] presentLocalNotificationNow:note];
}

#pragma mark - Test

+ (void)runTestPrompt {
	UIApplication *app = [UIApplication sharedApplication];
	__block UIBackgroundTaskIdentifier keepAlive = [app beginBackgroundTaskWithExpirationHandler:^{
		[app endBackgroundTask:keepAlive];
		keepAlive = UIBackgroundTaskInvalid;
	}];
	[[[[UIAlertView alloc] initWithTitle:@"Test starts in 6 seconds"
		message:@"Press Home or lock the phone now. A system dialog should appear over whatever you are doing; stay in the app to see the in-app alert instead."
		delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[NSThread sleepForTimeInterval:6.0];
		NSString *denial = nil;
		BOOL allowed = [AGApproval requestApprovalForKey:nil title:@"Test: agent wants to run python3"
			detail:@"This is only a test. Nothing will run, whatever you choose." taskLabel:@"Allow python3 for this task (test)"
			isCancelled:nil denial:&denial];
		dispatch_async(dispatch_get_main_queue(), ^{
			[[[[UIAlertView alloc] initWithTitle:@"Test result" message:allowed ? @"You allowed it. The approval path works." : @"You denied it (or it timed out). The approval path works."
				delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
			if (keepAlive != UIBackgroundTaskInvalid) { [app endBackgroundTask:keepAlive]; keepAlive = UIBackgroundTaskInvalid; }
		});
	});
}

@end
