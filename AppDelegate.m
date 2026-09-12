#import "AppDelegate.h"
#import "AudioEngine.h"
#import "HoldShortcutMonitor.h"
#import "FilterKnob.h"
#import "SettingsController.h"
#import "WisprActivity.h"
#include "FilterControl.h"

@interface AppDelegate () <NSPopoverDelegate> {
    FilterControl _control;
    unsigned _refreshTick;
    NSInteger _statusAngle;
    BOOL _selectedOnly, _suspended;
    BOOL _showSettingsAfterPopoverCloses;
}
@property AudioEngine *engine;
@property HoldShortcutMonitor *shortcutMonitor;
@property NSStatusItem *statusItem;
@property NSPopover *popover;
@property NSButton *sourceButton;
@property (copy) NSString *selectedBundle;
@property (copy) NSString *shortcutTitle;
@property SettingsController *settings;
@property FilterKnob *knob;
@property NSTextField *readout;
@property NSButton *settingsButton;
@property NSTimer *timer;
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
    [defaults registerDefaults:@{@"hapticsEnabled": @YES}];
    _control.preset = [defaults objectForKey:@"fnPreset"] ? [defaults doubleForKey:@"fnPreset"] : -.72;
    if (!isfinite(_control.preset)) _control.preset = -.72;
    _control.preset = fmin(1, fmax(-1, _control.preset));
    _selectedOnly = [defaults objectForKey:@"spotifyOnly"] ? [defaults boolForKey:@"spotifyOnly"] : YES;
    self.selectedBundle = [defaults stringForKey:@"selectedBundle"] ?: @"com.spotify.client";
    self.shortcutTitle = [defaults stringForKey:@"holdShortcutTitle"] ?: @"Fn";
    self.engine = [AudioEngine new];
    self.shortcutMonitor = [HoldShortcutMonitor new];
    __weak AppDelegate *weakSelf = self;
    self.shortcutMonitor.changed = ^(BOOL held) { [weakSelf shortcutHeld:held]; };
    if ([defaults objectForKey:@"holdShortcutKeyCode"]) {
        [self.shortcutMonitor setKeyCode:[defaults integerForKey:@"holdShortcutKeyCode"]
                        modifiers:(CGEventFlags)[defaults integerForKey:@"holdShortcutModifiers"]];
    }
    self.settings = [SettingsController new];
    self.settings.presetChanged = ^(double value) {
        AppDelegate *self = weakSelf;
        if (!self) return;
        controlSetPreset(&self->_control, value, NSProcessInfo.processInfo.systemUptime);
        [defaults setDouble:self->_control.preset forKey:@"fnPreset"];
        [self updateControl];
    };
    self.settings.colorsChanged = ^{ weakSelf.knob.needsDisplay = YES; };
    self.settings.wisprChanged = ^(BOOL enabled) { [weakSelf updateWispr]; };
    self.settings.hapticsChanged = ^(BOOL enabled) { weakSelf.knob.hapticsEnabled = enabled; };
    self.settings.recordingChanged = ^(BOOL recording) { weakSelf.shortcutMonitor.recording = recording; };
    self.settings.appChanged = ^(NSString *bundle) {
        AppDelegate *self = weakSelf;
        if (!self || [self.selectedBundle isEqualToString:bundle]) return;
        self.selectedBundle = bundle;
        [defaults setObject:bundle forKey:@"selectedBundle"];
        [self updateSourceButton];
        if (self->_selectedOnly) [self start];
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
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = knobStatusImage(0);
    self.statusItem.button.accessibilityLabel = @"Twiddle";
    self.statusItem.button.toolTip = @"Twiddle";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(statusClicked:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
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
- (void)buildPopover {
    NSRect bounds = NSMakeRect(0, 0, 240, 216);
    NSView *content = [[NSView alloc] initWithFrame:bounds];
    self.sourceButton = [NSButton buttonWithImage:[SettingsController iconForBundle:self.selectedBundle]
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
    [content addSubview:self.readout];
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
    }
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    if (!self.popover.shown) [self statusClicked:nil];
    return YES;
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
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit Twiddle" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = nil;
}
- (void)showSettings:(id)sender {
    self.settings.selectedBundle = self.selectedBundle;
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
    if (!_showSettingsAfterPopoverCloses) return;
    _showSettingsAfterPopoverCloses = NO;
    // Let the popover finish restoring focus before activating the settings window.
    dispatch_async(dispatch_get_main_queue(), ^{ [self.settings show]; });
}
- (void)openPermissions:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]];
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
    double value = controlValue(&_control, NSProcessInfo.processInfo.systemUptime);
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
    self.readout.hidden = fabs(displayed) <= .00001;
    NSString *name = [FilterKnob labelForValue:displayed];
    if (![self.readout.stringValue isEqualToString:name]) self.readout.stringValue = name;
}
- (void)resetKnob:(id)sender {
    controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)knobChanged:(id)sender {
    controlSetBaseline(&_control, self.knob.doubleValue, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)shortcutHeld:(BOOL)held {
    if (held && !self.engine.running) return;
    controlSetTrigger(&_control, PresetTriggerShortcut, held, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)updateWispr {
    BOOL active = !_suspended && self.engine.running && [NSUserDefaults.standardUserDefaults boolForKey:@"followWisprFlow"] && wisprMicrophoneActive();
    controlSetTrigger(&_control, PresetTriggerWispr, active, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)updateSourceButton {
    NSString *name = [SettingsController nameForBundle:self.selectedBundle];
    self.sourceButton.image = _selectedOnly ? [SettingsController iconForBundle:self.selectedBundle] : symbol(@"desktopcomputer");
    self.sourceButton.accessibilityLabel = _selectedOnly ? [name stringByAppendingString:@" only"] : @"All Mac audio";
    self.sourceButton.toolTip = _selectedOnly ? [NSString stringWithFormat:@"%@ only — click for all Mac audio", name] :
        [NSString stringWithFormat:@"All Mac audio — click for %@ only", name];
}
- (void)scopeChanged:(id)sender {
    _selectedOnly = !_selectedOnly;
    [NSUserDefaults.standardUserDefaults setBool:_selectedOnly forKey:@"spotifyOnly"];
    [self updateSourceButton];
    [self start];
}
- (void)start {
    while (!_suspended && ![self.engine startWithBundles:_selectedOnly ? [NSSet setWithObject:self.selectedBundle] : nil probe:NO]) {
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
    [self updateControl];
    if (++_refreshTick % 15 == 0) {
        [self updateWispr];
        if (self.engine.running && ![self.engine checkRoute]) {
            controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
            if (!_suspended) [self start];
        }
    }
}
- (void)suspend:(NSNotification *)notification {
    _suspended = YES;
    [self.shortcutMonitor disable];
    [self updateWispr];
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
    [self.timer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.shortcutMonitor disable];
    [self.engine stop];
}
@end
