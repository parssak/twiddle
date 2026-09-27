#import <Cocoa/Cocoa.h>

@interface OnboardingController : NSWindowController
@property (nonatomic) BOOL firstRun;
@property (nonatomic) BOOL audioReady;
@property (nonatomic) BOOL shortcutsReady;
@property (copy) NSString *audioError;
@property (copy) void (^audioRequested)(void);
@property (copy) void (^shortcutsRequested)(void);
@property (copy) void (^finished)(BOOL openAtLogin);
- (void)show;
- (void)refresh;
- (BOOL)consumeAudioSettingsOpened;
@end
