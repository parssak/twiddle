#import <Cocoa/Cocoa.h>

@interface ShortcutRecorder : NSButton
@property (nonatomic, copy) NSString *shortcutTitle;
@property (copy) void (^shortcutChanged)(NSInteger keyCode, NSEventModifierFlags modifiers, NSString *title);
@property (copy) void (^recordingChanged)(BOOL recording);
- (void)cancelRecording;
- (void)clearShortcut:(id)sender;
@end
