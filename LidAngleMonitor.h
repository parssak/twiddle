#import <Foundation/Foundation.h>

// Main-thread ownership; HID reads run on a private serial queue.
@interface LidAngleMonitor : NSObject
@property (nonatomic, readonly) double angle;
@property (nonatomic, readonly, getter=isAvailable) BOOL available;
- (void)start;
- (void)stop;
@end
