#import "EffectHoldButton.h"
#import "FilterKnob.h"

@implementation EffectHoldButton
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _momentary = YES;
        _iconSize = 10;
        [self setButtonType:NSButtonTypeMomentaryChange];
        self.focusRingType = NSFocusRingTypeNone;
        self.cell.focusRingType = NSFocusRingTypeNone;
    }
    return self;
}
- (void)drawFocusRingMask {}
- (NSRect)focusRingMaskBounds { return NSZeroRect; }
- (void)setHeld:(BOOL)held {
    if (_held == held) return;
    _held = held;
    self.needsDisplay = YES;
    if (self.heldChanged) self.heldChanged(held);
}
- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) return;
    if (!self.momentary) { [super mouseDown:event]; return; }
    [self.window makeFirstResponder:self];
    self.held = YES;
    @try { [super mouseDown:event]; }
    @finally { self.held = NO; }
}
- (BOOL)acceptsFirstResponder { return self.enabled; }
- (BOOL)becomeFirstResponder { self.needsDisplay = YES; return YES; }
- (BOOL)resignFirstResponder { self.held = NO; self.needsDisplay = YES; return YES; }
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 49 && self.enabled && self.momentary) self.held = YES;
    else [super keyDown:event];
}
- (void)keyUp:(NSEvent *)event {
    if (event.keyCode == 49 && self.momentary) self.held = NO;
    else [super keyUp:event];
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    BOOL pressed = self.held || self.cell.highlighted;
    BOOL lit = self.momentary ? self.held : self.state == NSControlStateValueOn;
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSColor *foreground = [NSColor colorWithWhite:dark ? .72 : .32 alpha:1];
    NSColor *accent = self.activeColor ?: FilterKnob.filterColor;
    NSRect face = NSInsetRect(self.bounds, 1, 1);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:face xRadius:5 yRadius:5];
    NSColor *fill = lit ? [accent colorWithAlphaComponent:.12] :
        [NSColor.labelColor colorWithAlphaComponent:pressed ? .12 : .06];
    [fill setFill];
    [shape fill];
    if (self.image) {
        NSColor *tint = lit ? accent : foreground;
        NSImage *icon = [self.image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPaletteColors:@[tint]]];
        CGFloat size = self.iconSize;
        [icon drawInRect:NSMakeRect(NSMidX(face) - size / 2, NSMidY(face) - size / 2, size, size)
            fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        return;
    }
    NSDictionary *attributes = @{
        NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
        NSKernAttributeName:@.7,
        NSForegroundColorAttributeName:lit ? accent : foreground,
    };
    NSSize size = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(NSMidX(face) - size.width / 2,
        NSMidY(face) - size.height / 2) withAttributes:attributes];
}
@end
