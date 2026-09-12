#import "AppDelegate.h"
#import "AudioEngine.h"
#import "FnKeyMonitor.h"
#include "FilterControl.h"

@interface AppDelegate () {
    FilterControl _control;
    unsigned _refreshTick;
    double _stopAt;
    BOOL _poweredOn, _spotifyOnly, _suspended;
}
@property AudioEngine *engine;
@property FnKeyMonitor *fnMonitor;
@property NSStatusItem *statusItem;
@property NSPopover *popover;
@property NSSegmentedControl *scopeControl;
@property NSSlider *slider, *presetSlider;
@property NSButton *powerButton;
@property NSImageView *fnIcon;
@property NSTimer *timer;
@end

static NSImage *symbol(NSString *name) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
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
    _poweredOn = [defaults objectForKey:@"powerEnabled"] ? [defaults boolForKey:@"powerEnabled"] : YES;
    self.engine = [AudioEngine new];
    self.fnMonitor = [FnKeyMonitor new];
    __weak AppDelegate *weakSelf = self;
    self.fnMonitor.changed = ^(BOOL held) { [weakSelf fnHeld:held]; };
    if (![defaults boolForKey:@"fnDisabled"]) [self.fnMonitor enableRequestingPermission:NO];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = symbol(@"line.3.horizontal.decrease");
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
    if (_poweredOn) [self start];
    [self updateControl];
}
- (void)buildPopover {
    NSRect bounds = NSMakeRect(0, 0, 304, 180);
    NSView *content = [[NSView alloc] initWithFrame:bounds];
    NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:bounds];
    glass.style = NSGlassEffectViewStyleRegular;
    glass.cornerRadius = 20;
    glass.contentView = content;
    NSURL *spotifyURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.spotify.client"];
    NSImage *spotify = spotifyURL ? [NSWorkspace.sharedWorkspace iconForFile:spotifyURL.path] : symbol(@"music.note");
    spotify.size = NSMakeSize(22, 22);
    self.scopeControl = [NSSegmentedControl segmentedControlWithImages:@[spotify, symbol(@"desktopcomputer")]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(scopeChanged:)];
    self.scopeControl.frame = NSMakeRect(18, 128, 112, 32);
    self.scopeControl.selectedSegment = _spotifyOnly ? 0 : 1;
    [self.scopeControl setWidth:48 forSegment:0];
    [self.scopeControl setWidth:48 forSegment:1];
    [self.scopeControl setToolTip:@"Spotify only" forSegment:0];
    [self.scopeControl setToolTip:@"All Mac audio" forSegment:1];
    self.scopeControl.accessibilityLabel = @"Audio source";
    [content addSubview:self.scopeControl];
    self.powerButton = [NSButton buttonWithImage:symbol(@"power") target:self action:@selector(togglePower:)];
    self.powerButton.frame = NSMakeRect(252, 128, 34, 32);
    self.powerButton.bezelStyle = NSBezelStyleCircular;
    [content addSubview:self.powerButton];
    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(18, 113, 268, 1)];
    divider.boxType = NSBoxSeparator;
    [content addSubview:divider];
    NSImageView *currentIcon = [NSImageView imageViewWithImage:symbol(@"waveform.path")];
    currentIcon.frame = NSMakeRect(18, 82, 22, 22);
    currentIcon.contentTintColor = NSColor.secondaryLabelColor;
    currentIcon.toolTip = @"Current filter";
    [content addSubview:currentIcon];
    self.slider = [NSSlider sliderWithValue:0 minValue:-1 maxValue:1 target:self action:@selector(sliderChanged:)];
    self.slider.frame = NSMakeRect(52, 80, 232, 26);
    self.slider.continuous = YES;
    self.slider.accessibilityLabel = @"Current filter";
    [content addSubview:self.slider];
    self.fnIcon = [NSImageView imageViewWithImage:symbol(@"fn")];
    self.fnIcon.frame = NSMakeRect(18, 36, 22, 22);
    [content addSubview:self.fnIcon];
    self.presetSlider = [NSSlider sliderWithValue:_control.preset minValue:-1 maxValue:1 target:self action:@selector(presetChanged:)];
    self.presetSlider.frame = NSMakeRect(52, 34, 232, 26);
    self.presetSlider.continuous = YES;
    self.presetSlider.accessibilityLabel = @"Fn preset";
    self.presetSlider.toolTip = [@"Fn preset: " stringByAppendingString:filterName(_control.preset)];
    [content addSubview:self.presetSlider];
    NSViewController *controller = [NSViewController new];
    controller.view = glass;
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
    if (self.slider.doubleValue != value) self.slider.doubleValue = value;
    self.slider.enabled = _poweredOn && self.engine.running && !_control.held;
    self.powerButton.contentTintColor = _poweredOn ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    self.powerButton.accessibilityLabel = _poweredOn ? @"Turn filtering off" : @"Turn filtering on";
    self.powerButton.toolTip = self.powerButton.accessibilityLabel;
    self.fnIcon.contentTintColor = _control.held ? NSColor.controlAccentColor :
        (self.fnMonitor.enabled ? NSColor.secondaryLabelColor : NSColor.systemOrangeColor);
    self.fnIcon.toolTip = self.fnMonitor.enabled ? @"Fn preset" : @"Fn unavailable — right-click the menu bar icon to enable it";
    self.statusItem.button.appearsDisabled = !_poweredOn;
}
- (void)sliderChanged:(id)sender {
    double value = self.slider.doubleValue;
    controlSetBaseline(&_control, fabs(value) < .015 ? 0 : value, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)presetChanged:(id)sender {
    double value = self.presetSlider.doubleValue;
    controlSetPreset(&_control, fabs(value) < .015 ? 0 : value, NSProcessInfo.processInfo.systemUptime);
    [NSUserDefaults.standardUserDefaults setDouble:_control.preset forKey:@"fnPreset"];
    self.presetSlider.toolTip = [@"Fn preset: " stringByAppendingString:filterName(_control.preset)];
}
- (void)fnHeld:(BOOL)held {
    if (held && (!_poweredOn || !self.engine.running)) return;
    controlSetHeld(&_control, held, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)scopeChanged:(id)sender {
    _spotifyOnly = self.scopeControl.selectedSegment == 0;
    [NSUserDefaults.standardUserDefaults setBool:_spotifyOnly forKey:@"spotifyOnly"];
    if (_poweredOn) { [self.engine stop]; [self start]; }
}
- (void)togglePower:(id)sender {
    _poweredOn = !_poweredOn;
    [NSUserDefaults.standardUserDefaults setBool:_poweredOn forKey:@"powerEnabled"];
    if (_poweredOn) {
        _stopAt = 0;
        if (!self.engine.running) [self start];
    } else {
        controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
        // Let the control ramp and DSP smoothing finish before releasing audio.
        _stopAt = NSProcessInfo.processInfo.systemUptime + .4;
    }
    [self updateControl];
}
- (void)start {
    _stopAt = 0;
    [self updateControl];
    if (![self.engine startWithBundles:_spotifyOnly ? [NSSet setWithObject:@"com.spotify.client"] : nil probe:NO]) {
        _poweredOn = NO;
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Couldn’t start audio";
        alert.informativeText = self.engine.errorMessage ?: @"Try again after checking your audio output.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
    [self updateControl];
}
- (void)refresh:(NSTimer *)timer {
    [self updateControl];
    if (_stopAt && NSProcessInfo.processInfo.systemUptime >= _stopAt) {
        _stopAt = 0;
        [self.engine stop];
    }
    if (++_refreshTick % 15 == 0 && self.engine.running && ![self.engine checkRoute]) {
        controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
        if (_poweredOn && !_suspended) [self start];
    }
}
- (void)suspend:(NSNotification *)notification {
    _suspended = YES;
    _stopAt = 0;
    [self.fnMonitor disable];
    controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
    [self.engine stop];
}
- (void)resume:(NSNotification *)notification {
    if (!_suspended) return;
    _suspended = NO;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"fnDisabled"]) [self.fnMonitor enableRequestingPermission:NO];
    if (_poweredOn) [self start];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.fnMonitor disable];
    [self.engine stop];
}
@end
