#import <Foundation/Foundation.h>

// Main-thread lifecycle; the real-time callback only measures sample levels.
@interface PlaybackActivity : NSObject
@property (readonly, getter=isMonitoring) BOOL monitoring;
@property (readonly) BOOL audible;
@property (readonly, copy) NSString *errorMessage;
- (void)updateProcesses:(NSArray<NSNumber *> *)processes;
- (void)stop;
@end
