#import "FilterKnob.h"
#import "KnobRenderer.h"
#import "LidAngleMonitor.h"
#include <math.h>

static NSPoint radial(NSPoint center, double radius, double degrees) {
    double angle = degrees * M_PI / 180;
    return NSMakePoint(center.x + cos(angle) * radius, center.y + sin(angle) * radius);
}

static CGFloat smoothstep(CGFloat value) {
    value = fmax(0, fmin(1, value));
    return value * value * (3 - 2 * value);
}

static CGFloat stableNoise(NSInteger index, NSInteger channel) {
    double value = sin((index + 1) * 12.9898 + (channel + 1) * 78.233) * 43758.5453;
    return value - floor(value);
}

@implementation FilterKnob {
    double _value;
    KnobRenderer *_renderer;
    LidAngleMonitor *_lidMonitor;
    NSTimer *_lightingTimer;
    double _displayedLidAngle;
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidChangeOcclusionStateNotification object:nil];
    if (self.window) [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(updateLightingActivity) name:NSWindowDidChangeOcclusionStateNotification object:self.window];
    [self updateLightingActivity];
}
- (void)viewDidHide { [super viewDidHide]; [self updateLightingActivity]; }
- (void)viewDidUnhide { [super viewDidUnhide]; [self updateLightingActivity]; }
- (void)updateLightingActivity {
    BOOL visible = self.window && !self.isHiddenOrHasHiddenAncestor &&
        (self.window.occlusionState & NSWindowOcclusionStateVisible);
    if (!visible) {
        [_lightingTimer invalidate];
        _lightingTimer = nil;
        [_lidMonitor stop];
        return;
    }
    if (_lightingTimer) return;
    if (!_lidMonitor) _lidMonitor = [LidAngleMonitor new];
    if (!_displayedLidAngle) _displayedLidAngle = 90;
    [_lidMonitor start];
    __weak FilterKnob *weakSelf = self;
    _lightingTimer = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        FilterKnob *self = weakSelf;
        if (!self) { [timer invalidate]; return; }
        double target = self->_lidMonitor.available ? self->_lidMonitor.angle : 90;
        double delta = target - self->_displayedLidAngle;
        if (fabs(delta) < .01) return;
        self->_displayedLidAngle += delta * .18;
        self.needsDisplay = YES;
    }];
    [NSRunLoop.mainRunLoop addTimer:_lightingTimer forMode:NSRunLoopCommonModes];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_lightingTimer invalidate];
    [_lidMonitor stop];
}
+ (double)defaultPresetValue {
    return -log(1100.0 / 20000.0) / log(115.0 / 20000.0);
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
+ (NSColor *)defaultFilterColor {
    return [NSColor colorWithSRGBRed:0.98245 green:0.46475 blue:0 alpha:1];
}
+ (NSColor *)lowColor { return [self colorForKey:@"lowColor" fallback:self.defaultFilterColor]; }
+ (NSColor *)highColor { return [self colorForKey:@"highColor" fallback:self.defaultFilterColor]; }
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
    BOOL snappedToNeutral = fabs(previous) > .00001 && fabs(self.doubleValue) <= .00001;
    // The arc has 20 intervals. Pulse on arrival/crossing, not again when
    // leaving the same mark or continuing to push against an endpoint.
    double from = previous * 10, to = self.doubleValue * 10;
    BOOL crossed = to > from ? floor(to + 1e-9) > floor(from + 1e-9) :
        ceil(to - 1e-9) < ceil(from - 1e-9);
    if (self.hapticsEnabled && (snappedToNeutral || crossed)) {
        id<NSHapticFeedbackPerformer> performer = NSHapticFeedbackManager.defaultPerformer;
        [performer performFeedbackPattern:snappedToNeutral ? NSHapticFeedbackPatternLevelChange
                                                         : NSHapticFeedbackPatternAlignment
            performanceTime:NSHapticFeedbackPerformanceTimeNow];
        if (snappedToNeutral) {
            __weak FilterKnob *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    FilterKnob *self = weakSelf;
                    if (!self.hapticsEnabled || fabs(self.doubleValue) > .00001) return;
                    [performer performFeedbackPattern:NSHapticFeedbackPatternGeneric
                        performanceTime:NSHapticFeedbackPerformanceTimeNow];
                });
        }
    }
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
    NSColor *filterAccent = _value > 0 ? FilterKnob.highColor : FilterKnob.lowColor;
    CGFloat magnitude = fabs(_value);
    // Each half of the knob spans 135 degrees. Keep the first 20 degrees
    // visibly neutral, then steadily intensify the chosen color toward the end.
    CGFloat neutralBand = 20.0 / 135.0;
    CGFloat colorAmount = smoothstep(magnitude / neutralBand);
    CGFloat endpointIntensity = smoothstep((magnitude - neutralBand) / (1 - neutralBand));
    NSColor *rgbAccent = [filterAccent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: filterAccent;
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 1;
    [rgbAccent getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    NSColor *vividAccent = [NSColor colorWithHue:hue
        saturation:saturation + (1 - saturation) * endpointIntensity
        brightness:brightness + (1 - brightness) * endpointIntensity
        alpha:alpha];
    NSColor *accent = [[NSColor colorWithWhite:.55 alpha:1]
        blendedColorWithFraction:colorAmount ofColor:vividAccent];
    for (int i = 0; i <= 20; i++) {
        double angle = 225 - i * 270.0 / 20;
        double tickValue = (i - 10) / 10.0;
        BOOL swept = fabs(_value) > .00001 &&
            ((_value > 0 && tickValue >= 0 && tickValue <= _value + 1e-9) ||
             (_value < 0 && tickValue <= 0 && tickValue >= _value - 1e-9));
        NSBezierPath *tick = [NSBezierPath bezierPath];
        [tick moveToPoint:radial(center, 94, angle)];
        [tick lineToPoint:radial(center, i == 10 ? 102 : 98, angle)];
        tick.lineWidth = i == 10 ? 2 : 1;
        NSColor *tickColor = swept ? accent : (i == 10 ? NSColor.labelColor : NSColor.secondaryLabelColor);
        [tickColor setStroke];
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
        arc.lineWidth = 4 + .75 * endpointIntensity;
        arc.lineCapStyle = NSLineCapStyleRound;
        [NSGraphicsContext saveGraphicsState];
        NSShadow *glow = [NSShadow new];
        glow.shadowColor = [accent colorWithAlphaComponent:.5 + .3 * endpointIntensity];
        glow.shadowBlurRadius = 8 + 4 * endpointIntensity;
        glow.shadowOffset = NSZeroSize;
        [glow set];
        [accent setStroke];
        [arc stroke];
        [NSGraphicsContext restoreGraphicsState];

        // Break the emitter into tiny, overlapping patches. Stable spectral
        // and luminance variation reads as imperfect optical scattering while
        // the underlying solid stroke keeps the arc continuous.
        NSColor *arcRGB = [accent colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: accent;
        CGFloat arcHue = 0, arcSaturation = 0, arcBrightness = 0, arcAlpha = 1;
        [arcRGB getHue:&arcHue saturation:&arcSaturation brightness:&arcBrightness alpha:&arcAlpha];
        CGFloat span = magnitude * 135;
        const CGFloat patchDegrees = 2.0;
        NSInteger patchCount = MAX(1, (NSInteger)ceil(span / patchDegrees));
        CGFloat direction = _value > 0 ? -1 : 1;
        NSInteger sideSeed = _value > 0 ? 97 : 193;
        for (NSInteger patch = 0; patch < patchCount; patch++) {
            CGFloat start = patch * patchDegrees;
            CGFloat end = MIN(span, (patch + 1) * patchDegrees) + 0.18;
            CGFloat hueNoise = stableNoise(patch + sideSeed, 0) - .5;
            CGFloat saturationNoise = stableNoise(patch + sideSeed, 1) - .5;
            CGFloat luminanceNoise = stableNoise(patch + sideSeed, 2) - .5;
            CGFloat slowScatter = sin((patch + sideSeed) * .61) * .5;
            CGFloat hueShift = (hueNoise * .65 + slowScatter * .35) * (4.0 / 360.0) * colorAmount;
            CGFloat scatteredSaturation = fmax(0, fmin(1,
                arcSaturation + saturationNoise * .035 * colorAmount));
            CGFloat scatteredBrightness = fmax(0, fmin(1,
                arcBrightness * (1 + luminanceNoise * .035 * colorAmount)));
            CGFloat scatteredHue = fmod(arcHue + hueShift + 1, 1);
            NSColor *scattered = [NSColor colorWithHue:scatteredHue
                saturation:scatteredSaturation brightness:scatteredBrightness alpha:arcAlpha];
            CGFloat glint = pow(stableNoise(patch + sideSeed, 3), 11) * .035 * colorAmount;
            scattered = [scattered blendedColorWithFraction:glint ofColor:NSColor.whiteColor];
            NSBezierPath *patchPath = [NSBezierPath bezierPath];
            [patchPath appendBezierPathWithArcWithCenter:center radius:85
                startAngle:90 + direction * start endAngle:90 + direction * MIN(end, span)
                clockwise:_value > 0];
            patchPath.lineWidth = arc.lineWidth + luminanceNoise * .06 * colorAmount;
            patchPath.lineCapStyle = NSLineCapStyleButt;
            [scattered setStroke];
            [patchPath stroke];
        }
    }
    NSRect body = NSMakeRect(center.x - 72, center.y - 72, 144, 144);
    if (!_renderer) _renderer = [KnobRenderer new];
    [_renderer drawValue:_value lidAngle:_displayedLidAngle ?: 90];
    if (self.window.firstResponder == self && self.enabled) {
        NSBezierPath *focus = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(body, -4, -4)];
        focus.lineWidth = 1;
        [[accent colorWithAlphaComponent:.18 + .32 * colorAmount] setStroke];
        [focus stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
}
@end
