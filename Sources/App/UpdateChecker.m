#import "UpdateChecker.h"
#import <Sparkle/Sparkle.h>

@interface UpdateChecker ()
@property SPUStandardUpdaterController *controller;
@end

@implementation UpdateChecker
- (instancetype)init {
    if ((self = [super init])) {
        self.controller = [[SPUStandardUpdaterController alloc]
            initWithStartingUpdater:YES updaterDelegate:nil userDriverDelegate:nil];
    }
    return self;
}
- (void)checkFromWindow:(NSWindow *)window {
    (void)window;
    [self.controller checkForUpdates:nil];
}
@end
