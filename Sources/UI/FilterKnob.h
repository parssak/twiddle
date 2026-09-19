#import <Cocoa/Cocoa.h>

@interface FilterKnob : NSControl
@property (nonatomic) BOOL hapticsEnabled;
@property (nonatomic) BOOL unipolar; // 0–1 amount, rather than the main filter’s −1–1 range.
@property (nonatomic) double dragStep; // Zero keeps dragging continuous; scrolling is always continuous.
@property (nonatomic) NSColor *metalTint; // Optional midtone finish; keeps reflections and the silver rim.
@property (nonatomic) SEL resetAction;
+ (NSString *)labelForValue:(double)value;
+ (double)defaultPresetValue;
+ (NSColor *)filterColor;
@end
