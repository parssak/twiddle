#import <Cocoa/Cocoa.h>

@interface DiscoWordmarkView : NSControl
@property (nonatomic, strong) NSImage *image;
@property (copy) void (^hoverChanged)(BOOL hovered);
- (void)resetEasterEgg;
@end
