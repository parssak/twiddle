#import "AppDelegate.h"
#import "AudioEngine.h"
#import "HoldShortcutMonitor.h"
#import "GlobalFilterHotkeys.h"
#import "FilterKnob.h"
#import "EffectsTrayView.h"
#import "EffectHoldButton.h"
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
static const CGFloat EffectsTrayHeight = 140;
static const CGFloat EffectKnobSize = 88;
static const NSPoint EffectKnobPositions[] = { {16, 36}, {136, 36} };

@interface AppDelegate () <NSPopoverDelegate> {
    FilterControl _control;
    unsigned _refreshTick;
    NSInteger _statusAngle;
    BOOL _suspended;
    BOOL _showSettingsAfterPopoverCloses;
    NSTimeInterval _filterReadoutUntil;
    NSUInteger _footerTransition;
    CGFloat _effectsProgress;
    NSTimeInterval _effectsLastTick;
}
@property AudioEngine *engine;
@property NSArray<FilterKnob *> *effectKnobs;
@property NSArray<NSTextField *> *effectLabels;
@property NSButton *effectsButton;
@property NSView *mainControls;
@property NSView *effectsTray;
@property EffectHoldButton *tapeStopButton;
@property EffectHoldButton *discoButton;
@property BOOL effectsExpanded;
@property NSTimer *effectsAnimationTimer;
@property (copy) NSString *effectReadout;
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
    self.settings.menuBarSettingsRequested = ^{
        AppDelegate *self = weakSelf;
        if (!self) return;
        if ([self statusItemHasMenuBarAnchor]) [self openMenuBarSettings:nil];
        else [self restoreMenuBarItemShowingPopover:NO];
    };
    self.settings.presetChanged = ^(double value) {
        AppDelegate *self = weakSelf;
        if (!self) return;
        controlSetPreset(&self->_control, value, NSProcessInfo.processInfo.systemUptime);
        [defaults setDouble:self->_control.preset forKey:@"fnPreset"];
        [self updateControl];
    };
    self.settings.discoChanged = ^(BOOL active) {
        weakSelf.discoActive = active;
        weakSelf.discoButton.state = active ? NSControlStateValueOn : NSControlStateValueOff;
        weakSelf.discoButton.needsDisplay = YES;
    };
    self.settings.microphoneChanged = ^ { [weakSelf updateAutomaticTriggers]; };
    self.settings.hapticsChanged = ^(BOOL enabled) {
        weakSelf.knob.hapticsEnabled = enabled;
        for (FilterKnob *knob in weakSelf.effectKnobs) knob.hapticsEnabled = enabled;
    };
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
    self.settingsButton.frame = NSMakeRect(18, 177, 28, 28);
    self.settingsButton.bordered = NO;
    self.settingsButton.accessibilityLabel = @"Settings";
    self.settingsButton.toolTip = @"Settings";
    self.settingsButton.contentTintColor = NSColor.secondaryLabelColor;
    [content addSubview:self.settingsButton];
    NSButton *effects = [NSButton buttonWithTitle:@"FX" target:self action:@selector(showEffects:)];
    effects.frame = NSMakeRect(192, 14, 34, 24);
    effects.bordered = NO;
    effects.accessibilityLabel = @"Effects";
    effects.contentTintColor = NSColor.secondaryLabelColor;
    self.effectsButton = effects;
    NSView *root = [[NSView alloc] initWithFrame:bounds];
    self.mainControls = content;
    self.effectsTray = [[EffectsTrayView alloc] initWithFrame:NSMakeRect(0, 0, 240, 0)];
    self.effectsTray.wantsLayer = YES;
    self.effectsTray.layer.masksToBounds = YES;
    [root addSubview:self.effectsTray];
    [root addSubview:content];
    NSMutableArray *effectKnobs = [NSMutableArray new];
    NSMutableArray *effectLabels = [NSMutableArray new];
    NSArray *names = @[@"Reverb", @"Pitch"];
    for (NSUInteger i = 0; i < names.count; i++) {
        FilterKnob *knob = [[FilterKnob alloc] initWithFrame:
            NSMakeRect(EffectKnobPositions[i].x, EffectKnobPositions[i].y, EffectKnobSize, EffectKnobSize)];
        knob.unipolar = i == 0;
        knob.metalTint = [NSColor colorWithSRGBRed:.32 green:.35 blue:.39 alpha:1];
        knob.dragStep = i == 1 ? 1.0 / 12 : 0;
        knob.hapticsEnabled = self.knob.hapticsEnabled;
        knob.tag = i;
        knob.target = self;
        knob.action = @selector(effectChanged:);
        knob.resetAction = @selector(resetEffect:);
        knob.accessibilityLabel = names[i];
        if (i == 1) knob.toolTip = @"Drag: steps · Scroll: smooth";
        knob.hidden = YES;
        [self.effectsTray addSubview:knob];
        [effectKnobs addObject:knob];
        NSTextField *label = [NSTextField labelWithString:names[i]];
        label.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
        label.textColor = NSColor.secondaryLabelColor;
        label.alignment = NSTextAlignmentCenter;
        label.hidden = YES;
        [self.effectsTray addSubview:label];
        [effectLabels addObject:label];
    }
    self.effectKnobs = effectKnobs;
    self.effectLabels = effectLabels;
    self.tapeStopButton = [[EffectHoldButton alloc] initWithFrame:NSMakeRect(108, 88, 24, 24)];
    self.tapeStopButton.title = @"";
    self.tapeStopButton.image = symbol(@"stop.fill");
    self.tapeStopButton.iconSize = 12;
    self.tapeStopButton.imagePosition = NSImageOnly;
    self.tapeStopButton.bordered = NO;
    self.tapeStopButton.accessibilityLabel = @"Hold for tape stop";
    self.tapeStopButton.toolTip = @"Hold to stop";
    __weak AppDelegate *weakSelf = self;
    self.tapeStopButton.heldChanged = ^(BOOL held) { weakSelf.engine.tapeStop = held; };
    [self.effectsTray addSubview:self.tapeStopButton];
    self.discoButton = [[EffectHoldButton alloc] initWithFrame:NSMakeRect(108, 54, 24, 24)];
    self.discoButton.momentary = NO;
    self.discoButton.title = @"";
    self.discoButton.image = symbol(@"sparkles");
    self.discoButton.iconSize = 16;
    self.discoButton.imagePosition = NSImageOnly;
    self.discoButton.bordered = NO;
    self.discoButton.activeColor = [NSColor colorWithSRGBRed:.72 green:.46 blue:1 alpha:1];
    self.discoButton.state = self.discoActive ? NSControlStateValueOn : NSControlStateValueOff;
    self.discoButton.accessibilityLabel = @"Disco";
    self.discoButton.toolTip = @"Disco";
    self.discoButton.target = self;
    self.discoButton.action = @selector(toggleDisco:);
    [self.effectsTray addSubview:self.discoButton];
    [content addSubview:effects];
    NSViewController *controller = [NSViewController new];
    controller.view = root;
    self.popover = [NSPopover new];
    self.popover.delegate = self;
    self.popover.contentViewController = controller;
    self.popover.contentSize = bounds.size;
    self.popover.behavior = NSPopoverBehaviorTransient;
}
- (void)layoutEffects {
    CGFloat progress = _effectsProgress;
    CGFloat eased = progress * progress * (3 - 2 * progress);
    CGFloat height = EffectsTrayHeight * eased;
    // Resize the single popover and shift the main section by the same amount
    // so its controls stay anchored while the effects section unfolds below.
    BOOL animates = self.popover.animates;
    self.popover.animates = NO;
    self.popover.contentSize = NSMakeSize(240, 216 + height);
    self.popover.animates = animates;
    self.mainControls.frame = NSMakeRect(0, height, 240, 216);
    self.effectsTray.frame = NSMakeRect(0, 0, 240, height);
    CGFloat reveal = fmax(0, fmin(1, (progress - .2) / .8));
    reveal = reveal * reveal * (3 - 2 * reveal);
    for (NSUInteger i = 0; i < self.effectKnobs.count; i++) {
        FilterKnob *knob = self.effectKnobs[i];
        knob.frame = NSMakeRect(EffectKnobPositions[i].x,
            EffectKnobPositions[i].y + height - EffectsTrayHeight + 10 * (1 - reveal), EffectKnobSize, EffectKnobSize);
        knob.alphaValue = reveal;
        knob.hidden = reveal == 0;
        NSTextField *label = self.effectLabels[i];
        label.frame = NSMakeRect(NSMinX(knob.frame), NSMinY(knob.frame) - 14, EffectKnobSize, 14);
        label.alphaValue = reveal;
        label.hidden = reveal == 0;
    }
    self.tapeStopButton.frame = NSMakeRect(108,
        88 + height - EffectsTrayHeight + 10 * (1 - reveal), 24, 24);
    self.tapeStopButton.alphaValue = reveal;
    self.tapeStopButton.hidden = reveal == 0;
    self.discoButton.frame = NSMakeRect(108,
        54 + height - EffectsTrayHeight + 10 * (1 - reveal), 24, 24);
    self.discoButton.alphaValue = reveal;
    self.discoButton.hidden = reveal == 0;
}
- (void)toggleDisco:(id)sender {
    [self.settings setDiscoEnabled:!self.discoActive];
}
- (void)showEffects:(id)sender {
    self.effectsExpanded = !self.effectsExpanded;
    if (!self.effectsExpanded) self.tapeStopButton.held = NO;
    self.effectsButton.contentTintColor = self.effectsExpanded ? FilterKnob.filterColor : NSColor.secondaryLabelColor;
    self.effectsButton.accessibilityValue = self.effectsExpanded ? @"Expanded" : @"Collapsed";
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        [self.effectsAnimationTimer invalidate];
        self.effectsAnimationTimer = nil;
        _effectsProgress = self.effectsExpanded ? 1 : 0;
        [self layoutEffects];
        return;
    }
    // A second click reverses the running timeline from its current position.
    if (self.effectsAnimationTimer) return;
    _effectsLastTick = NSProcessInfo.processInfo.systemUptime;
    __weak AppDelegate *weakSelf = self;
    self.effectsAnimationTimer = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        AppDelegate *self = weakSelf;
        if (!self) { [timer invalidate]; return; }
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        CGFloat step = (now - self->_effectsLastTick) / .24;
        self->_effectsLastTick = now;
        self->_effectsProgress = fmax(0, fmin(1,
            self->_effectsProgress + (self.effectsExpanded ? step : -step)));
        [self layoutEffects];
        if (self->_effectsProgress == (self.effectsExpanded ? 1 : 0)) {
            [timer invalidate];
            self.effectsAnimationTimer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:self.effectsAnimationTimer forMode:NSRunLoopCommonModes];
}
- (void)effectChanged:(NSControl *)knob {
    double value = knob.doubleValue;
    if (knob.tag == 0) self.engine.reverb = value;
    else self.engine.pitch = value * 12;
    NSString *name = @[@"Reverb", @"Pitch"][knob.tag];
    NSString *amount = knob.tag == 1 ? [NSString stringWithFormat:@"%+.2f st", value * 12] :
        (value == 0 ? @"Off" : [NSString stringWithFormat:@"%.0f%%", value * 100]);
    self.effectReadout = [NSString stringWithFormat:@"%@ · %@", name, amount];
    _filterReadoutUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
    [self updateControl];
}
- (void)resetEffect:(FilterKnob *)knob {
    knob.doubleValue = 0;
    [self effectChanged:knob];
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
        [self restoreMenuBarItemShowingPopover:YES];
        return YES;
    }
    if (!self.popover.shown) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.15 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [self statusClicked:nil]; });
    return YES;
}
- (void)restoreMenuBarItemShowingPopover:(BOOL)showPopover {
    [self installStatusItem];
    __weak AppDelegate *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AppDelegate *self = weakSelf;
        if (!self) return;
        BOOL restored = [self statusItemHasMenuBarAnchor];
        self.settings.menuBarItemVisible = restored;
        if (!restored) {
            [self openMenuBarSettings:nil];
        } else if (showPopover && !self.popover.shown) {
            [self statusClicked:nil];
        }
    });
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
    self.settings.menuBarItemVisible = [self statusItemHasMenuBarAnchor];
    if (self.popover.shown) {
        _showSettingsAfterPopoverCloses = YES;
        [self.popover performClose:nil];
    } else {
        [self.settings show];
    }
}
- (void)popoverWillClose:(NSNotification *)notification {
    self.tapeStopButton.held = NO;
    [self.effectsAnimationTimer invalidate];
    self.effectsAnimationTimer = nil;
    _effectsProgress = self.effectsExpanded ? 1 : 0;
}
- (void)popoverDidClose:(NSNotification *)notification {
    [self layoutEffects];
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
    if (now >= _filterReadoutUntil) self.effectReadout = nil;
    NSString *name = self.effectReadout ?: [FilterKnob labelForValue:displayed];
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
    self.effectReadout = nil;
    _filterReadoutUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
    controlReset(&_control, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)knobChanged:(id)sender {
    self.effectReadout = nil;
    _filterReadoutUntil = NSProcessInfo.processInfo.systemUptime + 1.0;
    controlSetBaseline(&_control, self.knob.doubleValue, NSProcessInfo.processInfo.systemUptime);
    [self updateControl];
}
- (void)performGlobalFilterHotkey:(GlobalFilterHotkeyAction)action {
    self.effectReadout = nil;
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
    } else if ([command isEqual:@"update"]) {
        [self.settings checkForUpdates:nil];
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
    self.sourceButton.toolTip = @"Choose apps";
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
