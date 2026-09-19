#import "SettingsLayout.h"
#import "CreditView.h"
#import "HoverButton.h"
#import "UpdateChecker.h"
#import "ShortcutRecorder.h"
#import "DiscoWordmarkView.h"
#import "AppGridView.h"
#import "SettingsController.h"
#import "DiscoOverlay.h"
#import "FilterKnob.h"
#import <ServiceManagement/ServiceManagement.h>
#import <QuartzCore/QuartzCore.h>

@interface SettingsController () <NSTableViewDataSource, NSTableViewDelegate>
@property NSSwitch *microphoneSwitch;
@property NSPopUpButton *microphonePicker;
@property FilterKnob *presetKnob;
@property NSTextField *presetReadout;
@property NSButton *menuBarSettingsButton;
@property NSButton *shortcutAccessButton;
@property NSSwitch *loginSwitch;
@property NSSwitch *hapticsSwitch;
@property ShortcutRecorder *recorder;
@property NSArray<AppGridView *> *appLists;
@property NSTableView *sidebarTable;
@property NSArray<NSView *> *pages;
@property NSScrollView *pageScroll;
@property NSArray<NSDictionary<NSString *, NSString *> *> *pageItems;
@property DiscoOverlayController *discoOverlay;
@property UpdateChecker *updateChecker;
@end

@implementation SettingsController
- (instancetype)init {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 688, 400)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        self.discoOverlay = [DiscoOverlayController new];
        __weak SettingsController *weakSettings = self;
        self.discoOverlay.activeChanged = ^(BOOL active) {
            if (weakSettings.discoChanged) weakSettings.discoChanged(active);
        };
        self.updateChecker = [UpdateChecker new];
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
            @{@"title": @"Auto-apply", @"symbol": @"waveform"},
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
        self.pageScroll = [[NSScrollView alloc] initWithFrame:detail.bounds];
        self.pageScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.pageScroll.drawsBackground = NO;
        self.pageScroll.automaticallyAdjustsContentInsets = NO;
        self.pageScroll.hasVerticalScroller = YES;
        self.pageScroll.scrollerStyle = NSScrollerStyleOverlay;
        [detail addSubview:self.pageScroll];
        NSView *pageContainer = [[SettingsPageDocument alloc] initWithFrame:NSMakeRect(0, 0, SettingsPageWidth, SettingsPageHeight)];
        pageContainer.autoresizingMask = NSViewWidthSizable;
        self.pageScroll.documentView = pageContainer;
        NSView *generalPage = [[NSView alloc] initWithFrame:pageContainer.bounds];
        NSView *automaticPage = [[NSView alloc] initWithFrame:pageContainer.bounds];
        generalPage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        automaticPage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [pageContainer addSubview:generalPage];
        [pageContainer addSubview:automaticPage];
        self.pages = @[generalPage, automaticPage];
        addSettingsCard(generalPage, 396, 200);
        addSettingsCard(generalPage, 234, 146);
        addSettingsCard(automaticPage, 430, 166);
        addSettingsCard(automaticPage, 306, 112);
        addSettingsCard(automaticPage, 232, 62);
        addSettingsCard(automaticPage, 74, 146);
        for (NSNumber *y in @[@546, @496, @446]) addSettingsSeparator(generalPage, y.doubleValue);
        addSettingsSeparator(automaticPage, 362);
        NSArray *generalTitles = @[@"Menu Bar icon", @"Open at Login", @"Trackpad Haptics", @"⌥F10–F12 shortcuts"];
        NSArray *generalCenters = @[@571, @521, @471, @421];
        for (NSUInteger i = 0; i < generalTitles.count; i++)
            addSettingsRowTitle(generalPage, generalTitles[i], [generalCenters[i] doubleValue], 190, NSFontWeightRegular);
        NSArray *automaticTitles = @[@"Apply when mic is active", @"Microphone app", @"Hold shortcut", @"Filter to apply"];
        NSArray *automaticCenters = @[@390, @334, @263, @531];
        for (NSUInteger i = 0; i < automaticTitles.count; i++)
            addSettingsRowTitle(automaticPage, automaticTitles[i], [automaticCenters[i] doubleValue],
                i ? 170 : 230, i == 3 ? NSFontWeightSemibold : NSFontWeightRegular);
        NSMutableArray *appLists = [NSMutableArray new];
        for (NSInteger i = 0; i < 2; i++) {
            NSView *page = i ? automaticPage : generalPage;
            CGFloat titleY = i ? 185 : 345;
            NSTextField *title = [NSTextField labelWithString:i ? @"Apps that trigger Twiddle" : @"Apps to Twiddle"];
            title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
            title.frame = NSMakeRect(SettingsContentInset, titleY, SettingsContentWidth - 70, 20);
            [page addSubview:title];
            NSTextField *hint = [NSTextField labelWithString:i ? @"Apply the filter while these apps play audio." : @"These apps’ audio gets filtered."];
            hint.font = [NSFont systemFontOfSize:11];
            hint.textColor = NSColor.secondaryLabelColor;
            hint.frame = NSMakeRect(SettingsContentInset, titleY - SettingsDescriptionOffset, SettingsContentWidth, 18);
            [page addSubview:hint];
            AppGridView *list = [[AppGridView alloc] initWithFrame:NSMakeRect(SettingsContentInset, titleY - 94, SettingsContentWidth, 70)];
            list.preferenceKey = i ? @"triggerBundles" : @"targetBundles";
            list.accessibilityLabel = title.stringValue;
            list.toolTip = @"Drag apps from Finder into this list, or use + Apps.";
            __weak SettingsController *weakSelf = self;
            list.changed = ^{ if (weakSelf.appsChanged) weakSelf.appsChanged(); };
            HoverButton *add = [[HoverButton alloc] initWithFrame:NSZeroRect];
            add.title = @"+ Apps";
            add.target = list;
            add.action = @selector(addApps:);
            add.frame = NSMakeRect(SettingsContentInset + SettingsContentWidth - 60, titleY - 2, 60, 24);
            add.autoresizingMask = NSViewMinXMargin;
            add.bordered = NO;
            add.font = [NSFont systemFontOfSize:12];
            add.contentTintColor = NSColor.secondaryLabelColor;
            add.accessibilityLabel = @"Add Apps";
            [page addSubview:add];
            [page addSubview:list];
            [appLists addObject:list];
        }
        self.appLists = appLists;
        self.menuBarSettingsButton = [NSButton buttonWithTitle:@"Open Settings…" target:self action:@selector(requestMenuBarSettings:)];
        self.menuBarSettingsButton.frame = NSMakeRect(320, 555, 122, 32);
        self.menuBarSettingsButton.bezelStyle = NSBezelStyleRounded;
        self.menuBarSettingsButton.controlSize = NSControlSizeSmall;
        self.menuBarSettingsButton.accessibilityLabel = @"Open Menu Bar Settings";
        [generalPage addSubview:self.menuBarSettingsButton];
        self.shortcutAccessButton = [NSButton buttonWithTitle:@"Allow Accessibility…" target:self action:@selector(requestShortcutAccess:)];
        self.shortcutAccessButton.frame = NSMakeRect(270, 405, 172, 32);
        self.shortcutAccessButton.bezelStyle = NSBezelStyleRounded;
        self.shortcutAccessButton.controlSize = NSControlSizeSmall;
        [generalPage addSubview:self.shortcutAccessButton];
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
        NSArray *switchCenters = @[@521, @471];
        for (NSUInteger i = 0; i < switches.count; i++) {
            NSSwitch *control = switches[i];
            [control sizeToFit];
            [control setFrameOrigin:NSMakePoint(442 - NSWidth(control.frame), [switchCenters[i] doubleValue] - NSHeight(control.frame) / 2)];
            [generalPage addSubview:control];
        }
        [self.microphoneSwitch sizeToFit];
        [self.microphoneSwitch setFrameOrigin:NSMakePoint(442 - NSWidth(self.microphoneSwitch.frame), 390 - NSHeight(self.microphoneSwitch.frame) / 2)];
        [automaticPage addSubview:self.microphoneSwitch];
        self.microphonePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(270, 318, 172, 32) pullsDown:NO];
        self.microphonePicker.bordered = NO;
        [self.microphonePicker addItemsWithTitles:@[@"Any app", @"Wispr Flow"]];
        self.microphonePicker.target = self;
        self.microphonePicker.action = @selector(chooseMicrophoneApp:);
        self.microphonePicker.accessibilityLabel = @"Microphone app";
        [automaticPage addSubview:self.microphonePicker];
        self.recorder = [[ShortcutRecorder alloc] initWithFrame:NSZeroRect];
        __weak SettingsController *weakSelf = self;
        self.recorder.shortcutChanged = ^(NSInteger keyCode, NSEventModifierFlags modifiers, NSString *title) {
            weakSelf.shortcutTitle = title;
            if (weakSelf.shortcutChanged) weakSelf.shortcutChanged(keyCode, modifiers, title);
        };
        self.recorder.recordingChanged = ^(BOOL recording) {
            if (weakSelf.recordingChanged) weakSelf.recordingChanged(recording);
        };
        self.recorder.frame = NSMakeRect(246, 247, 164, 32);
        self.recorder.bezelStyle = NSBezelStyleRounded;
        self.recorder.toolTip = @"Click to record. Press Escape to cancel. The shortcut also reaches other apps.";
        self.recorder.accessibilityLabel = @"Record hold shortcut";
        [automaticPage addSubview:self.recorder];
        NSButton *clear = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:nil]
            target:self.recorder action:@selector(clearShortcut:)];
        clear.frame = NSMakeRect(414, 247, 28, 32);
        clear.bordered = NO;
        clear.contentTintColor = NSColor.secondaryLabelColor;
        clear.toolTip = @"Clear hold shortcut";
        clear.accessibilityLabel = clear.toolTip;
        [automaticPage addSubview:clear];
        NSButton *resetFilter = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.counterclockwise" accessibilityDescription:nil]
            target:self action:@selector(resetPreset:)];
        resetFilter.frame = NSMakeRect(170, 497, 24, 28);
        resetFilter.bordered = NO;
        resetFilter.contentTintColor = NSColor.secondaryLabelColor;
        resetFilter.toolTip = @"Reset filter to apply to 1100 Hz";
        resetFilter.accessibilityLabel = resetFilter.toolTip;
        [automaticPage addSubview:resetFilter];
        self.presetKnob = [[FilterKnob alloc] initWithFrame:NSMakeRect(282, 438, 152, 144)];
        self.presetKnob.enabled = YES;
        self.presetKnob.target = self;
        self.presetKnob.action = @selector(changePreset:);
        self.presetKnob.resetAction = @selector(resetPreset:);
        self.presetKnob.accessibilityLabel = @"Preset applied by playback, shortcut, or microphone";
        [automaticPage addSubview:self.presetKnob];
        self.presetReadout = [NSTextField labelWithString:@""];
        self.presetReadout.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
        self.presetReadout.textColor = NSColor.secondaryLabelColor;
        self.presetReadout.alignment = NSTextAlignmentLeft;
        // Keep the label's hit-test bounds clear of the adjacent reset button.
        self.presetReadout.frame = NSMakeRect(SettingsContentInset, 500, 112, 16);
        [automaticPage addSubview:self.presetReadout];
        for (NSView *page in self.pages) {
            for (NSView *view in page.subviews) {
                view.autoresizingMask = NSViewMinYMargin;
                if ([view isKindOfClass:NSBox.class] || [view isKindOfClass:AppGridView.class]) {
                    view.autoresizingMask |= NSViewWidthSizable;
                } else if (NSMinX(view.frame) >= 246) {
                    view.autoresizingMask |= NSViewMinXMargin;
                }
            }
        }
        CreditView *credit = [[CreditView alloc] initWithFrame:NSMakeRect(0, 172, 490, 24)];
        credit.autoresizingMask = NSViewWidthSizable;
        [generalPage addSubview:credit];
        panel.contentViewController = splitController;
        [panel setContentSize:NSMakeSize(688, 600)];
        NSInteger savedPage = [NSUserDefaults.standardUserDefaults integerForKey:@"settingsPage"];
        [self setSettingsPage:(savedPage >= 0 && savedPage < (NSInteger)self.pages.count) ? savedPage : 0];
        [panel makeFirstResponder:self.sidebarTable];
        [panel center];
    }
    return self;
}
- (void)scrollPageToTop {
    NSView *document = self.pageScroll.documentView;
    [document scrollPoint:NSZeroPoint];
}
- (void)setSettingsPage:(NSInteger)page {
    for (NSInteger i = 0; i < (NSInteger)self.pages.count; i++) {
        self.pages[i].hidden = i != page;
    }
    [self.sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:page] byExtendingSelection:NO];
    [self scrollPageToTop];
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
    [self scrollPageToTop];
}
- (void)checkForUpdates:(id)sender { [self.updateChecker checkFromWindow:self.window]; }
- (void)setPresetValue:(double)value {
    _presetValue = isfinite(value) ? fmax(-1, fmin(1, value)) : 0;
    self.presetKnob.doubleValue = _presetValue;
    self.presetReadout.stringValue = [FilterKnob labelForValue:_presetValue];
}
- (void)setMenuBarItemVisible:(BOOL)visible {
    _menuBarItemVisible = visible;
    self.menuBarSettingsButton.title = visible ? @"Open Settings…" : @"Restore Icon";
    self.menuBarSettingsButton.accessibilityLabel = visible ? @"Open Menu Bar Settings" : @"Restore Twiddle to the Menu Bar";
}
- (void)changePreset:(id)sender {
    self.presetValue = self.presetKnob.doubleValue;
    if (self.presetChanged) self.presetChanged(self.presetValue);
}
- (void)resetPreset:(id)sender {
    self.presetValue = [FilterKnob defaultPresetValue];
    if (self.presetChanged) self.presetChanged(self.presetValue);
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
- (void)setDiscoEnabled:(BOOL)enabled {
    if (enabled) [self.discoOverlay show];
    else [self.discoOverlay cancel];
}
- (void)show {
    [self cancelRecording];
    [self refreshSwitches];
    self.recorder.shortcutTitle = self.shortcutTitle ?: @"None";
    for (AppGridView *list in self.appLists) [list reload];
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
    NSURL *wisprURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.electron.wispr-flow"];
    NSImage *wisprIcon = wisprURL ? [NSWorkspace.sharedWorkspace iconForFile:wisprURL.path] : nil;
    wisprIcon.size = NSMakeSize(20, 20);
    [self.microphonePicker itemAtIndex:1].image = wisprIcon;
    [self.microphonePicker selectItemAtIndex:[[NSUserDefaults.standardUserDefaults stringForKey:@"microphoneScope"] isEqualToString:@"any"] ? 0 : 1];
    self.microphonePicker.enabled = self.microphoneSwitch.state == NSControlStateValueOn;
}
- (void)updateShortcutAccess:(BOOL)granted ready:(BOOL)ready error:(NSString *)error {
    NSString *title = !granted ? @"Allow Accessibility…" : ready ? @"Enabled" : @"Retry Shortcuts";
    if (![self.shortcutAccessButton.title isEqualToString:title]) self.shortcutAccessButton.title = title;
    self.shortcutAccessButton.enabled = !granted || !ready;
    self.shortcutAccessButton.toolTip = !granted ? @"Enable Twiddle in Privacy & Security → Accessibility to use Option-F10, F11, and F12 on the media-key row." :
        ready ? @"Option-F10 toggles the filter; Option-F11 and Option-F12 adjust it." : error;
    self.shortcutAccessButton.accessibilityLabel = [@"Top-row shortcuts: " stringByAppendingString:title];
}
- (void)requestShortcutAccess:(id)sender {
    if (self.shortcutAccessRequested) self.shortcutAccessRequested();
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
- (void)showApps:(id)sender {
    [self cancelRecording];
    [self setSettingsPage:0];
}
- (void)cancelRecording { [self.recorder cancelRecording]; }
- (void)windowDidResignKey:(NSNotification *)notification {
    [self cancelRecording];
}
- (void)windowWillClose:(NSNotification *)notification {
    [self cancelRecording];
    [self.discoOverlay cancel];
}
@end
