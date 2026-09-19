#import "EffectsTrayView.h"

@implementation EffectsTrayView
- (BOOL)isOpaque { return YES; }
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    self.needsDisplay = YES;
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    // An opaque, finely grained finish separates the recessed tray from the
    // translucent popover material above it. Cache the grain across frames.
    static NSArray<NSColor *> *grains;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *patterns = [NSMutableArray new];
        for (NSInteger theme = 0; theme < 2; theme++) {
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes:NULL pixelsWide:192 pixelsHigh:192
                bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            uint32_t seed = 37;
            for (NSInteger y = 0; y < 192; y++) {
                for (NSInteger x = 0; x < 192; x++) {
                    seed = seed * 1664525u + 1013904223u;
                    unsigned char *pixel = bitmap.bitmapData + y * bitmap.bytesPerRow + x * 4;
                    unsigned char value = (theme == 0 ? 218 : 8) + (seed >> 28) / 3;
                    pixel[0] = value;
                    pixel[1] = value + 1;
                    pixel[2] = value + 2;
                    pixel[3] = 255;
                }
            }
            NSImage *texture = [[NSImage alloc] initWithSize:NSMakeSize(96, 96)];
            [texture addRepresentation:bitmap];
            [patterns addObject:[NSColor colorWithPatternImage:texture]];
        }
        grains = patterns;
    });
    [grains[dark ? 1 : 0] setFill];
    NSRectFill(self.bounds);

    // The upper shelf casts a shadow into the tray, with a narrow lit edge.
    CGFloat top = NSMaxY(self.bounds);
    NSGradient *shadow = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithWhite:0 alpha:dark ? .7 : .13]
        endingColor:NSColor.clearColor];
    [shadow drawInRect:NSMakeRect(0, top - 24, NSWidth(self.bounds), 24) angle:270];
    NSGradient *side = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithWhite:0 alpha:dark ? .3 : .05]
        endingColor:NSColor.clearColor];
    [side drawInRect:NSMakeRect(0, 0, 10, top) angle:0];
    [side drawInRect:NSMakeRect(NSWidth(self.bounds) - 10, 0, 10, top) angle:180];
    [[NSColor colorWithWhite:1 alpha:dark ? .08 : .55] setFill];
    NSRectFillUsingOperation(NSMakeRect(0, top - .5, NSWidth(self.bounds), .5), NSCompositingOperationSourceOver);
}
@end
