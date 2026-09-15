#import "MarqueeLabel.h"
#import <QuartzCore/QuartzCore.h>

@implementation MarqueeLabel {
    NSAttributedString *_text;
    NSTrackingArea *_trackingArea;
    NSTimer *_scrollTimer;
    CAGradientLayer *_edgeMask;
    BOOL _hovered;
    CGFloat _textWidth, _overflow, _offset;
    NSSize _layoutSize;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        _edgeMask = [CAGradientLayer layer];
        _edgeMask.startPoint = CGPointMake(0, .5);
        _edgeMask.endPoint = CGPointMake(1, .5);
    }
    return self;
}
- (void)dealloc { [_scrollTimer invalidate]; }
- (void)setStringValue:(NSString *)stringValue {
    stringValue = [stringValue copy] ?: @"";
    if ([_stringValue isEqualToString:stringValue]) return;
    _stringValue = stringValue;
    _text = [[NSAttributedString alloc] initWithString:stringValue attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
    }];
    _textWidth = ceil(_text.size.width) + 4;
    self.toolTip = stringValue.length ? stringValue : nil;
    [self layoutLabel];
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    if (active && _hovered) [self restartScrollAfterDelay:.5];
    else [self restartScroll];
}
- (void)layout {
    [super layout];
    if (!NSEqualSizes(_layoutSize, self.bounds.size)) [self layoutLabel];
}
- (void)drawRect:(NSRect)dirtyRect {
    // Redraw the complete string at its current offset. Moving an NSTextField
    // can move only the portion AppKit rasterized inside the original clip.
    CGFloat x = _overflow > 0 ? 2 - _offset : (NSWidth(self.bounds) - _text.size.width) / 2;
    CGFloat y = floor((NSHeight(self.bounds) - _text.size.height) / 2);
    [_text drawAtPoint:NSMakePoint(x, y)];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}
- (void)mouseEntered:(NSEvent *)event {
    _hovered = YES;
    [self restartScrollAfterDelay:.5];
}
- (void)mouseExited:(NSEvent *)event {
    _hovered = NO;
    [self restartScroll];
}
- (void)layoutLabel {
    _layoutSize = self.bounds.size;
    _overflow = fmax(0, _textWidth - NSWidth(self.bounds));
    if (self.active && _hovered) [self restartScrollAfterDelay:.5];
    else [self restartScroll];
}
- (void)updateEdgeFade {
    CGFloat fadeWidth = fmin(8, NSWidth(self.bounds) / 2);
    CGFloat left = fmin(fadeWidth, _offset) / fmax(1, NSWidth(self.bounds));
    CGFloat right = fmin(fadeWidth, _overflow - _offset) / fmax(1, NSWidth(self.bounds));
    [CATransaction begin];
    CATransaction.disableActions = YES;
    _edgeMask.frame = self.bounds;
    _edgeMask.colors = @[(id)(left > 0 ? NSColor.clearColor : NSColor.blackColor).CGColor,
        (id)NSColor.blackColor.CGColor, (id)NSColor.blackColor.CGColor,
        (id)(right > 0 ? NSColor.clearColor : NSColor.blackColor).CGColor];
    _edgeMask.locations = @[@0, @(left), @(1 - right), @1];
    self.layer.mask = _overflow > 0 ? _edgeMask : nil;
    [CATransaction commit];
}
- (void)restartScrollAfterDelay:(NSTimeInterval)delay {
    [self restartScroll];
    if (!self.active || !_hovered || _overflow <= 0) return;
    NSTimeInterval start = CACurrentMediaTime() + delay;
    __weak MarqueeLabel *weakSelf = self;
    _scrollTimer = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        MarqueeLabel *self = weakSelf;
        if (!self) { [timer invalidate]; return; }
        self->_offset = fmin(self->_overflow, fmax(0, CACurrentMediaTime() - start) * 24);
        [self updateEdgeFade];
        self.needsDisplay = YES;
        if (self->_offset >= self->_overflow) {
            [timer invalidate];
            self->_scrollTimer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:_scrollTimer forMode:NSRunLoopCommonModes];
}
- (void)restartScroll {
    [_scrollTimer invalidate];
    _scrollTimer = nil;
    _offset = 0;
    [self updateEdgeFade];
    self.needsDisplay = YES;
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityStaticTextRole; }
- (id)accessibilityValue { return self.stringValue; }
@end
