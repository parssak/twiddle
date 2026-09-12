#import "AppDelegate.h"
#import "AudioEngine.h"
#import "FnKeyMonitor.h"
#import "FilterKnob.h"
#include "FilterControl.h"

@interface AppDelegate () {
    FilterControl _control;
    unsigned _refreshTick;
    NSInteger _statusAngle;
    BOOL _spotifyOnly, _suspended, _editingPreset;
}
@property AudioEngine *engine;
@property FnKeyMonitor *fnMonitor;
@property NSStatusItem *statusItem;
@property NSPopover *popover;
@property NSButton *sourceButton;
@property NSImage *spotifyIcon;
@property FilterKnob *knob;
@property NSTextField *readout;
@property NSButton *presetButton;
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

static NSString *filterName(double value) {
    if (value < -.00001) return [NSString stringWithFormat:@"Low-pass · %.0f Hz", 20000 * pow(60.0 / 20000, -value)];
    if (value > .00001) return [NSString stringWithFormat:@"High-pass · %.0f Hz", 20 * pow(10000.0 / 20, value)];
    return @"Bypass";
}

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    _control.preset = [defaults objectForKey:@"fnPreset"] ? [defaults doubleForKey:@"fnPreset"] : -.72;
    if (!isfinite(_control.preset)) _control.preset = -.72;
    _control.preset = fmin(1, fmax(-1, _control.preset));
    _spotifyOnly = [defaults objectForKey:@"spotifyOnly"] ? [defaults boolForKey:@"spotifyOnly"] : YES;
    self.engine = [AudioEngine new];
    self.fnMonitor = [FnKeyMonitor new];
    __weak AppDelegate *weakSelf = self;
    self.fnMonitor.changed = ^(BOOL held) { [weakSelf fnHeld:held]; };
    if (![defaults boolForKey:@"fnDisabled"]) [self.fnMonitor enableRequestingPermission:NO];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = knobStatusImage(0);
    self.statusItem.button.accessibilityLabel = @"Lowpasser";
    self.statusItem.button.toolTip = @"Lowpasser";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(statusClicked:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
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
    NSURL *spotifyURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.spotify.client"];
    self.spotifyIcon = spotifyURL ? [NSWorkspace.sharedWorkspace iconForFile:spotifyURL.path] : symbol(@"music.note");
    self.spotifyIcon.size = NSMakeSize(22, 22);
    self.sourceButton = [NSButton buttonWithImage:self.spotifyIcon target:self action:@selector(scopeChanged:)];
    self.sourceButton.frame = NSMakeRect(18, 12, 28, 28);
    self.sourceButton.bordered = NO;
    [self updateSourceButton];
    [content addSubview:self.sourceButton];
    self.knob = [[FilterKnob alloc] initWithFrame:NSMakeRect(34, 32, 172, 164)];
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
    self.presetButton = [NSButton buttonWithImage:symbol(@"gearshape") target:self action:@selector(togglePresetEditing:)];
    self.presetButton.frame = NSMakeRect(194, 12, 28, 28);
    self.presetButton.bordered = NO;
    [self.presetButton setButtonType:NSButtonTypePushOnPushOff];
    self.presetButton.accessibilityLabel = @"Edit Fn preset";
    [content addSubview:self.presetButton];
    NSViewController *controller = [NSViewController new];
    controller.view = content;
    self.popover = [NSPopover new];
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
    NSMenuItem *fn = [menu addItemWithTitle:@"Fn shortcut" action:@selector(toggleFn:) keyEquivalent:@""];
    fn.target = self;
    fn.state = self.fnMonitor.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *permissions = [menu addItemWithTitle:@"Input Monitoring…" action:@selector(openPermissions:) keyEquivalent:@""];
    permissions.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit Lowpasser" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = nil;
}
- (void)openPermissions:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]];
}
- (void)toggleFn:(id)sender {
    if (self.fnMonitor.enabled) {
        [self.fnMonitor disable];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"fnDisabled"];
    } else {
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"fnDisabled"];
        if (![self.fnMonitor enableRequestingPermission:YES]) [self openPermissions:nil];
    }
    [self updateControl];
}
- (void)updateControl {
    double value = controlValue(&_control, NSProcessInfo.processInfo.systemUptime);
    self.engine.target = value;
    double displayed = _editingPreset ? _control.preset : value;
    self.knob.doubleValue = displayed;
    // Match the visible knob, including preset editing. Whole degrees avoid
    // redrawing the tiny template image for subpixel changes or idle frames.
    NSInteger angle = lround(displayed * 135);
    if (angle != _statusAngle) {
        _statusAngle = angle;
        self.statusItem.button.image = knobStatusImage(angle);
    }
    self.knob.enabled = _editingPreset || (self.engine.running && !_control.held);
    self.knob.editingPreset = _editingPreset;
    self.knob.accessibilityLabel = _editingPreset ? @"Fn preset" : @"Current filter";
    NSString *name = filterName(displayed);
    if (![self.readout.stringValue isEqualToString:name]) self.readout.stringValue = name;
    self.presetButton.state = _editingPreset ? NSControlStateValueOn : NSControlStateValueOff;
    self.presetButton.contentTintColor = _editingPreset ? NSColor.systemPurpleColor :
        (self.fnMonitor.enabled ? NSColor.secondaryLabelColor : NSColor.systemOrangeColor);
    self.presetButton.toolTip = self.fnMonitor.enabled ? @"Edit the held Fn preset" : @"Fn unavailable — right-click the menu bar icon to enable it";
}
- (void)togglePresetEditing:(id)sender {
    _editingPreset = !_editingPreset;
    [self updateControl];
}
- (void)resetKnob:(id)sender {
    double now = NSProcessInfo.processInfo.systemUptime;
    if (_editingPreset) {
        controlSetPreset(&_control, 0, now);
        [NSUserDefaults.standardUserDefaults setDouble:0 forKey:@"fnPreset"];
    } else {
        controlReset(&_control, now);
    }
    [self updateControl];
}
- (void)knobChanged:(id)sender {
    double value = self.knob.doubleValue;
    if (_editingPreset) {
        controlSetPreset(&_control, value, NSProcessInfo.processInfo.systemUptime);
        [NSUserDefaults.standardUserDefaults setDouble:_control.preset forKey:@"fnPreset"];
    } else {
        controlSetBaseline(&_control, value, NSProcessInfo.processInfo.systemUptime);
    }
    [self updateControl];
}
- (void)fnHeld:(BOOL)held {
    if (held && !self.engine.running) return;
    controlSetHeld(&_control, held, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)updateSourceButton {
    self.sourceButton.image = _spotifyOnly ? self.spotifyIcon : symbol(@"desktopcomputer");
    self.sourceButton.accessibilityLabel = _spotifyOnly ? @"Spotify only" : @"All Mac audio";
    self.sourceButton.toolTip = _spotifyOnly ? @"Spotify only — click for all Mac audio" : @"All Mac audio — click for Spotify only";
}
- (void)scopeChanged:(id)sender {
    _spotifyOnly = !_spotifyOnly;
    [NSUserDefaults.standardUserDefaults setBool:_spotifyOnly forKey:@"spotifyOnly"];
    [self updateSourceButton];
    [self start];
}
- (void)start {
    while (!_suspended && ![self.engine startWithBundles:_spotifyOnly ? [NSSet setWithObject:@"com.spotify.client"] : nil probe:NO]) {
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
    if (++_refreshTick % 15 == 0 && self.engine.running && ![self.engine checkRoute]) {
        controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
        if (!_suspended) [self start];
    }
}
- (void)suspend:(NSNotification *)notification {
    _suspended = YES;
    [self.fnMonitor disable];
    controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
    [self.engine stop];
}
- (void)resume:(NSNotification *)notification {
    if (!_suspended) return;
    _suspended = NO;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"fnDisabled"]) [self.fnMonitor enableRequestingPermission:NO];
    [self start];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.fnMonitor disable];
    [self.engine stop];
}
@end
