#import "OnboardingController.h"

static NSTextField *setupLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color,
                               NSRect frame, NSTextAlignment alignment) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.alignment = alignment;
    label.frame = frame;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static NSImageView *setupSymbol(NSString *name, NSColor *tint, NSRect frame) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:18
        weight:NSFontWeightMedium];
    NSImageView *view = [[NSImageView alloc] initWithFrame:frame];
    view.image = [image imageWithSymbolConfiguration:config] ?: image;
    view.imageScaling = NSImageScaleProportionallyDown;
    view.contentTintColor = tint;
    view.accessibilityElement = NO;
    return view;
}

@interface OnboardingController ()
@property NSTextField *titleLabel;
@property NSTextField *summaryLabel;
@property NSTextField *audioStatus;
@property NSTextField *shortcutsStatus;
@property NSImageView *audioReadyIcon;
@property NSImageView *shortcutsReadyIcon;
@property NSButton *audioButton;
@property NSButton *audioSettingsButton;
@property NSButton *shortcutsButton;
@property NSButton *finishButton;
@property NSSwitch *loginSwitch;
@property NSTextField *loginLabel;
@property BOOL audioAttempted;
@property BOOL audioSettingsOpened;
@property BOOL shortcutsAttempted;
@end

@implementation OnboardingController
- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 410)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        window.title = @"Set Up Twiddle";
        window.titleVisibility = NSWindowTitleHidden;
        window.titlebarAppearsTransparent = YES;
        window.backgroundColor = NSColor.windowBackgroundColor;
        window.releasedWhenClosed = NO;
        [window center];

        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 410)];
        window.contentView = root;
        NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"AppIcon" withExtension:@"icns"];
        NSImage *icon = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : nil;
        NSImageView *appIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(234, 322, 52, 52)];
        appIcon.image = icon ?: [NSImage imageWithSystemSymbolName:@"waveform" accessibilityDescription:nil];
        appIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
        appIcon.wantsLayer = YES;
        appIcon.layer.cornerRadius = 12;
        appIcon.layer.cornerCurve = kCACornerCurveContinuous;
        appIcon.layer.masksToBounds = YES;
        appIcon.accessibilityElement = NO;
        [root addSubview:appIcon];
        self.titleLabel = setupLabel(@"Welcome to Twiddle", 24, NSFontWeightSemibold,
            NSColor.labelColor, NSMakeRect(30, 284, 460, 32), NSTextAlignmentCenter);
        [root addSubview:self.titleLabel];
        self.summaryLabel = setupLabel(@"Shape the sound from your apps.", 13, NSFontWeightRegular,
            NSColor.secondaryLabelColor, NSMakeRect(35, 258, 450, 19), NSTextAlignmentCenter);
        [root addSubview:self.summaryLabel];

        NSBox *group = [[NSBox alloc] initWithFrame:NSMakeRect(32, 95, 456, 150)];
        group.boxType = NSBoxCustom;
        group.titlePosition = NSNoTitle;
        group.contentViewMargins = NSZeroSize;
        group.borderWidth = 0;
        group.cornerRadius = 12;
        group.fillColor = NSColor.controlBackgroundColor;
        [root addSubview:group];
        NSView *rows = group.contentView;
        [rows addSubview:setupSymbol(@"waveform", NSColor.secondaryLabelColor,
            NSMakeRect(18, 105, 22, 24))];
        [rows addSubview:setupLabel(@"System Audio", 14, NSFontWeightSemibold,
            NSColor.labelColor, NSMakeRect(52, 116, 250, 20), NSTextAlignmentLeft)];
        self.audioStatus = setupLabel(@"Required to filter your apps", 12, NSFontWeightRegular,
            NSColor.secondaryLabelColor, NSMakeRect(52, 96, 270, 18), NSTextAlignmentLeft);
        [rows addSubview:self.audioStatus];
        self.audioSettingsButton = [NSButton buttonWithTitle:@"Open Privacy Settings"
            target:self action:@selector(openAudioSettings:)];
        self.audioSettingsButton.frame = NSMakeRect(47, 76, 164, 18);
        self.audioSettingsButton.bordered = NO;
        self.audioSettingsButton.font = [NSFont systemFontOfSize:11];
        self.audioSettingsButton.contentTintColor = NSColor.controlAccentColor;
        self.audioSettingsButton.hidden = YES;
        [rows addSubview:self.audioSettingsButton];
        self.audioButton = [NSButton buttonWithTitle:@"Allow" target:self action:@selector(requestAudio:)];
        self.audioButton.frame = NSMakeRect(338, 98, 100, 30);
        self.audioButton.bezelStyle = NSBezelStyleRounded;
        self.audioButton.controlSize = NSControlSizeSmall;
        [rows addSubview:self.audioButton];
        self.audioReadyIcon = setupSymbol(@"checkmark.circle.fill", NSColor.systemGreenColor,
            NSMakeRect(405, 101, 24, 24));
        [rows addSubview:self.audioReadyIcon];

        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(52, 73, 386, 1)];
        separator.boxType = NSBoxSeparator;
        [rows addSubview:separator];
        [rows addSubview:setupSymbol(@"keyboard", NSColor.secondaryLabelColor,
            NSMakeRect(18, 29, 22, 24))];
        [rows addSubview:setupLabel(@"Keyboard Shortcuts", 14, NSFontWeightSemibold,
            NSColor.labelColor, NSMakeRect(52, 41, 250, 20), NSTextAlignmentLeft)];
        self.shortcutsStatus = setupLabel(@"Option + F10–F12 · Optional", 12, NSFontWeightRegular,
            NSColor.secondaryLabelColor, NSMakeRect(52, 21, 270, 18), NSTextAlignmentLeft);
        [rows addSubview:self.shortcutsStatus];
        self.shortcutsButton = [NSButton buttonWithTitle:@"Set Up"
            target:self action:@selector(requestShortcuts:)];
        self.shortcutsButton.frame = NSMakeRect(338, 23, 100, 30);
        self.shortcutsButton.bezelStyle = NSBezelStyleRounded;
        self.shortcutsButton.controlSize = NSControlSizeSmall;
        [rows addSubview:self.shortcutsButton];
        self.shortcutsReadyIcon = setupSymbol(@"checkmark.circle.fill", NSColor.systemGreenColor,
            NSMakeRect(405, 26, 24, 24));
        [rows addSubview:self.shortcutsReadyIcon];

        self.loginLabel = setupLabel(@"Open at Login", 13, NSFontWeightRegular,
            NSColor.labelColor, NSMakeRect(35, 56, 210, 21), NSTextAlignmentLeft);
        [root addSubview:self.loginLabel];
        self.loginSwitch = [NSSwitch new];
        self.loginSwitch.state = NSControlStateValueOn;
        self.loginSwitch.accessibilityLabel = @"Open Twiddle at Login";
        [self.loginSwitch sizeToFit];
        self.loginSwitch.frame = NSMakeRect(432, 54, NSWidth(self.loginSwitch.frame), NSHeight(self.loginSwitch.frame));
        [root addSubview:self.loginSwitch];
        self.finishButton = [NSButton buttonWithTitle:@"Start Twiddle" target:self action:@selector(finish:)];
        self.finishButton.frame = NSMakeRect(352, 15, 136, 32);
        self.finishButton.bezelStyle = NSBezelStyleRounded;
        [root addSubview:self.finishButton];
        [self refresh];
    }
    return self;
}
- (void)show {
    [self refresh];
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
}
- (void)refresh {
    self.window.title = self.firstRun ? @"Set Up Twiddle" : @"Twiddle Permissions";
    self.titleLabel.stringValue = self.firstRun ? @"Welcome to Twiddle" : @"Permissions";
    self.summaryLabel.stringValue = self.firstRun ? @"Shape the sound from your apps." :
        @"Manage access for Twiddle.";
    self.audioStatus.stringValue = self.audioReady ? @"Ready to filter" :
        self.audioError.length ? @"Couldn’t start audio" :
        self.audioAttempted ? @"Allow in Privacy & Security" : @"Required to filter your apps";
    self.audioStatus.toolTip = self.audioError;
    self.audioButton.title = self.audioAttempted ? @"Retry" : @"Allow";
    self.audioButton.accessibilityLabel = self.audioAttempted ? @"Retry system audio access" :
        @"Allow system audio access";
    self.audioButton.hidden = self.audioReady;
    self.audioReadyIcon.hidden = !self.audioReady;
    self.audioSettingsButton.hidden = self.audioReady || !self.audioAttempted;
    self.shortcutsStatus.stringValue = self.shortcutsReady ? @"Ready" :
        self.shortcutsAttempted ? @"Allow in Accessibility" : @"Option + F10–F12 · Optional";
    self.shortcutsButton.title = self.shortcutsAttempted ? @"Settings" : @"Set Up";
    self.shortcutsButton.accessibilityLabel = self.shortcutsAttempted ? @"Open Accessibility settings" :
        @"Set up keyboard shortcuts";
    self.shortcutsButton.hidden = self.shortcutsReady;
    self.shortcutsReadyIcon.hidden = !self.shortcutsReady;
    self.finishButton.title = self.firstRun ? @"Start Twiddle" : @"Done";
    self.finishButton.enabled = !self.firstRun || self.audioReady;
    self.audioButton.keyEquivalent = self.audioReady ? @"" : @"\r";
    self.finishButton.keyEquivalent = self.audioReady ? @"\r" : @"";
    self.loginSwitch.hidden = !self.firstRun;
    self.loginLabel.hidden = !self.firstRun;
}
- (void)requestAudio:(id)sender {
    self.audioAttempted = YES;
    if (self.audioRequested) self.audioRequested();
    [self refresh];
}
- (void)openAudioSettings:(id)sender {
    self.audioSettingsOpened = YES;
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    [NSWorkspace.sharedWorkspace openURL:url];
}
- (BOOL)consumeAudioSettingsOpened {
    BOOL opened = self.audioSettingsOpened;
    self.audioSettingsOpened = NO;
    return opened;
}
- (void)requestShortcuts:(id)sender {
    if (self.shortcutsAttempted) {
        NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
        [NSWorkspace.sharedWorkspace openURL:url];
    } else {
        self.shortcutsAttempted = YES;
        if (self.shortcutsRequested) self.shortcutsRequested();
        [self refresh];
    }
}
- (void)finish:(id)sender {
    if (self.firstRun && !self.audioReady) return;
    if (self.finished) self.finished(self.loginSwitch.state == NSControlStateValueOn);
    [self.window close];
}
@end
