#import <Cocoa/Cocoa.h>

@interface SettingsController : NSWindowController <NSWindowDelegate>
@property (copy) NSString *selectedBundle;
@property (copy) NSString *shortcutTitle;
@property (nonatomic) double presetValue;
@property (copy) void (^presetChanged)(double value);
@property (copy) void (^colorsChanged)(void);
@property (copy) void (^wisprChanged)(BOOL enabled);
@property (copy) void (^hapticsChanged)(BOOL enabled);
@property (copy) void (^appChanged)(NSString *bundle);
@property (copy) void (^shortcutChanged)(NSInteger keyCode, NSEventModifierFlags modifiers, NSString *title);
@property (copy) void (^recordingChanged)(BOOL recording);
+ (NSString *)nameForBundle:(NSString *)bundle;
+ (NSImage *)iconForBundle:(NSString *)bundle;
- (void)show;
@end
