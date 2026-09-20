#import "AppDelegate.h"
#import "AudioEngine.h"
#import "PlaybackActivity.h"
#import "MarqueeLabel.h"

@interface AppDelegate (EnergyTests)
- (void)updateControl;
- (void)refresh:(NSTimer *)timer;
- (void)updateAutomaticTriggers;
- (void)refreshShortcutAccess;
- (NSDictionary *)performCLICommand:(NSDictionary *)request;
- (void)suspend:(NSNotification *)notification;
- (void)resume:(NSNotification *)notification;
@end

// Exercise scheduling without opening audio devices, windows, or event taps.
@interface EnergyTestPlayback : PlaybackActivity
@property BOOL testMonitoring;
@end
@implementation EnergyTestPlayback
- (BOOL)isMonitoring { return self.testMonitoring; }
- (BOOL)audible { return NO; }
@end

@interface EnergyTestDelegate : AppDelegate
@property unsigned activityRefreshes, accessRefreshes;
@end
@implementation EnergyTestDelegate
- (void)updateAutomaticTriggers { self.activityRefreshes++; [self updateControl]; }
- (void)refreshShortcutAccess { self.accessRefreshes++; }
@end

int energyTests(void) {
    EnergyTestDelegate *delegate = [EnergyTestDelegate new];
    NSNotification *termination = [NSNotification notificationWithName:NSApplicationWillTerminateNotification object:nil];
    EnergyTestPlayback *playback = [EnergyTestPlayback new];
    [delegate setValue:playback forKey:@"playbackActivity"];
    [delegate setValue:[NSTextField labelWithString:@""] forKey:@"readout"];
    [delegate setValue:[[MarqueeLabel alloc] initWithFrame:NSZeroRect] forKey:@"nowPlayingReadout"];
#define CHECK_ENERGY(c) do { if (!(c)) { fprintf(stderr, "Energy check failed: %s line %d\n", #c, __LINE__); [delegate applicationWillTerminate:termination]; return 1; } } while (0)
    [delegate updateControl];
    NSTimer *idle = [delegate valueForKey:@"timer"];
    CHECK_ENERGY(idle.valid && idle.timeInterval == .25 && idle.tolerance > 0);
    [delegate updateControl];
    CHECK_ENERGY([delegate valueForKey:@"timer"] == idle);

    playback.testMonitoring = YES;
    [delegate updateControl];
    CHECK_ENERGY(!idle.valid && [[delegate valueForKey:@"timer"] timeInterval] == 1.0 / 60);
    playback.testMonitoring = NO;
    [delegate updateControl];
    CHECK_ENERGY([[delegate valueForKey:@"timer"] timeInterval] == .25);

    [delegate performCLICommand:@{@"command": @"set", @"value": @.6}];
    [delegate performCLICommand:@{@"command": @"reset"}];
    CHECK_ENERGY([[delegate valueForKey:@"timer"] timeInterval] == 1.0 / 60);
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
    CHECK_ENERGY([[delegate valueForKey:@"timer"] timeInterval] == .25);

    // Background scans use elapsed time even when the animation cadence changes.
    [delegate setValue:@0 forKey:@"nextActivityRefresh"];
    [delegate setValue:@0 forKey:@"nextMetadataRefresh"];
    delegate.activityRefreshes = delegate.accessRefreshes = 0;
    for (unsigned i = 0; i < 100; i++) [delegate refresh:nil];
    CHECK_ENERGY(delegate.activityRefreshes == 1 && delegate.accessRefreshes == 1);
    [delegate suspend:nil];
    CHECK_ENERGY([delegate valueForKey:@"timer"] == nil);
    unsigned refreshes = delegate.activityRefreshes;
    [delegate refresh:nil];
    CHECK_ENERGY(delegate.activityRefreshes == refreshes);
    [delegate resume:nil];
    CHECK_ENERGY([[delegate valueForKey:@"timer"] timeInterval] == .25);
    [delegate applicationWillTerminate:termination];
    puts("Energy: idle cadence, playback detection, transition completion, scan deadlines, suspend/resume passed.");
    return 0;
#undef CHECK_ENERGY
}
