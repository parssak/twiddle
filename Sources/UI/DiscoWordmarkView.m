#import "DiscoWordmarkView.h"
#import <QuartzCore/QuartzCore.h>

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
    NSColor *base = dark ? NSColor.secondaryLabelColor : [NSColor colorWithWhite:.45 alpha:1];
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
