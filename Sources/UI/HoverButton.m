#import "HoverButton.h"
#import <QuartzCore/QuartzCore.h>

@implementation HoverButton {
    NSTrackingArea *_tracking;
    BOOL _hovered;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.font = [NSFont systemFontOfSize:12];
        self.bordered = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 7;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return self;
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)event { [self setHovered:YES]; }
- (void)mouseExited:(NSEvent *)event { [self setHovered:NO]; }
- (void)setHovered:(BOOL)hovered {
    if (_hovered == hovered) return;
    _hovered = hovered;
    CGColorRef previous = self.layer.presentationLayer.backgroundColor ?: self.layer.backgroundColor;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    fade.fromValue = (__bridge id)previous;
    fade.duration = .15;
    [CATransaction begin];
    CATransaction.disableActions = YES;
    self.layer.backgroundColor = [NSColor.systemBlueColor colorWithAlphaComponent:hovered ? .12 : 0].CGColor;
    [CATransaction commit];
    fade.toValue = (__bridge id)self.layer.backgroundColor;
    [self.layer addAnimation:fade forKey:@"hoverColor"];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    NSDictionary *attributes = @{NSFontAttributeName:self.font,
        NSForegroundColorAttributeName:(_hovered || self.highlighted) ? NSColor.systemBlueColor : NSColor.secondaryLabelColor};
    NSSize size = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint((NSWidth(self.bounds) - size.width) / 2,
        (NSHeight(self.bounds) - size.height) / 2) withAttributes:attributes];
}
@end
