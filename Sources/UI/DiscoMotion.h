#import <Foundation/Foundation.h>
#import <simd/simd.h>

// Displacements are fractions of screen height, with positive y pointing down.
@interface DiscoMotion : NSObject
@property (readonly) BOOL dragging;
@property (readonly) NSUInteger palette;
@property (readonly) float pullProgress;
- (vector_float2)offsetAt:(double)time;
- (void)beginAt:(double)time;
- (BOOL)pull:(vector_float2)translation at:(double)time;
- (void)releaseAt:(double)time;
// Extra rotation and velocity decay independently of the normal .3 rad/s spin.
- (double)spinAngleAt:(double)time;
- (double)spinVelocityAt:(double)time;
- (void)addSpin:(double)impulse at:(double)time;
- (void)reset;
- (float)paletteBlendAt:(double)time;
@end
