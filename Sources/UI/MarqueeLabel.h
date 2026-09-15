#import <Cocoa/Cocoa.h>

@interface MarqueeLabel : NSView
@property (copy, nonatomic) NSString *stringValue;
@property (nonatomic, getter=isActive) BOOL active;
- (void)restartScroll;
- (void)restartScrollAfterDelay:(NSTimeInterval)delay;
@end
