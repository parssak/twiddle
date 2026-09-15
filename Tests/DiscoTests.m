#import "DiscoMotion.h"
#import "AlbumPalette.h"
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "Disco check failed: %s, line %d\n", #c, __LINE__); return 1; } } while (0)
int discoMotionTests(void) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:128 bitsPerPixel:32];
    NSImage *cover = [[NSImage alloc] initWithSize:NSMakeSize(32,32)];
    [cover addRepresentation:bitmap];
    memset(bitmap.bitmapData, 128, 32*128);
    for (int i=0;i<1024;i++) bitmap.bitmapData[i*4+3]=255;
    CHECK(albumPalette(cover).count == 0);
    for (int i=0;i<1024;i++) {
        unsigned char *p=bitmap.bitmapData+i*4;
        p[0]=i%32<16 ? 230 : 20; p[1]=20; p[2]=i%32<16 ? 20 : 230;
    }
    // Recreate the image so cached representations cannot retain the gray sample.
    cover = [[NSImage alloc] initWithSize:NSMakeSize(32,32)]; [cover addRepresentation:bitmap];
    NSArray<NSColor *> *palette = albumPalette(cover);
    CHECK(palette.count == 2);
    BOOL red=NO, blue=NO;
    for (NSColor *color in palette) { red |= color.redComponent > .8; blue |= color.blueComponent > .8; }
    CHECK(red && blue && albumPalette(nil).count == 0);
    puts("Album palette: distinct accents, monochrome fallback, and missing artwork checks passed.");
    DiscoMotion *motion = [DiscoMotion new];
    [motion beginAt:10];
    CHECK((![motion pull:(vector_float2){.04,.03} at:10.05]));
    vector_float2 held = [motion offsetAt:10.1];
    CHECK(held.x > 0 && held.y > 0 && motion.palette == 0);
    [motion releaseAt:10.2];
    CHECK(simd_length([motion offsetAt:10.2]-held) < .00001);
    CHECK(simd_length([motion offsetAt:13]) < .00001);
    [motion beginAt:14];
    CHECK((![motion pull:(vector_float2){-.05,.14} at:14.05]));
    CHECK(motion.dragging && motion.pullProgress < 1);
    CHECK(([motion pull:(vector_float2){-.05,.28} at:14.1]));
    CHECK(motion.palette == 1 && !motion.dragging);
    CHECK((![motion pull:(vector_float2){0,.2} at:14.2]));
    CHECK(motion.palette == 1);
    CHECK([motion offsetAt:14.1].x < 0);
    CHECK([motion offsetAt:14.2].y < [motion offsetAt:14.1].y);
    CHECK([motion paletteBlendAt:14.1] == 0 && [motion paletteBlendAt:14.4] == 1);
    [motion beginAt:14.3];
    CHECK((![motion pull:(vector_float2){0,-.1} at:14.4]));
    CHECK(motion.palette == 1);
    [motion reset];
    CHECK(!motion.dragging && simd_length([motion offsetAt:14.5]) == 0);
    for (int i=0;i<4;i++) {
        [motion beginAt:20+i];
        CHECK(([motion pull:(vector_float2){0,.30} at:20.1+i]));
        [motion reset];
    }
    CHECK(motion.palette == 5);
    [motion reset];
    [motion addSpin:3 at:30];
    CHECK([motion spinAngleAt:30] == 0 && [motion spinVelocityAt:30] == 3);
    double angle = [motion spinAngleAt:30.1];
    CHECK(angle > 0 && [motion spinVelocityAt:31] < 1);
    [motion addSpin:-6 at:30.1];
    CHECK(fabs([motion spinAngleAt:30.1]-angle) < .00001);
    CHECK([motion spinVelocityAt:30.1]+.3 < 0);
    CHECK([motion spinAngleAt:30.2] < angle);
    CHECK(fabs([motion spinVelocityAt:40]) < .00001);
    [motion addSpin:1000 at:40];
    CHECK([motion spinVelocityAt:40] == 8);
    [motion addSpin:NAN at:40];
    CHECK(isfinite([motion spinAngleAt:41]));
    [motion reset];
    CHECK([motion spinAngleAt:42] == 0 && [motion spinVelocityAt:42] == 0);
    puts("Disco swipe continuity, reversal, friction, speed limit, and reset checks passed.");
    puts("Disco pull threshold, single latch, spring continuity, palette, and reset checks passed.");
    return 0;
}
