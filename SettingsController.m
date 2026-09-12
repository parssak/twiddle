#import "SettingsController.h"
#import "FilterKnob.h"
#import <ServiceManagement/ServiceManagement.h>

static NSArray<NSArray<NSString *> *> *apps(void) {
    return @[@[@"com.spotify.client", @"Spotify"], @[@"com.apple.Music", @"Music"],
             @[@"com.google.Chrome", @"Chrome"], @[@"company.thebrowser.Browser", @"Arc"],
             @[@"company.thebrowser.dia", @"Dia"]];
}
static NSEventModifierFlags shortcutFlags(NSEventModifierFlags flags) {
    return flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption |
                    NSEventModifierFlagShift | NSEventModifierFlagFunction);
}
static NSString *modifierTitle(NSEventModifierFlags flags) {
    NSMutableString *title = [NSMutableString new];
    if (flags & NSEventModifierFlagControl) [title appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption) [title appendString:@"⌥"];
    if (flags & NSEventModifierFlagShift) [title appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [title appendString:@"⌘"];
    if (flags & NSEventModifierFlagFunction) [title appendString:@"Fn"];
    return title;
}
static NSString *keyTitle(NSEvent *event) {
    switch (event.keyCode) {
        case 36: return @"↩"; case 48: return @"⇥"; case 49: return @"Space";
        case 51: return @"⌫"; case 117: return @"⌦";
        case 123: return @"←"; case 124: return @"→"; case 125: return @"↓"; case 126: return @"↑";
    }
    NSString *characters = [event charactersByApplyingModifiers:0];
    if (characters.length) {
        unichar c = [characters characterAtIndex:0];
        if (c >= NSF1FunctionKey && c <= NSF35FunctionKey) return [NSString stringWithFormat:@"F%d", c - NSF1FunctionKey + 1];
        if (c < 0xF700) return characters.uppercaseString;
    }
    return [NSString stringWithFormat:@"Key %hu", event.keyCode];
}

// Color controls in a floating panel should respond on the first click,
// even when another application is currently active.
@interface FilterColorWell : NSColorWell
@end
@implementation FilterColorWell
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

// A slight adaptive wash groups rows without opaque NSBox backgrounds.
@interface SettingsGroupView : NSView
@end
@implementation SettingsGroupView
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor.labelColor colorWithAlphaComponent:.035] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:12 yRadius:12] fill];
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

@interface SettingsController () {
    id _eventMonitor;
    NSEventModifierFlags _recordedFlags;
}
@property (weak) NSColorWell *activeColorWell;
@property NSSwitch *wisprSwitch;
@property FilterKnob *presetKnob;
@property NSTextField *presetReadout;
@property NSSwitch *loginSwitch;
@property NSSwitch *hapticsSwitch;
@property NSButton *recorder;
@property NSPopUpButton *appPicker;
@end

@implementation SettingsController
+ (NSString *)nameForBundle:(NSString *)bundle {
    for (NSArray *app in apps()) if ([app[0] isEqualToString:bundle]) return app[1];
    return @"Spotify";
}
+ (NSImage *)iconForBundle:(NSString *)bundle {
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundle];
    NSImage *image = url ? [NSWorkspace.sharedWorkspace iconForFile:url.path] :
        [NSImage imageWithSystemSymbolName:@"app" accessibilityDescription:nil];
    image.size = NSMakeSize(20, 20);
    return image;
}
- (instancetype)init {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 648)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        panel.title = @"Twiddle Settings";
        panel.floatingPanel = YES;
        panel.titlebarAppearsTransparent = YES;
        panel.opaque = NO;
        panel.backgroundColor = NSColor.clearColor;
        panel.hidesOnDeactivate = NO;
        panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
        panel.delegate = self;
        panel.releasedWhenClosed = NO;
        NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:panel.contentView.bounds];
        glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        glass.style = NSGlassEffectViewStyleRegular;
        glass.cornerRadius = 20;
        NSView *content = [[NSView alloc] initWithFrame:glass.bounds];
        glass.contentView = content;
        panel.contentView = glass;
        for (NSValue *rect in @[[NSValue valueWithRect:NSMakeRect(16, 356, 348, 224)],
                               [NSValue valueWithRect:NSMakeRect(16, 16, 348, 296)]]) {
            SettingsGroupView *group = [[SettingsGroupView alloc] initWithFrame:rect.rectValue];
            [content addSubview:group];
        }
        NSArray *sectionTitles = @[@"General", @"Shortcut & Wispr Flow"];
        NSArray *sectionPositions = @[@588, @320];
        for (NSUInteger i = 0; i < sectionTitles.count; i++) {
            NSTextField *heading = [NSTextField labelWithString:sectionTitles[i]];
            heading.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
            heading.textColor = NSColor.secondaryLabelColor;
            heading.frame = NSMakeRect(32, [sectionPositions[i] doubleValue], 316, 16);
            [content addSubview:heading];
        }
        for (NSNumber *y in @[@524, @468, @412, @252, @192]) {
            NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(32, y.doubleValue, 316, 1)];
            divider.boxType = NSBoxSeparator;
            [content addSubview:divider];
        }
        NSArray *titles = @[@"Open at Login", @"Trackpad Haptics", @"Default app", @"Filter colors",
                            @"Follow Wispr Flow", @"Hold shortcut", @"Filter to apply"];
        NSArray *centers = @[@552, @496, @440, @384, @282, @222, @116];
        for (NSUInteger i = 0; i < titles.count; i++) {
            NSTextField *label = [NSTextField labelWithString:titles[i]];
            label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            label.frame = NSMakeRect(32, [centers[i] doubleValue] - 9, 160, 18);
            [content addSubview:label];
        }
        self.loginSwitch = [NSSwitch new];
        self.loginSwitch.target = self;
        self.loginSwitch.action = @selector(toggleLogin:);
        self.loginSwitch.accessibilityLabel = @"Open at Login";
        self.hapticsSwitch = [NSSwitch new];
        self.hapticsSwitch.target = self;
        self.hapticsSwitch.action = @selector(toggleHaptics:);
        self.hapticsSwitch.accessibilityLabel = @"Trackpad Haptics";
        self.wisprSwitch = [NSSwitch new];
        self.wisprSwitch.target = self;
        self.wisprSwitch.action = @selector(toggleWispr:);
        self.wisprSwitch.accessibilityLabel = @"Follow Wispr Flow";
        self.wisprSwitch.toolTip = @"Use the preset while Wispr Flow’s microphone is active, including hands-free listening.";
        NSArray<NSSwitch *> *switches = @[self.loginSwitch, self.hapticsSwitch, self.wisprSwitch];
        NSArray *switchCenters = @[@552, @496, @282];
        for (NSUInteger i = 0; i < switches.count; i++) {
            NSSwitch *control = switches[i];
            [control sizeToFit];
            [control setFrameOrigin:NSMakePoint(348 - NSWidth(control.frame), [switchCenters[i] doubleValue] - NSHeight(control.frame) / 2)];
            [content addSubview:control];
        }
        self.appPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(186, 424, 162, 32) pullsDown:NO];
        self.appPicker.bordered = NO;
        self.appPicker.target = self;
        self.appPicker.action = @selector(chooseApp:);
        self.appPicker.accessibilityLabel = @"Default app";
        [content addSubview:self.appPicker];
        for (NSUInteger i = 0; i < 2; i++) {
            NSTextField *label = [NSTextField labelWithString:i ? @"High" : @"Low"];
            label.font = [NSFont systemFontOfSize:11];
            label.textColor = NSColor.secondaryLabelColor;
            label.frame = NSMakeRect(194 + i * 80, 376, 32, 16);
            [content addSubview:label];
            NSColorWell *well = [[FilterColorWell alloc] initWithFrame:NSMakeRect(232 + i * 80, 372, 28, 24)];
            well.colorWellStyle = NSColorWellStyleMinimal;
            well.supportsAlpha = NO;
            well.pulldownTarget = self;
            well.pulldownAction = @selector(openColorPicker:);
            well.color = i ? FilterKnob.highColor : FilterKnob.lowColor;
            well.tag = i;
            well.target = self;
            well.action = @selector(changeColor:);
            well.accessibilityLabel = i ? @"High-pass color" : @"Low-pass color";
            [content addSubview:well];
        }
        NSColorPanel.sharedColorPanel.showsAlpha = NO;
        self.recorder = [NSButton buttonWithTitle:@"Fn" target:self action:@selector(toggleRecording:)];
        self.recorder.frame = NSMakeRect(164, 206, 120, 32);
        self.recorder.bezelStyle = NSBezelStyleRounded;
        self.recorder.toolTip = @"Click to record. Press Escape to cancel. The shortcut also reaches other apps.";
        self.recorder.accessibilityLabel = @"Record hold shortcut";
        [content addSubview:self.recorder];
        NSArray *symbols = @[@"arrow.counterclockwise", @"xmark"];
        for (NSUInteger i = 0; i < 2; i++) {
            NSButton *button = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:nil]
                target:self action:i ? @selector(clearShortcut:) : @selector(resetShortcut:)];
            button.frame = NSMakeRect(288 + i * 32, 206, 28, 32);
            button.bordered = NO;
            button.contentTintColor = NSColor.secondaryLabelColor;
            button.toolTip = i ? @"Clear hold shortcut" : @"Reset shortcut to Fn";
            button.accessibilityLabel = button.toolTip;
            [content addSubview:button];
        }
        self.presetKnob = [[FilterKnob alloc] initWithFrame:NSMakeRect(184, 44, 152, 144)];
        self.presetKnob.enabled = YES;
        self.presetKnob.target = self;
        self.presetKnob.action = @selector(changePreset:);
        self.presetKnob.resetAction = @selector(resetPreset:);
        self.presetKnob.accessibilityLabel = @"Filter applied by shortcut or Wispr Flow";
        [content addSubview:self.presetKnob];
        self.presetReadout = [NSTextField labelWithString:@""];
        self.presetReadout.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
        self.presetReadout.textColor = NSColor.secondaryLabelColor;
        self.presetReadout.alignment = NSTextAlignmentCenter;
        self.presetReadout.frame = NSMakeRect(170, 28, 178, 16);
        [content addSubview:self.presetReadout];
        [panel center];
    }
    return self;
}
- (void)setPresetValue:(double)value {
    _presetValue = isfinite(value) ? fmax(-1, fmin(1, value)) : 0;
    self.presetKnob.doubleValue = _presetValue;
    self.presetReadout.stringValue = [FilterKnob labelForValue:_presetValue];
}
- (void)changePreset:(id)sender {
    self.presetValue = self.presetKnob.doubleValue;
    if (self.presetChanged) self.presetChanged(self.presetValue);
}
- (void)resetPreset:(id)sender {
    self.presetValue = 0;
    if (self.presetChanged) self.presetChanged(0);
}
- (void)openColorPicker:(NSColorWell *)sender {
    [self cancelRecording];
    [self.activeColorWell deactivate];
    self.activeColorWell = sender;
    [sender activate:YES];
    NSColorPanel *picker = NSColorPanel.sharedColorPanel;
    picker.title = sender.tag ? @"High-pass color" : @"Low-pass color";
    picker.continuous = YES;
    picker.level = self.window.level + 1;
    [NSApp activateIgnoringOtherApps:YES];
    [picker makeKeyAndOrderFront:nil];
}
- (void)changeColor:(id)sender {
    NSColorWell *well = [sender isKindOfClass:NSColorWell.class] ? sender : self.activeColorWell;
    NSColor *color = [[sender color] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!well || !color) return;
    well.color = color;
    [NSUserDefaults.standardUserDefaults setObject:@[@(color.redComponent), @(color.greenComponent), @(color.blueComponent)]
                                           forKey:well.tag ? @"highColor" : @"lowColor"];
    self.presetKnob.needsDisplay = YES;
    if (self.colorsChanged) self.colorsChanged();
}
- (void)toggleWispr:(NSSwitch *)sender {
    [self cancelRecording];
    BOOL enabled = sender.state == NSControlStateValueOn;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"followWisprFlow"];
    if (self.wisprChanged) self.wisprChanged(enabled);
}
- (void)show {
    [self cancelRecording];
    [self refreshSwitches];
    self.recorder.title = self.shortcutTitle ?: @"Fn";
    [self.appPicker removeAllItems];
    self.appPicker.menu.autoenablesItems = NO;
    for (NSArray *app in apps()) {
        [self.appPicker addItemWithTitle:app[1]];
        NSMenuItem *item = self.appPicker.lastItem;
        item.representedObject = app[0];
        item.image = [SettingsController iconForBundle:app[0]];
        item.enabled = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:app[0]] != nil;
        if ([self.selectedBundle isEqualToString:app[0]]) [self.appPicker selectItem:item];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
}
- (void)refreshSwitches {
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    self.loginSwitch.state = status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginSwitch.toolTip = status == SMAppServiceStatusRequiresApproval ? @"Allow Twiddle in System Settings → General → Login Items" : nil;
    self.hapticsSwitch.state = [NSUserDefaults.standardUserDefaults boolForKey:@"hapticsEnabled"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.presetKnob.hapticsEnabled = self.hapticsSwitch.state == NSControlStateValueOn;
    self.wisprSwitch.state = [NSUserDefaults.standardUserDefaults boolForKey:@"followWisprFlow"] ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)toggleLogin:(NSSwitch *)sender {
    [self cancelRecording];
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL enabled = sender.state == NSControlStateValueOn;
    BOOL success = YES;
    if (enabled && service.status != SMAppServiceStatusEnabled && service.status != SMAppServiceStatusRequiresApproval) {
        success = [service registerAndReturnError:&error];
    } else if (!enabled && (service.status == SMAppServiceStatusEnabled || service.status == SMAppServiceStatusRequiresApproval)) {
        success = [service unregisterAndReturnError:&error];
    }
    [self refreshSwitches];
    if (enabled && service.status == SMAppServiceStatusRequiresApproval) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Allow Twiddle to open at login";
        alert.informativeText = @"Enable Twiddle in System Settings → General → Login Items.";
        [alert addButtonWithTitle:@"Open System Settings"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn) [SMAppService openSystemSettingsLoginItems];
        }];
    } else if (!success) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Couldn’t update Open at Login";
        alert.informativeText = error.localizedDescription ?: @"Try again from the copy of Twiddle in Applications.";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}
- (void)toggleHaptics:(NSSwitch *)sender {
    [self cancelRecording];
    BOOL enabled = sender.state == NSControlStateValueOn;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"hapticsEnabled"];
    self.presetKnob.hapticsEnabled = enabled;
    if (self.hapticsChanged) self.hapticsChanged(enabled);
}
- (void)windowDidBecomeKey:(NSNotification *)notification { [self refreshSwitches]; }
- (void)chooseApp:(id)sender {
    [self cancelRecording];
    self.selectedBundle = self.appPicker.selectedItem.representedObject;
    if (self.appChanged) self.appChanged(self.selectedBundle);
}
- (void)cancelRecording {
    if (!_eventMonitor) return;
    [NSEvent removeMonitor:_eventMonitor];
    _eventMonitor = nil;
    self.recorder.title = self.shortcutTitle ?: @"Fn";
    if (self.recordingChanged) self.recordingChanged(NO);
}
- (void)finishKeyCode:(NSInteger)keyCode modifiers:(NSEventModifierFlags)flags title:(NSString *)title {
    self.shortcutTitle = title;
    if (self.shortcutChanged) self.shortcutChanged(keyCode, flags, title);
    [self cancelRecording];
}
- (void)clearShortcut:(id)sender {
    [self cancelRecording];
    self.shortcutTitle = @"None";
    self.recorder.title = self.shortcutTitle;
    if (self.shortcutChanged) self.shortcutChanged(-1, 0, self.shortcutTitle);
}
- (void)resetShortcut:(id)sender {
    [self cancelRecording];
    self.shortcutTitle = @"Fn";
    self.recorder.title = self.shortcutTitle;
    if (self.shortcutChanged) self.shortcutChanged(-1, NSEventModifierFlagFunction, self.shortcutTitle);
}
- (void)toggleRecording:(id)sender {
    if (_eventMonitor) { [self cancelRecording]; return; }
    _recordedFlags = 0;
    self.recorder.title = @"Press keys…";
    if (self.recordingChanged) self.recordingChanged(YES);
    __weak SettingsController *weakSelf = self;
    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskFlagsChanged
        handler:^NSEvent *(NSEvent *event) {
            SettingsController *self = weakSelf;
            if (!self || !self.window.keyWindow) return event;
            if (event.type == NSEventTypeKeyDown) {
                if (event.keyCode == 53) { [self cancelRecording]; return nil; }
                if (event.isARepeat) return nil;
                NSEventModifierFlags flags = shortcutFlags(event.modifierFlags);
                // Arrow/function keys also carry the Function flag without a physical Fn press.
                if (!(self->_recordedFlags & NSEventModifierFlagFunction)) flags &= ~NSEventModifierFlagFunction;
                NSString *title = [modifierTitle(flags) stringByAppendingString:keyTitle(event)];
                [self finishKeyCode:event.keyCode modifiers:flags title:title];
            } else {
                NSEventModifierFlags flags = shortcutFlags(event.modifierFlags);
                if (flags) self->_recordedFlags |= flags;
                else if (self->_recordedFlags) {
                    [self finishKeyCode:-1 modifiers:self->_recordedFlags title:modifierTitle(self->_recordedFlags)];
                }
            }
            return nil;
        }];
}
- (void)windowDidResignKey:(NSNotification *)notification { [self cancelRecording]; }
- (void)windowWillClose:(NSNotification *)notification {
    [self cancelRecording];
    [self.activeColorWell deactivate];
    [NSColorPanel.sharedColorPanel orderOut:nil];
}
- (void)dealloc { if (_eventMonitor) [NSEvent removeMonitor:_eventMonitor]; }
@end
