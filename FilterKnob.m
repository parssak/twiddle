#import "FilterKnob.h"
#include <math.h>

static NSPoint radial(NSPoint center, double radius, double degrees) {
    double angle = degrees * M_PI / 180;
    return NSMakePoint(center.x + cos(angle) * radius, center.y + sin(angle) * radius);
}

@implementation FilterKnob {
    double _value;
}
+ (NSString *)labelForValue:(double)value {
    if (value < -.00001) return [NSString stringWithFormat:@"Low-pass · %.0f Hz", 20000 * pow(115.0 / 20000, -value)];
    if (value > .00001) return [NSString stringWithFormat:@"High-pass · %.0f Hz", 20 * pow(10000.0 / 20, value)];
    return @"";
}
+ (NSColor *)colorForKey:(NSString *)key fallback:(NSColor *)fallback {
    NSArray *rgb = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    if (rgb.count != 3) return fallback;
    for (id value in rgb) if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return fallback;
    return [NSColor colorWithSRGBRed:fmax(0, fmin(1, [rgb[0] doubleValue]))
                             green:fmax(0, fmin(1, [rgb[1] doubleValue]))
                              blue:fmax(0, fmin(1, [rgb[2] doubleValue])) alpha:1];
}
+ (NSColor *)lowColor { return [self colorForKey:@"lowColor" fallback:NSColor.systemGreenColor]; }
+ (NSColor *)highColor { return [self colorForKey:@"highColor" fallback:NSColor.systemOrangeColor]; }
- (double)doubleValue { return _value; }
- (void)setDoubleValue:(double)value {
    value = isfinite(value) ? fmax(-1, fmin(1, value)) : 0;
    if (_value == value) return;
    _value = value;
    self.needsDisplay = YES;
}
- (void)setEnabled:(BOOL)enabled {
    if (self.enabled == enabled) return;
    [super setEnabled:enabled];
    self.needsDisplay = YES;
}
- (BOOL)acceptsFirstResponder { return self.enabled; }
- (BOOL)becomeFirstResponder { self.needsDisplay = YES; return YES; }
- (BOOL)resignFirstResponder { self.needsDisplay = YES; return YES; }
- (void)changeValue:(double)value {
    if (!self.enabled) return;
    double previous = self.doubleValue;
    self.doubleValue = fabs(value) < .015 ? 0 : value;
    // The arc has 24 intervals. Pulse on arrival/crossing, not again when
    // leaving the same mark or continuing to push against an endpoint.
    double from = previous * 12, to = self.doubleValue * 12;
    BOOL crossed = to > from ? floor(to + 1e-9) > floor(from + 1e-9) :
        ceil(to - 1e-9) < ceil(from - 1e-9);
    if (crossed && self.hapticsEnabled) [NSHapticFeedbackManager.defaultPerformer
        performFeedbackPattern:NSHapticFeedbackPatternAlignment
        performanceTime:NSHapticFeedbackPerformanceTimeNow];
    [self sendAction:self.action to:self.target];
}
- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) return;
    [self.window makeFirstResponder:self];
    if (event.clickCount == 2) { [self sendAction:self.resetAction to:self.target]; return; }
    NSPoint previous = event.locationInWindow;
    double value = self.doubleValue;
    while ((event = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp])) {
        if (event.type == NSEventTypeLeftMouseUp) break;
        NSPoint point = event.locationInWindow;
        double sensitivity = (event.modifierFlags & NSEventModifierFlagShift) ? .001 : .008;
        value = fmax(-1, fmin(1, value + (point.y - previous.y) * sensitivity));
        previous = point;
        [self changeValue:value];
    }
}
- (void)scrollWheel:(NSEvent *)event {
    double step = event.hasPreciseScrollingDeltas ? .003 : .03;
    if (event.modifierFlags & NSEventModifierFlagShift) step *= .1;
    [self changeValue:self.doubleValue + event.scrollingDeltaY * step];
}
- (void)keyDown:(NSEvent *)event {
    double step = (event.modifierFlags & NSEventModifierFlagShift) ? .005 : .025;
    switch (event.keyCode) {
        case 123: case 125: [self changeValue:self.doubleValue - step]; break;
        case 124: case 126: [self changeValue:self.doubleValue + step]; break;
        case 36: if (self.enabled) [self sendAction:self.resetAction to:self.target]; break;
        default: [super keyDown:event];
    }
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilitySliderRole; }
- (id)accessibilityValue { return @(self.doubleValue); }
- (id)accessibilityMinValue { return @(-1); }
- (id)accessibilityMaxValue { return @1; }
- (void)setAccessibilityValue:(id)value { [self changeValue:[value doubleValue]]; }
- (BOOL)accessibilityPerformIncrement { [self changeValue:self.doubleValue + .025]; return self.enabled; }
- (BOOL)accessibilityPerformDecrement { [self changeValue:self.doubleValue - .025]; return self.enabled; }
- (void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    CGFloat scale = MIN(NSWidth(self.bounds) / 220, NSHeight(self.bounds) / 204);
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMidX(self.bounds) yBy:NSMidY(self.bounds)];
    [transform scaleBy:scale];
    [transform concat];
    NSPoint center = NSZeroPoint;
    NSColor *accent = _value > 0 ? FilterKnob.highColor : FilterKnob.lowColor;
    for (int i = 0; i <= 24; i++) {
        double angle = 225 - i * 270.0 / 24;
        NSBezierPath *tick = [NSBezierPath bezierPath];
        [tick moveToPoint:radial(center, 94, angle)];
        [tick lineToPoint:radial(center, i == 12 ? 102 : 98, angle)];
        tick.lineWidth = i == 12 ? 2 : 1;
        [(i == 12 ? NSColor.labelColor : NSColor.secondaryLabelColor) setStroke];
        [tick stroke];
    }
    NSBezierPath *track = [NSBezierPath bezierPath];
    [track appendBezierPathWithArcWithCenter:center radius:85 startAngle:225 endAngle:-45 clockwise:YES];
    track.lineWidth = 4;
    track.lineCapStyle = NSLineCapStyleRound;
    [[NSColor.labelColor colorWithAlphaComponent:.12] setStroke];
    [track stroke];
    if (fabs(_value) > .00001) {
        NSBezierPath *arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:center radius:85 startAngle:90 endAngle:90 - _value * 135 clockwise:_value > 0];
        arc.lineWidth = 4;
        arc.lineCapStyle = NSLineCapStyleRound;
        [NSGraphicsContext saveGraphicsState];
        NSShadow *glow = [NSShadow new];
        glow.shadowColor = [accent colorWithAlphaComponent:.5];
        glow.shadowBlurRadius = 8;
        glow.shadowOffset = NSZeroSize;
        [glow set];
        [accent setStroke];
        [arc stroke];
        [NSGraphicsContext restoreGraphicsState];
    }
    NSRect body = NSMakeRect(center.x - 72, center.y - 72, 144, 144);
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:.5];
    shadow.shadowBlurRadius = 10;
    shadow.shadowOffset = NSZeroSize;
    [shadow set];
    [[NSColor colorWithWhite:.12 alpha:1] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:body] fill];
    [NSGraphicsContext restoreGraphicsState];
    NSGradient *rim = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithWhite:.95 alpha:1], [NSColor colorWithWhite:.58 alpha:1],
        [NSColor colorWithWhite:.25 alpha:1]]];
    [rim drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(body, 1, 1)] angle:-65];
    NSRect face = NSInsetRect(body, 5, 5);
    static NSImage *metal;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        metal = [[NSImage alloc] initWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"KnobMetal" withExtension:@"png"]];
    });
    // The photographed lighting stays fixed; only the recessed pointer rotates.
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithOvalInRect:face] addClip];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
    [metal drawInRect:face fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    NSBezierPath *faceEdge = [NSBezierPath bezierPathWithOvalInRect:face];
    faceEdge.lineWidth = .6;
    [[NSColor.blackColor colorWithAlphaComponent:.35] setStroke];
    [faceEdge stroke];
    NSBezierPath *highlight = [NSBezierPath bezierPath];
    [highlight appendBezierPathWithArcWithCenter:center radius:70 startAngle:25 endAngle:155];
    highlight.lineWidth = .7;
    [[NSColor.whiteColor colorWithAlphaComponent:.7] setStroke];
    [highlight stroke];
    NSBezierPath *pointer = [NSBezierPath bezierPath];
    [pointer moveToPoint:radial(center, 43, 90 - _value * 135)];
    [pointer lineToPoint:radial(center, 59, 90 - _value * 135)];
    pointer.lineWidth = 6.5;
    pointer.lineCapStyle = NSLineCapStyleRound;
    [[NSColor.whiteColor colorWithAlphaComponent:.45] setStroke];
    [pointer stroke];
    pointer.lineWidth = 5;
    [[NSColor colorWithWhite:.12 alpha:1] setStroke];
    [pointer stroke];
    if (self.window.firstResponder == self && self.enabled) {
        NSBezierPath *focus = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(body, -4, -4)];
        focus.lineWidth = 1;
        [[accent colorWithAlphaComponent:.5] setStroke];
        [focus stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
}
@end
