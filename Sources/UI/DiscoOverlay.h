#import <Foundation/Foundation.h>

@interface DiscoOverlayController : NSObject
@property (copy) void (^cancelHandler)(void);
@property (copy) void (^activeChanged)(BOOL active);
- (void)show;
- (void)hide;
- (void)cancel;
@end
