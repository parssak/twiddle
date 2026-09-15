#import <Foundation/Foundation.h>

@interface SpotifyNowPlaying : NSObject
- (void)refreshDetailsWithCompletion:(void (^)(NSString *title, NSString *artist, BOOL playing, NSString *artworkURL))completion;
- (void)refreshWithCompletion:(void (^)(NSString *track))completion;
@end
