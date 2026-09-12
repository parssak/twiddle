#import <Cocoa/Cocoa.h>

@interface FilterKnob : NSControl
@property (nonatomic) BOOL hapticsEnabled;
@property (nonatomic) SEL resetAction;
+ (NSString *)labelForValue:(double)value;
+ (NSColor *)lowColor;
+ (NSColor *)highColor;
@end
