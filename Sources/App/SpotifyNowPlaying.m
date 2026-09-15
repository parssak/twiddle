#import "SpotifyNowPlaying.h"
#import <AppKit/AppKit.h>

@implementation SpotifyNowPlaying {
    dispatch_queue_t _queue;
    BOOL _refreshing;
}
- (instancetype)init {
    if ((self = [super init]))
        _queue = dispatch_queue_create("com.parssa.twiddle.spotify-metadata", DISPATCH_QUEUE_SERIAL);
    return self;
}
- (void)refreshWithCompletion:(void (^)(NSString *track))completion {
    [self refreshDetailsWithCompletion:^(NSString *title, NSString *artist, BOOL playing, NSString *artworkURL) {
        NSString *track = title.length && artist.length ? [NSString stringWithFormat:@"%@ · %@", title, artist] :
            title.length ? title : artist;
        completion(track);
    }];
}
- (void)refreshDetailsWithCompletion:(void (^)(NSString *title, NSString *artist, BOOL playing, NSString *artworkURL))completion {
    NSAssert(NSThread.isMainThread, @"Spotify metadata refreshes must start on the main thread");
    if (_refreshing) return;
    if (![NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.spotify.client"].count) {
        completion(nil, nil, NO, nil);
        return;
    }
    _refreshing = YES;
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *source = @"tell application id \"com.spotify.client\"\n"
                "if player state is stopped then return {}\n"
                "set playingTrack to current track\n"
                "return {name of playingTrack, artist of playingTrack, player state is playing, artwork url of playingTrack}\n"
                "end tell";
            NSDictionary *error = nil;
            NSAppleEventDescriptor *result = [[[NSAppleScript alloc] initWithSource:source]
                executeAndReturnError:&error];
            NSString *title = [result descriptorAtIndex:1].stringValue;
            NSString *artist = [result descriptorAtIndex:2].stringValue;
            BOOL playing = [result descriptorAtIndex:3].booleanValue;
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_refreshing = NO;
                completion(title, artist, playing, [result descriptorAtIndex:4].stringValue);
            });
        }
    });
}
@end
