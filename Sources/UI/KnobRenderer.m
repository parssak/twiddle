#import "KnobRenderer.h"
#import <CoreImage/CoreImage.h>
#include <math.h>

// Separate the photo once, at its native resolution. A small blur keeps the
// broad star-shaped reflection in illumination while removing machining detail.
// Overlay's inverse encodes that residual around neutral gray, reconstructing
// the photograph when the two layers have the same orientation.
static void photographicLayers(CGImageRef *illumination, CGImageRef *detail) {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"KnobMetal" withExtension:@"png"];
    CIImage *photo = url ? [CIImage imageWithContentsOfURL:url] : nil;
    if (!photo) return;
    size_t width = (size_t)photo.extent.size.width, height = (size_t)photo.extent.size.height;
    size_t stride = width * 4;
    NSMutableData *original = [NSMutableData dataWithLength:stride * height];
    NSMutableData *blurred = [NSMutableData dataWithLength:stride * height];
    CIContext *context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null}];
    CGColorSpaceRef colors = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    [context render:photo toBitmap:original.mutableBytes rowBytes:stride bounds:photo.extent
        format:kCIFormatRGBA8 colorSpace:colors];
    CIImage *low = [[[photo imageByClampingToExtent] imageByApplyingFilter:@"CIGaussianBlur"
        withInputParameters:@{kCIInputRadiusKey:@6}] imageByCroppingToRect:photo.extent];
    [context render:low toBitmap:blurred.mutableBytes rowBytes:stride bounds:photo.extent
        format:kCIFormatRGBA8 colorSpace:colors];
    unsigned char *source = original.mutableBytes, *base = blurred.mutableBytes;
    for (size_t i = 0; i < stride * height; i += 4) {
        for (size_t c = 0; c < 3; c++) {
            double b = base[i + c] / 255.0, p = source[i + c] / 255.0;
            double residual = .5 + (p - b) / (2 * fmax(1.0 / 255, fmin(b, 1 - b)));
            source[i + c] = (unsigned char)lround(fmax(0, fmin(1, residual)) * 255);
        }
        source[i + 3] = base[i + 3] = 255;
    }
    CGDataProviderRef lowData = CGDataProviderCreateWithCFData((__bridge CFDataRef)blurred);
    CGDataProviderRef detailData = CGDataProviderCreateWithCFData((__bridge CFDataRef)original);
    *illumination = CGImageCreate(width, height, 8, 32, stride, colors,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast, lowData, NULL, YES, kCGRenderingIntentDefault);
    *detail = CGImageCreate(width, height, 8, 32, stride, colors,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast, detailData, NULL, YES, kCGRenderingIntentDefault);
    CGDataProviderRelease(lowData);
    CGDataProviderRelease(detailData);
    CGColorSpaceRelease(colors);
}

@implementation KnobRenderer
- (void)drawValue:(double)value lidAngle:(double)lidAngle metalTint:(NSColor *)metalTint {
    NSRect body = NSMakeRect(-72, -72, 144, 144);
    // Sweep the photograph's existing reflection with the lid. Adding
    // another specular lobe over its baked sheen would make two light sources.
    CGFloat tilt = fmax(-1, fmin(1, (lidAngle - 90) / 50));
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
    [rim drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(body, 1, 1)] angle:-65 + tilt * 35];
    NSRect face = NSInsetRect(body, 5, 5);
    static CGImageRef illumination, detail;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        photographicLayers(&illumination, &detail);
    });
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithOvalInRect:face] addClip];
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *rotation = [NSAffineTransform transform];
    [rotation rotateByDegrees:tilt * 40];
    [rotation concat];
    CGContextRef graphics = NSGraphicsContext.currentContext.CGContext;
    CGContextSetInterpolationQuality(graphics, kCGInterpolationHigh);
    if (illumination) CGContextDrawImage(graphics, NSRectToCGRect(face), illumination);
    [NSGraphicsContext restoreGraphicsState];
    [NSGraphicsContext saveGraphicsState];
    rotation = [NSAffineTransform transform];
    [rotation rotateByDegrees:-value * 135];
    [rotation concat];
    CGContextSetBlendMode(graphics, kCGBlendModeOverlay);
    if (detail) CGContextDrawImage(graphics, NSRectToCGRect(face), detail);
    [NSGraphicsContext restoreGraphicsState];
    // Directional shading reinforces the lid tilt while retaining machining detail.
    NSGradient *shade = [[NSGradient alloc] initWithStartingColor:NSColor.clearColor
        endingColor:[NSColor.blackColor colorWithAlphaComponent:fabs(tilt) * .22]];
    [shade drawInRect:face angle:tilt >= 0 ? 90 : -90];
    [NSGraphicsContext restoreGraphicsState];
    // Shape the midtones without dimming the bright reflection bands. Only the
    // face gets this finish; the machined silver rim remains a distinct edge.
    if (metalTint) {
        [NSGraphicsContext saveGraphicsState];
        CGContextSetBlendMode(graphics, kCGBlendModeOverlay);
        [metalTint setFill];
        [[NSBezierPath bezierPathWithOvalInRect:face] fill];
        [NSGraphicsContext restoreGraphicsState];
    }
    NSBezierPath *edge = [NSBezierPath bezierPathWithOvalInRect:face];
    edge.lineWidth = .6;
    [[NSColor.blackColor colorWithAlphaComponent:.35] setStroke];
    [edge stroke];
    NSBezierPath *highlight = [NSBezierPath bezierPath];
    [highlight appendBezierPathWithArcWithCenter:NSZeroPoint radius:70
        startAngle:25 + tilt * 35 endAngle:155 + tilt * 35];
    highlight.lineWidth = .7;
    [[NSColor.whiteColor colorWithAlphaComponent:.7] setStroke];
    [highlight stroke];
    // The indicator follows only the filter, never the changing reflection.
    double angle = (90 - value * 135) * M_PI / 180;
    NSBezierPath *pointer = [NSBezierPath bezierPath];
    [pointer moveToPoint:NSMakePoint(cos(angle) * 43, sin(angle) * 43)];
    [pointer lineToPoint:NSMakePoint(cos(angle) * 59, sin(angle) * 59)];
    pointer.lineWidth = 6.5;
    pointer.lineCapStyle = NSLineCapStyleRound;
    [[NSColor.whiteColor colorWithAlphaComponent:.45] setStroke];
    [pointer stroke];
    pointer.lineWidth = 5;
    [[NSColor colorWithWhite:.12 alpha:1] setStroke];
    [pointer stroke];
}
@end
