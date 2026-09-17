#import <Cocoa/Cocoa.h>
@class AudioEngine;
@interface EffectsController : NSWindowController <NSWindowDelegate>
- (instancetype)initWithEngine:(AudioEngine *)engine;
- (void)show;
@end
