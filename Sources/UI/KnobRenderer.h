#import <Cocoa/Cocoa.h>

// Draws in knob-local coordinates (144 point diameter), without the value arc.
@interface KnobRenderer : NSObject
- (void)drawValue:(double)value lidAngle:(double)lidAngle metalTint:(NSColor *)metalTint;
@end
