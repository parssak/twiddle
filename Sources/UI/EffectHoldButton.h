#import <Cocoa/Cocoa.h>

@interface EffectHoldButton : NSButton
@property (nonatomic) BOOL held;
@property (nonatomic) BOOL momentary;
@property NSColor *activeColor;
@property CGFloat iconSize;
@property (copy) void (^heldChanged)(BOOL held);
@end
