#import "AlbumPalette.h"

NSArray<NSColor *> *albumPalette(NSImage *image) {
    if (!image) return @[];
    CGImageRef source = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!source) return @[];
    unsigned char pixels[32*32*4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, 32, 32, 8, 32*4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return @[];
    CGContextDrawImage(context, CGRectMake(0, 0, 32, 32), source);
    CGContextRelease(context);
    struct { double weight, r, g, b; } bins[512] = {0};
    for (int i=0; i<32*32; i++) {
        unsigned char *pixel = pixels+i*4;
        if (pixel[3] < 230) continue;
        double r=pixel[0]/255., g=pixel[1]/255., b=pixel[2]/255.;
        double high=fmax(r,fmax(g,b)), low=fmin(r,fmin(g,b));
        double saturation = high ? (high-low)/high : 0;
        if (high < .15 || saturation < .20) continue;
        int bin = (pixel[0]/32)*64+(pixel[1]/32)*8+pixel[2]/32;
        double weight = saturation*saturation;
        bins[bin].weight += weight;
        bins[bin].r += r*weight; bins[bin].g += g*weight; bins[bin].b += b*weight;
    }
    NSMutableArray<NSColor *> *colors = [NSMutableArray new];
    while (colors.count < 4) {
        int best = -1;
        for (int i=0;i<512;i++) if (bins[i].weight >= 2 && (best<0 || bins[i].weight > bins[best].weight)) best=i;
        if (best < 0) break;
        double r=bins[best].r/bins[best].weight, g=bins[best].g/bins[best].weight, b=bins[best].b/bins[best].weight;
        bins[best].weight=0;
        double scale=.95/fmax(r,fmax(g,b));
        r*=scale; g*=scale; b*=scale;
        BOOL distinct=YES;
        for (NSColor *color in colors) {
            double dr=r-color.redComponent, dg=g-color.greenComponent, db=b-color.blueComponent;
            if (dr*dr+dg*dg+db*db < .10) { distinct=NO; break; }
        }
        if (distinct) [colors addObject:[NSColor colorWithSRGBRed:r green:g blue:b alpha:1]];
    }
    return colors;
}
