#import <Foundation/Foundation.h>

@interface SpotifyNowPlaying : NSObject
- (void)refreshWithCompletion:(void (^)(NSString *track))completion;
@end
