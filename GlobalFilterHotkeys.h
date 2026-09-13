#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, GlobalFilterHotkeyAction) {
    GlobalFilterHotkeyToggle = 1,
    GlobalFilterHotkeyDecrease,
    GlobalFilterHotkeyIncrease,
};

// Fixed, global controls that do not depend on the configurable hold shortcut.
@interface GlobalFilterHotkeys : NSObject
@property (copy) void (^performed)(GlobalFilterHotkeyAction action);
@property (readonly, getter=isEnabled) BOOL enabled;
@property (readonly, copy) NSString *errorMessage;
- (BOOL)start;
- (void)stop;
@end
