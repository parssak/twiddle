#import "SettingsController.h"
#import "DiscoOverlay.h"
#import "FilterKnob.h"
#import <ServiceManagement/ServiceManagement.h>
#import <QuartzCore/QuartzCore.h>

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

@interface SettingsNavigationTable : NSTableView
@end
@implementation SettingsNavigationTable
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

@interface DiscoWordmarkView : NSControl
@property (nonatomic, strong) NSImage *image;
@property (copy) void (^hoverChanged)(BOOL hovered);
- (void)resetEasterEgg;
@end
static const CGFloat WordmarkLetterBoundaries[] = {0, .119, .355, .411, .583, .755, .834, 1};
@implementation DiscoWordmarkView {
    CALayer *_fillLayer;
    CALayer *_maskLayer;
    NSMutableArray<CALayer *> *_letterLayers;
    NSMutableArray<CALayer *> *_letterMasks;
    NSTrackingArea *_trackingArea;
    NSTimer *_letterTimer;
    BOOL _hovered;
    BOOL _effectActive;
    NSUInteger _visitedLetters;
    NSInteger _highlightedLetter;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        _fillLayer = [CALayer layer];
        _maskLayer = [CALayer layer];
        _maskLayer.contentsGravity = kCAGravityResizeAspect;
        _fillLayer.mask = _maskLayer;
        [self.layer addSublayer:_fillLayer];
        _letterLayers = [NSMutableArray new];
        _letterMasks = [NSMutableArray new];
        _highlightedLetter = -1;
        for (NSUInteger i = 0; i < 7; i++) {
            CALayer *letter = [CALayer layer];
            CALayer *mask = [CALayer layer];
            mask.contentsGravity = kCAGravityResizeAspect;
            letter.mask = mask;
            letter.opacity = 0;
            [self.layer addSublayer:letter];
            [_letterLayers addObject:letter];
            [_letterMasks addObject:mask];
        }
        self.toolTip = @"Check for updates";
        [self updateWordmarkColor];
    }
    return self;
}
- (void)dealloc { [_letterTimer invalidate]; }
- (void)setImage:(NSImage *)image {
    _image = image;
    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef cgImage = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    _maskLayer.contents = (__bridge id)cgImage;
    for (CALayer *mask in _letterMasks) mask.contents = (__bridge id)cgImage;
}
- (void)layout {
    [super layout];
    _fillLayer.frame = self.bounds;
    _maskLayer.frame = self.bounds;
    for (NSUInteger i = 0; i < _letterLayers.count; i++) {
        CGFloat x = NSWidth(self.bounds) * WordmarkLetterBoundaries[i];
        CGFloat maxX = NSWidth(self.bounds) * WordmarkLetterBoundaries[i + 1];
        CALayer *letter = _letterLayers[i];
        CALayer *mask = _letterMasks[i];
        letter.frame = CGRectMake(x, 0, maxX - x, NSHeight(self.bounds));
        mask.frame = CGRectMake(-x, 0, NSWidth(self.bounds), NSHeight(self.bounds));
    }
    CGFloat scale = self.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
    _fillLayer.contentsScale = scale;
    _maskLayer.contentsScale = scale;
    for (CALayer *layer in _letterLayers) layer.contentsScale = scale;
    for (CALayer *mask in _letterMasks) mask.contentsScale = scale;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways |
            NSTrackingInVisibleRect | NSTrackingEnabledDuringMouseDrag
        owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}
- (void)updateWordmarkColor {
    NSString *appearance = [self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    NSColor *base = dark ? NSColor.secondaryLabelColor : NSColor.blackColor;
    [CATransaction begin];
    CATransaction.disableActions = YES;
    _fillLayer.backgroundColor = base.CGColor;
    [CATransaction commit];
}
- (void)randomizeLetterColors {
    static NSArray<NSColor *> *palette;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        palette = @[NSColor.systemRedColor, NSColor.systemOrangeColor,
            NSColor.systemYellowColor, NSColor.systemGreenColor,
            NSColor.systemTealColor, NSColor.systemBlueColor,
            NSColor.systemPurpleColor, NSColor.systemPinkColor];
    });
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.18 + arc4random_uniform(18) / 100.0];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    for (CALayer *letter in _letterLayers) {
        BOOL lightUp = arc4random_uniform(100) < 48;
        letter.backgroundColor = palette[arc4random_uniform((uint32_t)palette.count)].CGColor;
        letter.opacity = lightUp ? 0.82 + arc4random_uniform(19) / 100.0 : 0;
        letter.shadowOpacity = lightUp ? 0.12 : 0;
        letter.shadowRadius = lightUp ? 3 : 0;
    }
    [CATransaction commit];
}
- (void)startLetterDisco {
    [_letterTimer invalidate];
    __weak DiscoWordmarkView *weakSelf = self;
    _letterTimer = [NSTimer timerWithTimeInterval:0.22 repeats:YES block:^(NSTimer *timer) {
        [weakSelf randomizeLetterColors];
    }];
    [NSRunLoop.mainRunLoop addTimer:_letterTimer forMode:NSRunLoopCommonModes];
}
- (void)stopLetterDisco {
    [_letterTimer invalidate];
    _letterTimer = nil;
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.28];
    for (CALayer *letter in _letterLayers) {
        letter.opacity = 0;
        letter.shadowOpacity = 0;
        letter.shadowRadius = 0;
    }
    [CATransaction commit];
}
- (NSInteger)letterAtPoint:(NSPoint)point {
    CGFloat position = point.x / MAX(NSWidth(self.bounds), 1);
    for (NSInteger i = 0; i < 7; i++) {
        if (position >= WordmarkLetterBoundaries[i] &&
            position < WordmarkLetterBoundaries[i + 1]) return i;
    }
    return position == 1 ? 6 : -1;
}
- (void)highlightLetter:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_letterLayers.count || _effectActive) return;
    _highlightedLetter = index;
    _visitedLetters |= 1u << index;
    static NSArray<NSColor *> *palette;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        palette = @[NSColor.systemRedColor, NSColor.systemOrangeColor,
            NSColor.systemYellowColor, NSColor.systemGreenColor,
            NSColor.systemTealColor, NSColor.systemBlueColor,
            NSColor.systemPurpleColor, NSColor.systemPinkColor];
    });
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.16];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    for (NSInteger i = 0; i < (NSInteger)_letterLayers.count; i++) {
        CALayer *letter = _letterLayers[i];
        BOOL visited = (_visitedLetters & (1u << i)) != 0;
        if (i == index && letter.opacity < .01) {
            NSColor *color = palette[arc4random_uniform((uint32_t)palette.count)];
            letter.backgroundColor = color.CGColor;
            letter.shadowColor = color.CGColor;
        }
        letter.opacity = visited ? 1 : 0;
        letter.shadowOpacity = i == index ? 0.16 : 0;
        letter.shadowRadius = i == index ? 3 : 0;
    }
    [CATransaction commit];
    if (_visitedLetters == 0x7f) {
        _effectActive = YES;
        [self startLetterDisco];
        if (self.hoverChanged) self.hoverChanged(YES);
    }
}
- (void)resetEasterEgg {
    _effectActive = NO;
    _visitedLetters = 0;
    _highlightedLetter = -1;
    [self stopLetterDisco];
}
- (void)mouseEntered:(NSEvent *)event {
    [NSCursor.pointingHandCursor set];
    _hovered = YES;
    [self highlightLetter:[self letterAtPoint:[self convertPoint:event.locationInWindow fromView:nil]]];
}
- (void)mouseMoved:(NSEvent *)event {
    NSInteger letter = [self letterAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (letter == _highlightedLetter) return;
    [self highlightLetter:letter];
}
- (void)mouseExited:(NSEvent *)event {
    [NSCursor.arrowCursor set];
    _hovered = NO;
    _highlightedLetter = -1;
    if (!_effectActive) [self resetEasterEgg];
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event {
    BOOL effectWasActive = _effectActive;
    BOOL dragged = NO;
    self.alphaValue = .72;
    NSEvent *next = nil;
    while ((next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp])) {
        if (next.type == NSEventTypeLeftMouseUp) break;
        dragged = YES;
        NSPoint point = [self convertPoint:next.locationInWindow fromView:nil];
        [self highlightLetter:[self letterAtPoint:point]];
    }
    self.alphaValue = 1;
    if (!next || next.type != NSEventTypeLeftMouseUp) return;
    NSPoint point = [self convertPoint:next.locationInWindow fromView:nil];
    if (!NSPointInRect(point, self.bounds)) return;
    if (effectWasActive) {
        if (self.hoverChanged) self.hoverChanged(NO);
        [self resetEasterEgg];
    } else if (!dragged) {
        [self sendAction:self.action to:self.target];
    }
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateWordmarkColor];
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityButtonRole; }
- (NSString *)accessibilityLabel { return @"Twiddle"; }
- (NSString *)accessibilityHelp { return @"Hover for the disco effect. Click to check for updates."; }
- (BOOL)accessibilityPerformPress { [self sendAction:self.action to:self.target]; return YES; }
@end

@interface SettingsController () <NSTableViewDataSource, NSTableViewDelegate> {
    id _eventMonitor;
    NSEventModifierFlags _recordedFlags;
    NSEvent *_recordedKey;
    BOOL _checkingForUpdates;
}
@property (weak) NSColorWell *activeColorWell;
@property NSSwitch *microphoneSwitch;
@property NSPopUpButton *microphonePicker;
@property FilterKnob *presetKnob;
@property NSTextField *presetReadout;
@property NSButton *menuBarSettingsButton;
@property NSSwitch *loginSwitch;
@property NSSwitch *hapticsSwitch;
@property NSButton *recorder;
@property NSPopUpButton *appPicker;
@property NSTableView *sidebarTable;
@property NSArray<NSView *> *pages;
@property NSArray<NSDictionary<NSString *, NSString *> *> *pageItems;
@property DiscoOverlayController *discoOverlay;
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
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 688, 400)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        self.discoOverlay = [DiscoOverlayController new];
        panel.title = @"Twiddle Settings";
        panel.titleVisibility = NSWindowTitleHidden;
        panel.titlebarAppearsTransparent = YES;
        panel.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        panel.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TwiddleSettings"];
        panel.toolbarStyle = NSWindowToolbarStyleUnified;
        panel.floatingPanel = YES;
        panel.backgroundColor = NSColor.windowBackgroundColor;
        panel.contentMinSize = NSMakeSize(688, 400);
        panel.hidesOnDeactivate = NO;
        panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
        panel.delegate = self;
        panel.releasedWhenClosed = NO;
        NSSplitViewController *splitController = [NSSplitViewController new];
        splitController.splitView.vertical = YES;
        splitController.splitView.dividerStyle = NSSplitViewDividerStyleThin;
        NSViewController *sidebarController = [NSViewController new];
        NSVisualEffectView *sidebar = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 190, 400)];
        sidebar.material = NSVisualEffectMaterialSidebar;
        sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        sidebarController.view = sidebar;
        NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
        sidebarItem.minimumThickness = 190;
        sidebarItem.maximumThickness = 190;
        sidebarItem.canCollapse = NO;
        sidebarItem.allowsFullHeightLayout = YES;
        [splitController addSplitViewItem:sidebarItem];
        NSURL *wordmarkURL = [NSBundle.mainBundle URLForResource:@"TwiddleWordmark" withExtension:@"svg"];
        NSImage *wordmark = wordmarkURL ? [[NSImage alloc] initWithContentsOfURL:wordmarkURL] : nil;
        if (wordmark) {
            wordmark.template = YES;
            // The SVG includes a small transparent inset; offset its frame so the
            // visible wordmark aligns with the source-list selection's left edge.
            DiscoWordmarkView *wordmarkView = [[DiscoWordmarkView alloc] initWithFrame:NSMakeRect(14, 328, 92, 22)];
            wordmarkView.image = wordmark;
            wordmarkView.target = self;
            wordmarkView.action = @selector(checkForUpdates:);
            __weak SettingsController *weakSelf = self;
            wordmarkView.hoverChanged = ^(BOOL hovered) {
                if (hovered) [weakSelf.discoOverlay show];
                else [weakSelf.discoOverlay hide];
            };
            __weak DiscoWordmarkView *weakWordmark = wordmarkView;
            self.discoOverlay.cancelHandler = ^{ [weakWordmark resetEasterEgg]; };
            wordmarkView.autoresizingMask = NSViewMinYMargin;
            [sidebar addSubview:wordmarkView];
            NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            if (version.length) {
                NSTextField *versionLabel = [NSTextField labelWithString:[@"v" stringByAppendingString:version]];
                versionLabel.font = [NSFont systemFontOfSize:9];
                versionLabel.textColor = NSColor.tertiaryLabelColor;
                versionLabel.accessibilityLabel = [@"Version " stringByAppendingString:version];
                [versionLabel sizeToFit];
                [versionLabel setFrameOrigin:NSMakePoint(111, 328)];
                versionLabel.autoresizingMask = NSViewMinYMargin;
                [sidebar addSubview:versionLabel];
            }
        }
        // Fill the sidebar below the wordmark; future settings pages scroll naturally.
        NSScrollView *navigation = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 190, 310)];
        navigation.autoresizingMask = NSViewHeightSizable;
        navigation.drawsBackground = NO;
        self.sidebarTable = [[SettingsNavigationTable alloc] initWithFrame:navigation.bounds];
        self.pageItems = @[
            @{@"title": @"General", @"symbol": @"gearshape"},
            @{@"title": @"Automatic Preset", @"symbol": @"waveform"},
        ];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"page"];
        column.width = 170;
        [self.sidebarTable addTableColumn:column];
        self.sidebarTable.headerView = nil;
        self.sidebarTable.style = NSTableViewStyleSourceList;
        self.sidebarTable.rowHeight = 32;
        self.sidebarTable.intercellSpacing = NSMakeSize(0, 4);
        self.sidebarTable.backgroundColor = NSColor.clearColor;
        self.sidebarTable.allowsEmptySelection = NO;
        self.sidebarTable.dataSource = self;
        self.sidebarTable.delegate = self;
        self.sidebarTable.accessibilityLabel = @"Settings categories";
        navigation.documentView = self.sidebarTable;
        [sidebar addSubview:navigation];
        NSViewController *detailController = [NSViewController new];
        NSView *detail = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 490, 400)];
        detailController.view = detail;
        NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailController];
        detailItem.minimumThickness = 490;
        [splitController addSplitViewItem:detailItem];
        NSView *pageContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 490, 400)];
        pageContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [detail addSubview:pageContainer];
        NSView *generalPage = [[NSView alloc] initWithFrame:pageContainer.bounds];
        NSView *automaticPage = [[NSView alloc] initWithFrame:pageContainer.bounds];
        generalPage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        automaticPage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [pageContainer addSubview:generalPage];
        [pageContainer addSubview:automaticPage];
        self.pages = @[generalPage, automaticPage];
        NSBox *generalGroup = [[NSBox alloc] initWithFrame:NSMakeRect(28, 100, 434, 256)];
        NSBox *automaticGroup = [[NSBox alloc] initWithFrame:NSMakeRect(28, 30, 434, 326)];
        generalGroup.titlePosition = NSNoTitle;
        automaticGroup.titlePosition = NSNoTitle;
        [generalPage addSubview:generalGroup];
        [automaticPage addSubview:automaticGroup];
        for (NSNumber *y in @[@302, @252, @202, @152]) {
            NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(48, y.doubleValue, 394, 1)];
            divider.boxType = NSBoxSeparator;
            [generalPage addSubview:divider];
        }
        for (NSNumber *y in @[@302, @252, @202]) {
            NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(48, y.doubleValue, 394, 1)];
            divider.boxType = NSBoxSeparator;
            [automaticPage addSubview:divider];
        }
        NSArray *generalTitles = @[@"Menu Bar icon", @"Open at Login", @"Trackpad Haptics", @"Default app", @"Filter colors"];
        NSArray *generalCenters = @[@327, @277, @227, @177, @127];
        for (NSUInteger i = 0; i < generalTitles.count; i++) {
            NSTextField *label = [NSTextField labelWithString:generalTitles[i]];
            label.font = [NSFont systemFontOfSize:13];
            label.frame = NSMakeRect(48, [generalCenters[i] doubleValue] - 9, 190, 18);
            [generalPage addSubview:label];
        }
        NSArray *automaticTitles = @[@"Apply when mic is active", @"Microphone app", @"Hold shortcut", @"Filter to apply"];
        NSArray *automaticCenters = @[@327, @277, @227, @128];
        for (NSUInteger i = 0; i < automaticTitles.count; i++) {
            NSTextField *label = [NSTextField labelWithString:automaticTitles[i]];
            label.font = [NSFont systemFontOfSize:13];
            label.frame = NSMakeRect(48, [automaticCenters[i] doubleValue] - 9, i ? 170 : 230, 18);
            [automaticPage addSubview:label];
        }
        self.menuBarSettingsButton = [NSButton buttonWithTitle:@"Open Settings…" target:self action:@selector(requestMenuBarSettings:)];
        self.menuBarSettingsButton.frame = NSMakeRect(320, 311, 122, 32);
        self.menuBarSettingsButton.bezelStyle = NSBezelStyleRounded;
        self.menuBarSettingsButton.controlSize = NSControlSizeSmall;
        self.menuBarSettingsButton.accessibilityLabel = @"Open Menu Bar Settings";
        [generalPage addSubview:self.menuBarSettingsButton];
        self.loginSwitch = [NSSwitch new];
        self.loginSwitch.target = self;
        self.loginSwitch.action = @selector(toggleLogin:);
        self.loginSwitch.accessibilityLabel = @"Open at Login";
        self.hapticsSwitch = [NSSwitch new];
        self.hapticsSwitch.target = self;
        self.hapticsSwitch.action = @selector(toggleHaptics:);
        self.hapticsSwitch.accessibilityLabel = @"Trackpad Haptics";
        self.microphoneSwitch = [NSSwitch new];
        self.microphoneSwitch.target = self;
        self.microphoneSwitch.action = @selector(toggleMicrophone:);
        self.microphoneSwitch.accessibilityLabel = @"Apply when mic is active";
        self.microphoneSwitch.toolTip = @"Use the preset while the selected apps have an active audio input.";
        NSArray<NSSwitch *> *switches = @[self.loginSwitch, self.hapticsSwitch];
        NSArray *switchCenters = @[@277, @227];
        for (NSUInteger i = 0; i < switches.count; i++) {
            NSSwitch *control = switches[i];
            [control sizeToFit];
            [control setFrameOrigin:NSMakePoint(442 - NSWidth(control.frame), [switchCenters[i] doubleValue] - NSHeight(control.frame) / 2)];
            [generalPage addSubview:control];
        }
        [self.microphoneSwitch sizeToFit];
        [self.microphoneSwitch setFrameOrigin:NSMakePoint(442 - NSWidth(self.microphoneSwitch.frame), 327 - NSHeight(self.microphoneSwitch.frame) / 2)];
        [automaticPage addSubview:self.microphoneSwitch];
        self.appPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(270, 161, 172, 32) pullsDown:NO];
        self.appPicker.bordered = NO;
        self.appPicker.target = self;
        self.appPicker.action = @selector(chooseApp:);
        self.appPicker.accessibilityLabel = @"Default app";
        [generalPage addSubview:self.appPicker];
        self.microphonePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(270, 261, 172, 32) pullsDown:NO];
        self.microphonePicker.bordered = NO;
        [self.microphonePicker addItemsWithTitles:@[@"Any app", @"Wispr Flow"]];
        self.microphonePicker.target = self;
        self.microphonePicker.action = @selector(chooseMicrophoneApp:);
        self.microphonePicker.accessibilityLabel = @"Microphone app";
        [automaticPage addSubview:self.microphonePicker];
        for (NSUInteger i = 0; i < 2; i++) {
            NSTextField *label = [NSTextField labelWithString:i ? @"High" : @"Low"];
            label.font = [NSFont systemFontOfSize:11];
            label.textColor = NSColor.secondaryLabelColor;
            label.frame = NSMakeRect(270 + i * 86, 119, 32, 16);
            [generalPage addSubview:label];
            NSColorWell *well = [[FilterColorWell alloc] initWithFrame:NSMakeRect(308 + i * 88, 115, 28, 24)];
            well.colorWellStyle = NSColorWellStyleMinimal;
            well.supportsAlpha = NO;
            well.pulldownTarget = self;
            well.pulldownAction = @selector(openColorPicker:);
            well.color = i ? FilterKnob.highColor : FilterKnob.lowColor;
            well.tag = i;
            well.target = self;
            well.action = @selector(changeColor:);
            well.accessibilityLabel = i ? @"High-pass color" : @"Low-pass color";
            [generalPage addSubview:well];
        }
        NSColorPanel.sharedColorPanel.showsAlpha = NO;
        self.recorder = [NSButton buttonWithTitle:@"None" target:self action:@selector(toggleRecording:)];
        self.recorder.frame = NSMakeRect(246, 211, 164, 32);
        self.recorder.bezelStyle = NSBezelStyleRounded;
        self.recorder.toolTip = @"Click to record. Press Escape to cancel. The shortcut also reaches other apps.";
        self.recorder.accessibilityLabel = @"Record hold shortcut";
        [automaticPage addSubview:self.recorder];
        NSButton *clear = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:nil]
            target:self action:@selector(clearShortcut:)];
        clear.frame = NSMakeRect(414, 211, 28, 32);
        clear.bordered = NO;
        clear.contentTintColor = NSColor.secondaryLabelColor;
        clear.toolTip = @"Clear hold shortcut";
        clear.accessibilityLabel = clear.toolTip;
        [automaticPage addSubview:clear];
        NSButton *resetFilter = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.counterclockwise" accessibilityDescription:nil]
            target:self action:@selector(resetPreset:)];
        resetFilter.frame = NSMakeRect(170, 101, 24, 28);
        resetFilter.bordered = NO;
        resetFilter.contentTintColor = NSColor.secondaryLabelColor;
        resetFilter.toolTip = @"Reset filter to apply to 1100 Hz";
        resetFilter.accessibilityLabel = resetFilter.toolTip;
        [automaticPage addSubview:resetFilter];
        self.presetKnob = [[FilterKnob alloc] initWithFrame:NSMakeRect(282, 46, 152, 144)];
        self.presetKnob.enabled = YES;
        self.presetKnob.target = self;
        self.presetKnob.action = @selector(changePreset:);
        self.presetKnob.resetAction = @selector(resetPreset:);
        self.presetKnob.accessibilityLabel = @"Filter applied by shortcut or microphone";
        [automaticPage addSubview:self.presetKnob];
        self.presetReadout = [NSTextField labelWithString:@""];
        self.presetReadout.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
        self.presetReadout.textColor = NSColor.secondaryLabelColor;
        self.presetReadout.alignment = NSTextAlignmentLeft;
        // Keep the label's hit-test bounds clear of the adjacent reset button.
        self.presetReadout.frame = NSMakeRect(48, 104, 112, 16);
        [automaticPage addSubview:self.presetReadout];
        for (NSView *page in self.pages) {
            for (NSView *view in page.subviews) {
                view.autoresizingMask = NSViewMinYMargin;
                if ([view isKindOfClass:NSBox.class]) {
                    view.autoresizingMask |= NSViewWidthSizable;
                } else if (NSMinX(view.frame) >= 246) {
                    view.autoresizingMask |= NSViewMinXMargin;
                }
            }
        }
        NSString *creditText = @"Made with ❤️ by Parssa Kyanzadeh";
        NSMutableParagraphStyle *creditStyle = [NSMutableParagraphStyle new];
        creditStyle.alignment = NSTextAlignmentCenter;
        NSMutableAttributedString *credit = [[NSMutableAttributedString alloc] initWithString:creditText attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
            NSParagraphStyleAttributeName: creditStyle,
        }];
        NSRange nameRange = [creditText rangeOfString:@"Parssa Kyanzadeh"];
        [credit addAttributes:@{
            NSLinkAttributeName: [NSURL URLWithString:@"https://parssak.com"],
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone),
        } range:nameRange];
        NSTextView *creditLabel = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 20, 490, 16)];
        [creditLabel.textStorage setAttributedString:credit];
        creditLabel.alignment = NSTextAlignmentCenter;
        creditLabel.drawsBackground = NO;
        creditLabel.editable = NO;
        creditLabel.selectable = YES;
        creditLabel.textContainerInset = NSZeroSize;
        creditLabel.textContainer.lineFragmentPadding = 0;
        creditLabel.linkTextAttributes = @{
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone),
        };
        creditLabel.accessibilityLabel = @"Made with love by Parssa Kyanzadeh";
        creditLabel.autoresizingMask = NSViewWidthSizable;
        [generalPage addSubview:creditLabel];
        panel.contentViewController = splitController;
        [panel setContentSize:NSMakeSize(688, 400)];
        NSInteger savedPage = [NSUserDefaults.standardUserDefaults integerForKey:@"settingsPage"];
        [self setSettingsPage:(savedPage >= 0 && savedPage < (NSInteger)self.pages.count) ? savedPage : 0];
        [panel makeFirstResponder:self.sidebarTable];
        [panel center];
    }
    return self;
}
- (void)setSettingsPage:(NSInteger)page {
    for (NSInteger i = 0; i < (NSInteger)self.pages.count; i++) {
        self.pages[i].hidden = i != page;
    }
    [self.sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:page] byExtendingSelection:NO];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.pageItems.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary<NSString *, NSString *> *item = self.pageItems[row];
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 156, 32)];
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(4, 7, 18, 18)];
    icon.image = [NSImage imageWithSystemSymbolName:item[@"symbol"] accessibilityDescription:nil];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    [cell addSubview:icon];
    cell.imageView = icon;
    NSTextField *label = [NSTextField labelWithString:item[@"title"]];
    label.font = [NSFont systemFontOfSize:13];
    label.frame = NSMakeRect(30, 7, 122, 18);
    [cell addSubview:label];
    cell.textField = label;
    return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger page = self.sidebarTable.selectedRow;
    if (page < 0) return;
    [self cancelRecording];
    for (NSInteger i = 0; i < (NSInteger)self.pages.count; i++) self.pages[i].hidden = i != page;
    [NSUserDefaults.standardUserDefaults setInteger:page forKey:@"settingsPage"];
}
- (void)checkForUpdates:(id)sender {
    if (_checkingForUpdates) return;
    _checkingForUpdates = YES;
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/parssak/twiddle/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSString *current = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
    [request setValue:[@"Twiddle/" stringByAppendingString:current] forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    __weak SettingsController *weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:
        ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
        NSError *jsonError = nil;
        NSDictionary *payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
        NSString *tag = [payload isKindOfClass:NSDictionary.class] ? payload[@"tag_name"] : nil;
        NSString *releasePage = [payload isKindOfClass:NSDictionary.class] ? payload[@"html_url"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            SettingsController *self = weakSelf;
            if (!self) return;
            self->_checkingForUpdates = NO;
            NSAlert *alert = [NSAlert new];
            if (error || http.statusCode != 200 || !tag.length) {
                alert.messageText = @"Couldn’t check for updates";
                alert.informativeText = error.localizedDescription ?: jsonError.localizedDescription ?:
                    @"GitHub didn’t return a release. Try again in a moment.";
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
                return;
            }
            NSString *latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
            if ([latest compare:current options:NSNumericSearch] == NSOrderedDescending) {
                alert.messageText = [NSString stringWithFormat:@"Twiddle %@ is available", tag];
                alert.informativeText = [NSString stringWithFormat:@"You’re currently using v%@.", current];
                [alert addButtonWithTitle:@"Download"];
                [alert addButtonWithTitle:@"Later"];
                [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
                    if (result != NSAlertFirstButtonReturn) return;
                    NSURL *downloadURL = [NSURL URLWithString:releasePage ?: @"https://github.com/parssak/twiddle/releases/latest"];
                    [NSWorkspace.sharedWorkspace openURL:downloadURL];
                }];
            } else {
                alert.messageText = @"Twiddle is up to date";
                alert.informativeText = [NSString stringWithFormat:@"You’re using the latest version, v%@.", current];
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
            }
        });
    }] resume];
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
    self.presetValue = [FilterKnob defaultPresetValue];
    if (self.presetChanged) self.presetChanged(self.presetValue);
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
- (void)toggleMicrophone:(NSSwitch *)sender {
    [self cancelRecording];
    BOOL enabled = sender.state == NSControlStateValueOn;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"microphoneEnabled"];
    [self refreshSwitches];
    if (self.microphoneChanged) self.microphoneChanged();
}
- (void)chooseMicrophoneApp:(NSPopUpButton *)sender {
    [self cancelRecording];
    [NSUserDefaults.standardUserDefaults setObject:sender.indexOfSelectedItem == 0 ? @"any" : @"wispr" forKey:@"microphoneScope"];
    if (self.microphoneChanged) self.microphoneChanged();
}
- (void)show {
    [self cancelRecording];
    [self refreshSwitches];
    self.recorder.title = self.shortcutTitle ?: @"None";
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
    self.microphoneSwitch.state = [NSUserDefaults.standardUserDefaults boolForKey:@"microphoneEnabled"] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.microphonePicker selectItemAtIndex:[[NSUserDefaults.standardUserDefaults stringForKey:@"microphoneScope"] isEqualToString:@"any"] ? 0 : 1];
    self.microphonePicker.enabled = self.microphoneSwitch.state == NSControlStateValueOn;
}
- (void)requestMenuBarSettings:(id)sender {
    [self cancelRecording];
    if (self.menuBarSettingsRequested) self.menuBarSettingsRequested();
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
    _recordedKey = nil;
    self.recorder.title = self.shortcutTitle ?: @"None";
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
- (void)toggleRecording:(id)sender {
    if (_eventMonitor) { [self cancelRecording]; return; }
    _recordedFlags = 0;
    self.recorder.title = @"Press keys…";
    if (self.recordingChanged) self.recordingChanged(YES);
    __weak SettingsController *weakSelf = self;
    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged
        handler:^NSEvent *(NSEvent *event) {
            SettingsController *self = weakSelf;
            if (!self || !self.window.keyWindow) return event;
            if (event.type == NSEventTypeKeyDown) {
                if (event.keyCode == 53) { [self cancelRecording]; return nil; }
                if (event.isARepeat || self->_recordedKey) return nil;
                NSEventModifierFlags flags = shortcutFlags(event.modifierFlags);
                // Arrow/function keys also carry the Function flag without a physical Fn press.
                if (!(self->_recordedFlags & NSEventModifierFlagFunction)) flags &= ~NSEventModifierFlagFunction;
                self->_recordedKey = event;
                self->_recordedFlags = flags;
                self.recorder.title = [modifierTitle(flags) stringByAppendingString:keyTitle(event)];
                // Keep consuming repeats until release so recording cannot leak
                // an unhandled key into the window and play the alert sound.
            } else if (event.type == NSEventTypeKeyUp) {
                if (self->_recordedKey && event.keyCode == self->_recordedKey.keyCode)
                    [self finishKeyCode:event.keyCode modifiers:self->_recordedFlags title:self.recorder.title];
            } else if (!self->_recordedKey) {
                NSEventModifierFlags flags = shortcutFlags(event.modifierFlags);
                if (flags) self->_recordedFlags |= flags;
                else if (self->_recordedFlags) {
                    [self finishKeyCode:-1 modifiers:self->_recordedFlags title:modifierTitle(self->_recordedFlags)];
                }
            }
            return nil;
        }];
}
- (void)windowDidResignKey:(NSNotification *)notification {
    [self cancelRecording];
}
- (void)windowWillClose:(NSNotification *)notification {
    [self cancelRecording];
    [self.discoOverlay cancel];
    [self.activeColorWell deactivate];
    [NSColorPanel.sharedColorPanel orderOut:nil];
}
- (void)dealloc { if (_eventMonitor) [NSEvent removeMonitor:_eventMonitor]; }
@end
