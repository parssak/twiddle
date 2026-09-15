#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// A listen-only event tap. Key events are matched, never stored or suppressed.
@interface HoldShortcutMonitor : NSObject
@property (copy) void (^changed)(BOOL held);
@property (readonly) BOOL enabled;
@property (readonly) BOOL configured;
@property (readonly, copy) NSString *errorMessage;
@property (nonatomic) BOOL recording;
- (void)setKeyCode:(NSInteger)keyCode modifiers:(CGEventFlags)modifiers;
- (BOOL)enableRequestingPermission:(BOOL)request;
- (void)disable;
@end
