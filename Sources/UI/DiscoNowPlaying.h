#import <Cocoa/Cocoa.h>

@interface DiscoNowPlaying : NSObject
@property (copy) void (^paletteChanged)(NSArray<NSColor *> *colors);
- (void)show;
- (void)hide;
@end
