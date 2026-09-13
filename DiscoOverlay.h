#import <Foundation/Foundation.h>

@interface DiscoOverlayController : NSObject
@property (copy) void (^cancelHandler)(void);
- (void)show;
- (void)hide;
- (void)cancel;
@end
