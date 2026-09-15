#import <Cocoa/Cocoa.h>

@interface SettingsController : NSWindowController <NSWindowDelegate>
@property (copy) NSString *shortcutTitle;
@property (nonatomic) double presetValue;
@property (copy) void (^presetChanged)(double value);
@property (copy) void (^menuBarSettingsRequested)(void);
@property (copy) void (^shortcutAccessRequested)(void);
@property (copy) void (^colorsChanged)(void);
@property (copy) void (^microphoneChanged)(void);
@property (copy) void (^discoChanged)(BOOL active);
@property (copy) void (^hapticsChanged)(BOOL enabled);
@property (copy) void (^appsChanged)(void);
@property (copy) void (^shortcutChanged)(NSInteger keyCode, NSEventModifierFlags modifiers, NSString *title);
@property (copy) void (^recordingChanged)(BOOL recording);
- (void)show;
- (void)updateShortcutAccess:(BOOL)granted ready:(BOOL)ready error:(NSString *)error;
- (void)setDiscoEnabled:(BOOL)enabled;
- (void)showApps:(id)sender;
@end
