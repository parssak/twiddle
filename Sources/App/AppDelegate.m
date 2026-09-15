#import "AppDelegate.h"
#import "AudioEngine.h"
#import "HoldShortcutMonitor.h"
#import "GlobalFilterHotkeys.h"
#import "FilterKnob.h"
#import "SettingsController.h"
#import "AudioProcessActivity.h"
#import "PlaybackActivity.h"
#import "SpotifyNowPlaying.h"
#import "TwiddleControl.h"
#import <ServiceManagement/ServiceManagement.h>
#import "MarqueeLabel.h"
#import "ViewAnimations.h"
#import "ApplicationInfo.h"
#import <QuartzCore/QuartzCore.h>
#include "FilterControl.h"

typedef NS_ENUM(NSInteger, FooterMode) {
    FooterModeNone,
    FooterModeFilter,
    FooterModeNowPlaying,
};
static const NSTimeInterval GlobalHotkeyPopoverDuration = 1.4;

@interface AppDelegate () <NSPopoverDelegate> {
    FilterControl _control;
    unsigned _refreshTick;
    NSInteger _statusAngle;
    BOOL _suspended;
    BOOL _showSettingsAfterPopoverCloses;
    NSTimeInterval _filterReadoutUntil;
    NSUInteger _footerTransition;
}
@property AudioEngine *engine;
@property HoldShortcutMonitor *shortcutMonitor;
@property GlobalFilterHotkeys *globalFilterHotkeys;
@property NSStatusItem *statusItem;
@property NSPopover *popover;
@property NSButton *sourceButton;
@property (copy) NSString *selectedBundle;
@property (copy) NSArray<NSString *> *targetBundles;
@property (copy) NSString *shortcutTitle;
@property SettingsController *settings;
@property BOOL discoActive;
@property TwiddleControlServer *controlServer;
@property PlaybackActivity *playbackActivity;
@property FilterKnob *knob;
@property NSTextField *readout;
@property MarqueeLabel *nowPlayingReadout;
@property NSButton *settingsButton;
@property SpotifyNowPlaying *spotifyNowPlaying;
@property (copy) NSString *nowPlayingText;
@property FooterMode footerMode;
@property NSTimer *timer;
@property NSTimer *globalHotkeyPopoverTimer;
@end

static NSImage *symbol(NSString *name) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
}

static NSImage *knobStatusImage(NSInteger degrees) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [NSColor.blackColor setStroke];
        NSBezierPath *outline = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3.375, 3.375, 11.25, 11.25)];
        outline.lineWidth = 1.2375;
        [outline stroke];
        double angle = (90 - degrees) * M_PI / 180;
        NSBezierPath *pointer = [NSBezierPath bezierPath];
        [pointer moveToPoint:NSMakePoint(9 + cos(angle) * 5.625, 9 + sin(angle) * 5.625)];
        [pointer lineToPoint:NSMakePoint(9 + cos(angle) * 1.5, 9 + sin(angle) * 1.5)];
        pointer.lineWidth = 1.2375;
        pointer.lineCapStyle = NSLineCapStyleRound;
        [pointer stroke];
        return YES;
    }];
    image.template = YES;
    return image;
}

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // Register login once for new installs; never undo a user's later opt-out.
    if (![defaults boolForKey:@"loginDefaultApplied"]) {
        BOOL freshInstall = [defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier].count == 0;
        [defaults setBool:YES forKey:@"loginDefaultApplied"];
        if (freshInstall && SMAppService.mainAppService.status == SMAppServiceStatusNotRegistered) {
            NSError *error = nil;
            if (![SMAppService.mainAppService registerAndReturnError:&error])
                NSLog(@"Could not enable Open at Login: %@", error.localizedDescription);
        }
    }
    [defaults registerDefaults:@{@"hapticsEnabled": @YES}];
    [defaults registerDefaults:@{@"microphoneScope": @"wispr"}];
    if (![defaults objectForKey:@"microphoneEnabled"]) {
        BOOL installed = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.electron.wispr-flow"] != nil;
        NSNumber *previous = [defaults objectForKey:@"followWisprFlow"];
        [defaults setBool:previous ? previous.boolValue : installed forKey:@"microphoneEnabled"];
    }
    double defaultPreset = [FilterKnob defaultPresetValue];
    _control.preset = [defaults objectForKey:@"fnPreset"] ? [defaults doubleForKey:@"fnPreset"] : defaultPreset;
    if (!isfinite(_control.preset)) _control.preset = defaultPreset;
    _control.preset = fmin(1, fmax(-1, _control.preset));
    self.selectedBundle = [defaults stringForKey:@"selectedBundle"] ?: @"com.spotify.client";
    if (![defaults objectForKey:@"targetBundles"]) [defaults setObject:@[self.selectedBundle] forKey:@"targetBundles"];
    self.targetBundles = [defaults stringArrayForKey:@"targetBundles"] ?: @[];
    self.selectedBundle = self.targetBundles.firstObject ?: @"";
    self.shortcutTitle = [defaults stringForKey:@"holdShortcutTitle"] ?: @"None";
    self.engine = [AudioEngine new];
    self.playbackActivity = [PlaybackActivity new];
    self.spotifyNowPlaying = [SpotifyNowPlaying new];
    self.shortcutMonitor = [HoldShortcutMonitor new];
    self.globalFilterHotkeys = [GlobalFilterHotkeys new];
    __weak AppDelegate *weakSelf = self;
    self.shortcutMonitor.changed = ^(BOOL held) { [weakSelf shortcutHeld:held]; };
    self.globalFilterHotkeys.performed = ^(GlobalFilterHotkeyAction action) {
        [weakSelf performGlobalFilterHotkey:action];
    };
    if (![self.globalFilterHotkeys start]) NSLog(@"%@", self.globalFilterHotkeys.errorMessage);
    if ([defaults objectForKey:@"holdShortcutKeyCode"]) {
        [self.shortcutMonitor setKeyCode:[defaults integerForKey:@"holdShortcutKeyCode"]
                        modifiers:(CGEventFlags)[defaults integerForKey:@"holdShortcutModifiers"]];
    }
    self.settings = [SettingsController new];
    self.controlServer = [[TwiddleControlServer alloc] initWithPath:twiddleControlPath() handler:^NSDictionary *(NSDictionary *command) {
        return [weakSelf performCLICommand:command];
    }];
    if (![self.controlServer start]) NSLog(@"Twiddle CLI control channel unavailable.");
    self.settings.shortcutAccessRequested = ^{
        if (CGPreflightPostEventAccess()) {
            [weakSelf.globalFilterHotkeys stop];
            [weakSelf.globalFilterHotkeys start];
        } else {
            [weakSelf openAccessibilityPermissions:nil];
        }
        [weakSelf refreshShortcutAccess];
    };
    self.settings.menuBarSettingsRequested = ^{ [weakSelf openMenuBarSettings:nil]; };
    self.settings.presetChanged = ^(double value) {
        AppDelegate *self = weakSelf;
        if (!self) return;
        controlSetPreset(&self->_control, value, NSProcessInfo.processInfo.systemUptime);
        [defaults setDouble:self->_control.preset forKey:@"fnPreset"];
        [self updateControl];
    };
    self.settings.colorsChanged = ^{ weakSelf.knob.needsDisplay = YES; };
    self.settings.discoChanged = ^(BOOL active) {
        weakSelf.discoActive = active;
        [weakSelf updateAutomaticTriggers];
    };
    self.settings.microphoneChanged = ^ { [weakSelf updateAutomaticTriggers]; };
    self.settings.hapticsChanged = ^(BOOL enabled) { weakSelf.knob.hapticsEnabled = enabled; };
    self.settings.recordingChanged = ^(BOOL recording) { weakSelf.shortcutMonitor.recording = recording; };
    self.settings.appsChanged = ^{
        AppDelegate *self = weakSelf;
        if (!self) return;
        NSArray *targets = [defaults stringArrayForKey:@"targetBundles"] ?: @[];
        BOOL targetsChanged = ![targets isEqualToArray:self.targetBundles];
        self.targetBundles = targets;
        self.selectedBundle = targets.firstObject ?: @"";
        if (targetsChanged) [self start];
        [self updateSourceButton];
        [self refreshNowPlaying];
        [self updateAutomaticTriggers];
    };
    self.settings.shortcutChanged = ^(NSInteger keyCode, NSEventModifierFlags flags, NSString *title) {
        AppDelegate *self = weakSelf;
        if (!self) return;
        [self.shortcutMonitor setKeyCode:keyCode modifiers:(CGEventFlags)flags];
        self.shortcutTitle = title;
        [defaults setInteger:keyCode forKey:@"holdShortcutKeyCode"];
        [defaults setInteger:flags forKey:@"holdShortcutModifiers"];
        [defaults setObject:title forKey:@"holdShortcutTitle"];
        [defaults setBool:!self.shortcutMonitor.configured forKey:@"fnDisabled"];
        if (!self.shortcutMonitor.configured) [self.shortcutMonitor disable];
        else if (![self.shortcutMonitor enableRequestingPermission:YES]) [self openPermissions:nil];
        [self updateControl];
    };
    if (![defaults boolForKey:@"fnDisabled"]) [self.shortcutMonitor enableRequestingPermission:NO];
    [self installStatusItem];
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *applicationMenu = [NSMenuItem new];
    applicationMenu.submenu = [NSMenu new];
    NSMenuItem *settingsItem = [applicationMenu.submenu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    settingsItem.target = self;
    [applicationMenu.submenu addItemWithTitle:@"Quit Twiddle" action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu addItem:applicationMenu];
    NSApp.mainMenu = mainMenu;
    [self buildPopover];
    self.timer = [NSTimer timerWithTimeInterval:1.0 / 60 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(suspend:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(suspend:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspace addObserver:self selector:@selector(resume:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    [self start];
    [self updateControl];
}
- (void)installStatusItem {
    if (self.statusItem) {
        self.statusItem.visible = YES;
        return;
    }
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    // A stable identity gives Twiddle one persistent slot in macOS's Menu Bar settings.
    self.statusItem.autosaveName = @"TwiddleMenuBarItemV2";
    self.statusItem.behavior = NSStatusItemBehaviorRemovalAllowed;
    self.statusItem.visible = YES;
    self.statusItem.button.image = knobStatusImage(lround(controlValue(&_control, NSProcessInfo.processInfo.systemUptime) * 135));
    self.statusItem.button.accessibilityLabel = @"Twiddle";
    self.statusItem.button.toolTip = @"Twiddle";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(statusClicked:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
}
- (void)buildPopover {
    NSRect bounds = NSMakeRect(0, 0, 240, 216);
    NSView *content = [[NSView alloc] initWithFrame:bounds];
    self.sourceButton = [NSButton buttonWithImage:[ApplicationInfo iconForBundle:self.selectedBundle]
        target:self action:@selector(scopeChanged:)];
    self.sourceButton.frame = NSMakeRect(18, 12, 28, 28);
    self.sourceButton.bordered = NO;
    [self updateSourceButton];
    [content addSubview:self.sourceButton];
    self.knob = [[FilterKnob alloc] initWithFrame:NSMakeRect(34, 32, 172, 164)];
    self.knob.hapticsEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"hapticsEnabled"];
    self.knob.target = self;
    self.knob.action = @selector(knobChanged:);
    self.knob.resetAction = @selector(resetKnob:);
    [content addSubview:self.knob];
    self.readout = [NSTextField labelWithString:@"Bypass"];
    self.readout.alignment = NSTextAlignmentCenter;
    self.readout.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    CGFloat textHeight = self.readout.fittingSize.height;
    self.readout.frame = NSMakeRect(48, NSMidY(self.sourceButton.frame) - textHeight / 2, 144, textHeight);
    self.readout.textColor = NSColor.secondaryLabelColor;
    self.readout.hidden = YES;
    self.readout.wantsLayer = YES;
    [content addSubview:self.readout];
    self.nowPlayingReadout = [[MarqueeLabel alloc] initWithFrame:self.readout.frame];
    self.nowPlayingReadout.hidden = YES;
    [content addSubview:self.nowPlayingReadout];
    self.settingsButton = [NSButton buttonWithImage:symbol(@"gearshape") target:self action:@selector(showSettings:)];
    self.settingsButton.frame = NSMakeRect(194, 12, 28, 28);
    self.settingsButton.bordered = NO;
    self.settingsButton.accessibilityLabel = @"Settings";
    self.settingsButton.toolTip = @"Settings";
    self.settingsButton.contentTintColor = NSColor.secondaryLabelColor;
    [content addSubview:self.settingsButton];
    NSViewController *controller = [NSViewController new];
    controller.view = content;
    self.popover = [NSPopover new];
    self.popover.delegate = self;
    self.popover.contentViewController = controller;
    self.popover.contentSize = bounds.size;
    self.popover.behavior = NSPopoverBehaviorTransient;
}
- (void)statusClicked:(id)sender {
    if (NSApp.currentEvent.type == NSEventTypeRightMouseUp) { [self showMenu]; return; }
    if (self.popover.shown) [self.popover performClose:nil];
    else {
        [NSApp activateIgnoringOtherApps:YES];
        [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
        self.nowPlayingReadout.active = self.footerMode == FooterModeNowPlaying;
        [self refreshNowPlaying];
    }
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    if (![self statusItemHasMenuBarAnchor]) {
        [self openMenuBarSettings:nil];
        return YES;
    }
    if (!self.popover.shown) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.15 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [self statusClicked:nil]; });
    return YES;
}
- (BOOL)statusItemHasMenuBarAnchor {
    NSWindow *window = self.statusItem.button.window;
    if (!self.statusItem.visible || !window || NSIsEmptyRect(window.frame)) return NO;
    NSPoint center = NSMakePoint(NSMidX(window.frame), NSMidY(window.frame));
    for (NSScreen *screen in NSScreen.screens) {
        if (!NSPointInRect(center, screen.frame)) continue;
        // A hosted status-item window lives in the strip above the screen's
        // visible frame. A removed item is parked elsewhere by AppKit.
        return NSMinY(window.frame) >= NSMaxY(screen.visibleFrame) - 2;
    }
    return NO;
}
- (void)showMenu {
    [self.popover performClose:nil];
    NSMenu *menu = [NSMenu new];
    NSMenuItem *settings = [menu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    settings.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *fn = [menu addItemWithTitle:[self.shortcutTitle stringByAppendingString:@" shortcut"] action:@selector(toggleShortcut:) keyEquivalent:@""];
    fn.target = self;
    fn.enabled = self.shortcutMonitor.configured;
    fn.state = self.shortcutMonitor.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *permissions = [menu addItemWithTitle:@"Input Monitoring…" action:@selector(openPermissions:) keyEquivalent:@""];
    permissions.target = self;
    NSMenuItem *topRowPermissions = [menu addItemWithTitle:CGPreflightPostEventAccess() ? @"Top-row Shortcut Access…" : @"Enable ⌥F10–F12 — Accessibility…" action:@selector(openAccessibilityPermissions:) keyEquivalent:@""];
    topRowPermissions.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit Twiddle" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = nil;
}
- (void)showSettings:(id)sender {
    [self refreshShortcutAccess];
    self.settings.shortcutTitle = self.shortcutTitle;
    self.settings.presetValue = _control.preset;
    if (self.popover.shown) {
        _showSettingsAfterPopoverCloses = YES;
        [self.popover performClose:nil];
    } else {
        [self.settings show];
    }
}
- (void)popoverDidClose:(NSNotification *)notification {
    [self.globalHotkeyPopoverTimer invalidate];
    self.globalHotkeyPopoverTimer = nil;
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.nowPlayingReadout.active = NO;
    if (!_showSettingsAfterPopoverCloses) return;
    _showSettingsAfterPopoverCloses = NO;
    // Let the popover finish restoring focus before activating the settings window.
    dispatch_async(dispatch_get_main_queue(), ^{ [self.settings show]; });
}
- (void)openPermissions:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]];
}
- (void)refreshShortcutAccess {
    BOOL granted = CGPreflightPostEventAccess();
    if (!_suspended && granted && !self.globalFilterHotkeys.enabled) [self.globalFilterHotkeys start];
    [self.settings updateShortcutAccess:granted ready:self.globalFilterHotkeys.enabled error:self.globalFilterHotkeys.errorMessage];
}
- (void)openAccessibilityPermissions:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (void)openMenuBarSettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    [NSWorkspace.sharedWorkspace openURL:url configuration:configuration
        completionHandler:^(NSRunningApplication *application, NSError *error) {
            if (error) NSLog(@"Could not open Menu Bar settings: %@", error.localizedDescription);
        }];
}
- (void)toggleShortcut:(id)sender {
    if (self.shortcutMonitor.enabled) {
        [self.shortcutMonitor disable];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"fnDisabled"];
    } else {
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"fnDisabled"];
        if (![self.shortcutMonitor enableRequestingPermission:YES]) [self openPermissions:nil];
    }
    [self updateControl];
}
- (void)updateControl {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    double value = controlValue(&_control, now);
    self.engine.target = value;
    double displayed = value;
    self.knob.doubleValue = displayed;
    // Whole degrees avoid
    // redrawing the tiny template image for subpixel changes or idle frames.
    NSInteger angle = lround(displayed * 135);
    if (angle != _statusAngle) {
        _statusAngle = angle;
        self.statusItem.button.image = knobStatusImage(angle);
    }
    self.knob.enabled = self.engine.running && !_control.held;
    self.knob.accessibilityLabel = @"Current filter";
    NSString *name = [FilterKnob labelForValue:displayed];
    if (![self.readout.stringValue isEqualToString:name]) self.readout.stringValue = name;
    FooterMode mode = FooterModeNone;
    if (now < _filterReadoutUntil) {
        if (!name.length) self.readout.stringValue = @"Bypass";
        mode = FooterModeFilter;
    } else if (self.nowPlayingText.length) {
        mode = FooterModeNowPlaying;
    } else if (name.length) {
        mode = FooterModeFilter;
    }
    [self showFooterMode:mode];
}
- (void)resetKnob:(id)sender {
    _filterReadoutUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
    controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)knobChanged:(id)sender {
    _filterReadoutUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
    controlSetBaseline(&_control, self.knob.doubleValue, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)performGlobalFilterHotkey:(GlobalFilterHotkeyAction)action {
    if (_suspended || !self.engine.running) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    _filterReadoutUntil = now + GlobalHotkeyPopoverDuration;
    if (action == GlobalFilterHotkeyToggle) controlTogglePreset(&_control, now);
    else controlStepBaseline(&_control, action == GlobalFilterHotkeyDecrease ? -1 : 1, now);
    [self updateControl];
    [self showPopoverForGlobalHotkey];
}
- (void)showPopoverForGlobalHotkey {
    if (![self statusItemHasMenuBarAnchor]) return;
    self.popover.behavior = NSPopoverBehaviorApplicationDefined;
    if (!self.popover.shown) {
        [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button
                           preferredEdge:NSRectEdgeMinY];
    }
    self.nowPlayingReadout.active = NO;
    [self.globalHotkeyPopoverTimer invalidate];
    __weak AppDelegate *weakSelf = self;
    self.globalHotkeyPopoverTimer = [NSTimer timerWithTimeInterval:GlobalHotkeyPopoverDuration
        repeats:NO block:^(NSTimer *timer) {
            AppDelegate *self = weakSelf;
            self.globalHotkeyPopoverTimer = nil;
            if (self.popover.shown) [self.popover performClose:nil];
        }];
    [NSRunLoop.mainRunLoop addTimer:self.globalHotkeyPopoverTimer forMode:NSRunLoopCommonModes];
}
- (void)showFooterMode:(FooterMode)mode {
    if (_footerMode == mode) {
        self.nowPlayingReadout.active = self.popover.shown && mode == FooterModeNowPlaying;
        return;
    }
    FooterMode previous = _footerMode;
    _footerMode = mode;
    NSUInteger transition = ++_footerTransition;
    NSView *outgoing = previous == FooterModeFilter ? self.readout :
        previous == FooterModeNowPlaying ? self.nowPlayingReadout : nil;
    NSView *incoming = mode == FooterModeFilter ? self.readout :
        mode == FooterModeNowPlaying ? self.nowPlayingReadout : nil;
    self.nowPlayingReadout.active = self.popover.shown && mode == FooterModeNowPlaying;
    if (!self.popover.shown) {
        for (NSView *field in @[self.readout, self.nowPlayingReadout]) {
            clearBlur(field);
            field.alphaValue = field == incoming ? 1 : 0;
            field.hidden = field != incoming;
        }
        return;
    }
    outgoing.hidden = NO;
    incoming.hidden = NO;
    if (outgoing) animateBlur(outgoing, 0, 6, .18);
    if (incoming) {
        incoming.alphaValue = 0;
        animateBlur(incoming, 6, 0, .18);
        animateScaleIn(incoming, .18);
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = .18;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        outgoing.animator.alphaValue = 0;
        incoming.animator.alphaValue = 1;
    } completionHandler:^{
        if (transition != self->_footerTransition) return;
        for (NSView *field in @[self.readout, self.nowPlayingReadout]) {
            BOOL visible = field == incoming;
            clearBlur(field);
            field.alphaValue = visible ? 1 : 0;
            field.hidden = !visible;
        }
    }];
}
- (void)refreshNowPlaying {
    if (![self.selectedBundle isEqualToString:@"com.spotify.client"]) {
        self.nowPlayingText = nil;
        self.nowPlayingReadout.stringValue = @"";
        [self updateControl];
        return;
    }
    __weak AppDelegate *weakSelf = self;
    [self.spotifyNowPlaying refreshWithCompletion:^(NSString *track) {
        AppDelegate *self = weakSelf;
        if (!self || ![self.selectedBundle isEqualToString:@"com.spotify.client"]) return;
        self.nowPlayingText = track;
        self.nowPlayingReadout.stringValue = track ?: @"";
        self.nowPlayingReadout.toolTip = track;
        self.nowPlayingReadout.accessibilityLabel = track.length ? [@"Now playing: " stringByAppendingString:track] : nil;
        [self updateControl];
    }];
}
- (NSDictionary *)performCLICommand:(NSDictionary *)request {
    NSString *command = request[@"command"];
    double now = NSProcessInfo.processInfo.systemUptime;
    if ([command isEqual:@"set"] || [command isEqual:@"apply"]) {
        // Explicit CLI filter changes have the same priority as manual bypass.
        controlReset(&_control, now);
        controlSetBaseline(&_control, [command isEqual:@"apply"] ? _control.preset : [request[@"value"] doubleValue], now);
    } else if ([command isEqual:@"preset"]) {
        controlSetPreset(&_control, [request[@"value"] doubleValue], now);
        [NSUserDefaults.standardUserDefaults setDouble:_control.preset forKey:@"fnPreset"];
        self.settings.presetValue = _control.preset;
    } else if ([command isEqual:@"reset"]) {
        controlReset(&_control, now);
    } else if ([command isEqual:@"disco"]) {
        [self.settings setDiscoEnabled:[request[@"enabled"] boolValue]];
    } else if ([command isEqual:@"settings"]) {
        [self showSettings:nil];
    }
    [self updateControl];
    return @{@"ok":@YES, @"running":@(self.engine.running), @"value":@(controlValue(&_control, now)),
        @"target":@(_control.to), @"baseline":@(_control.baseline), @"preset":@(_control.preset),
        @"autoApplyActive":@(_control.held), @"automationSuppressed":@(_control.suppressTriggers),
        @"disco":@(self.discoActive), @"targetApps":self.targetBundles ?: @[],
        @"triggerApps":[NSUserDefaults.standardUserDefaults stringArrayForKey:@"triggerBundles"] ?: @[],
        @"audioError":self.engine.errorMessage ?: (id)NSNull.null};
}
- (void)shortcutHeld:(BOOL)held {
    if (held && !self.engine.running) return;
    controlSetTrigger(&_control, PresetTriggerShortcut, held, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)updateAutomaticTriggers {
    controlSetTrigger(&_control, PresetTriggerDisco, !_suspended && self.engine.running && self.discoActive, NSProcessInfo.processInfo.systemUptime);
    BOOL active = !_suspended && self.engine.running && [NSUserDefaults.standardUserDefaults boolForKey:@"microphoneEnabled"] && microphoneActive([NSUserDefaults.standardUserDefaults stringForKey:@"microphoneScope"]);
    controlSetTrigger(&_control, PresetTriggerMicrophone, active, NSProcessInfo.processInfo.systemUptime);
    NSArray *processes = !_suspended && self.engine.running ? activeOutputProcesses([NSSet setWithArray:[NSUserDefaults.standardUserDefaults stringArrayForKey:@"triggerBundles"] ?: @[]]) : @[];
    [self.playbackActivity updateProcesses:processes];
    controlSetTrigger(&_control, PresetTriggerPlayback, self.playbackActivity.audible, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)updateSourceButton {
    NSString *name = self.targetBundles.count == 1 ? [ApplicationInfo nameForBundle:self.selectedBundle] :
        self.targetBundles.count ? [NSString stringWithFormat:@"%lu apps", (unsigned long)self.targetBundles.count] : @"No apps selected";
    self.sourceButton.image = self.targetBundles.count == 1 ? [ApplicationInfo iconForBundle:self.selectedBundle] : symbol(@"square.grid.2x2");
    self.sourceButton.accessibilityLabel = [@"Apps to Twiddle: " stringByAppendingString:name];
    self.sourceButton.toolTip = [name stringByAppendingString:@" — choose apps to Twiddle"];
}
- (void)scopeChanged:(id)sender {
    [self showSettings:nil];
    [self.settings showApps:nil];
}
- (void)start {
    if (!self.targetBundles.count) {
        [self.engine stop];
        [self updateAutomaticTriggers];
        [self updateControl];
        return;
    }
    while (!_suspended && ![self.engine startWithBundles:[NSSet setWithArray:self.targetBundles] probe:NO]) {
        [self updateControl];
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Couldn’t start audio";
        alert.informativeText = self.engine.errorMessage ?: @"Try again after checking your audio output.";
        [alert addButtonWithTitle:@"Retry"];
        [alert addButtonWithTitle:@"Quit"];
        if ([alert runModal] != NSAlertFirstButtonReturn) { [NSApp terminate:nil]; return; }
    }
    [self updateControl];
}
- (void)refresh:(NSTimer *)timer {
    controlSetTrigger(&_control, PresetTriggerPlayback, !_suspended && self.engine.running && self.playbackActivity.audible, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
    _refreshTick++;
    if (_refreshTick % 15 == 0) {
        [self updateAutomaticTriggers];
        if (self.engine.running && ![self.engine checkRoute]) {
            [self.playbackActivity stop];
            controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
            if (!_suspended) [self start];
        }
    }
    if (_refreshTick % 60 == 0 && self.popover.shown) [self refreshNowPlaying];
    if (_refreshTick % 60 == 0) [self refreshShortcutAccess];
}
- (void)suspend:(NSNotification *)notification {
    _suspended = YES;
    [self.shortcutMonitor disable];
    [self updateAutomaticTriggers];
    controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
    [self.engine stop];
}
- (void)resume:(NSNotification *)notification {
    if (!_suspended) return;
    _suspended = NO;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"fnDisabled"]) [self.shortcutMonitor enableRequestingPermission:NO];
    [self start];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.controlServer stop];
    [self.timer invalidate];
    [self.globalHotkeyPopoverTimer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.globalFilterHotkeys stop];
    [self.shortcutMonitor disable];
    [self.playbackActivity stop];
    [self.engine stop];
}
@end
