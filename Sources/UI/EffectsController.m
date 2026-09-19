#import "EffectsController.h"
#import "AudioEngine.h"
#import "FilterKnob.h"
#import "EffectHoldButton.h"

enum { ReverbControl, PitchControl, PhaserControl };

@interface EffectsController ()
@property AudioEngine *engine;
@property NSArray<NSControl *> *sliders;
@property NSArray<NSTextField *> *values;
@end
@implementation EffectsController
- (instancetype)initWithEngine:(AudioEngine *)engine {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 430, 500)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self = [super initWithWindow:window])) return nil;
    self.engine = engine;
    window.title = @"Twiddle · Effects";
    window.delegate = self;
    window.releasedWhenClosed = NO;
    [window center];
    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:window.contentView.bounds];
    glass.material = NSVisualEffectMaterialSidebar;
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = glass;
    [self label:@"Effects" frame:NSMakeRect(24, 452, 380, 28) size:20];
    NSMutableArray *sliders = [NSMutableArray new], *values = [NSMutableArray new];
    NSArray *names = @[@"Reverb", @"Pitch", @"Phaser"];
    NSArray *hints = @[@"Add space around the track", @"Slide an octave down or up; center returns to normal", @"A liquid sweep that gets deeper and faster"];
    for (NSUInteger i = 0; i < names.count; i++) {
        if (i != PitchControl) {
            CGFloat x = i == ReverbControl ? 20 : 220;
            NSTextField *name = [self label:names[i] frame:NSMakeRect(x, 422, 190, 22) size:13];
            name.alignment = NSTextAlignmentCenter;
            FilterKnob *knob = [[FilterKnob alloc] initWithFrame:NSMakeRect(x, 242, 190, 176)];
            knob.unipolar = YES; knob.hapticsEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"hapticsEnabled"];
            knob.tag = i; knob.target = self; knob.action = @selector(amountChanged:); knob.resetAction = @selector(resetKnob:);
            knob.accessibilityLabel = names[i]; knob.toolTip = [hints[i] stringByAppendingString:@". Drag up/down or scroll; double-click to reset."];
            [glass addSubview:knob]; [sliders addObject:knob];
            NSTextField *value = [self label:@"Off" frame:NSMakeRect(x, 224, 190, 22) size:12];
            value.alignment = NSTextAlignmentCenter; value.textColor = NSColor.secondaryLabelColor;
            [values addObject:value];
            continue;
        }
        CGFloat y = 142;
        [self label:names[i] frame:NSMakeRect(24, y + 38, 290, 22) size:13];
        NSTextField *description = [self label:hints[i] frame:NSMakeRect(24, y + 22, 366, 16) size:11];
        description.textColor = NSColor.secondaryLabelColor;
        NSSlider *slider = [NSSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(amountChanged:)];
        slider.frame = NSMakeRect(24, y - 2, 382, 24);
        slider.tag = i; slider.continuous = YES;
        if (i == PitchControl) {
            slider.minValue = -12; slider.maxValue = 12;
            slider.numberOfTickMarks = 3; slider.allowsTickMarkValuesOnly = NO;
        }
        slider.accessibilityLabel = names[i]; slider.toolTip = hints[i];
        [glass addSubview:slider]; [sliders addObject:slider];
        NSTextField *value = [self label:i == PitchControl ? @"0 st" : @"Off" frame:NSMakeRect(328, y + 38, 78, 22) size:12];
        value.alignment = NSTextAlignmentRight;
        value.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
        value.textColor = NSColor.secondaryLabelColor;
        [values addObject:value];
    }
    NSTextField *low = [self label:@"−12" frame:NSMakeRect(24, 118, 40, 18) size:10];
    NSTextField *middle = [self label:@"0" frame:NSMakeRect(195, 118, 40, 18) size:10];
    NSTextField *high = [self label:@"+12" frame:NSMakeRect(366, 118, 40, 18) size:10];
    middle.alignment = NSTextAlignmentCenter; high.alignment = NSTextAlignmentRight;
    low.textColor = middle.textColor = high.textColor = NSColor.secondaryLabelColor;
    __weak EffectsController *weakSelf = self;
    EffectHoldButton *tape = [[EffectHoldButton alloc] initWithFrame:NSMakeRect(20, 65, 390, 36)];
    tape.title = @"Hold · Tape stop"; tape.bezelStyle = NSBezelStyleRounded;
    tape.toolTip = @"Hold to slow to a stop; release to return to live playback";
    tape.heldChanged = ^(BOOL held) { weakSelf.engine.tapeStop = held; };
    [glass addSubview:tape];
    self.sliders = sliders; self.values = values;
    NSButton *reset = [NSButton buttonWithTitle:@"Reset effects" target:self action:@selector(reset:)];
    reset.frame = NSMakeRect(20, 18, 125, 30); [glass addSubview:reset];
    NSTextField *hint = [self label:@"Closing this window resets the effects" frame:NSMakeRect(157, 20, 250, 22) size:11];
    hint.textColor = NSColor.secondaryLabelColor;
    return self;
}
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size {
    return [self label:text frame:frame size:size inView:self.window.contentView];
}
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size inView:(NSView *)parent {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:size weight:size > 15 ? NSFontWeightSemibold : NSFontWeightRegular];
    [parent addSubview:label]; return label;
}
- (void)amountChanged:(NSControl *)slider {
    if (slider.tag == ReverbControl) self.engine.reverb = slider.doubleValue;
    else if (slider.tag == PitchControl) {
        if (fabs(slider.doubleValue) < .12f) slider.doubleValue = 0;
        self.engine.pitch = slider.doubleValue;
    } else if (slider.tag == PhaserControl) self.engine.phaser = slider.doubleValue;
    self.values[slider.tag].stringValue = slider.tag == PitchControl ?
        [NSString stringWithFormat:@"%+.2f st", slider.doubleValue] :
        (slider.doubleValue == 0 ? @"Off" : [NSString stringWithFormat:@"%.0f%%", slider.doubleValue * 100]);
}
- (void)resetKnob:(FilterKnob *)knob { knob.doubleValue = 0; [self amountChanged:knob]; }
- (void)reset:(id)sender {
    self.engine.tapeStop = NO;
    for (NSControl *slider in self.sliders) { slider.doubleValue = 0; [self amountChanged:slider]; }
}
- (void)windowDidResignKey:(NSNotification *)note { self.engine.tapeStop = NO; }
- (void)windowWillClose:(NSNotification *)note { [self reset:nil]; }
- (void)show { [NSApp activateIgnoringOtherApps:YES]; [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil]; }
@end
