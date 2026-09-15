#import <Foundation/Foundation.h>

// Main-thread API. Only the internal audio callback touches DSP state.
@interface AudioEngine : NSObject
@property float target;
@property (readonly) float peak;
@property (readonly) unsigned callbacks;
@property (readonly) BOOL running;
@property (readonly, copy) NSString *outputName;
@property (readonly, copy) NSString *errorMessage;
// nil captures all apps; an empty set is rejected.
- (BOOL)startWithBundles:(NSSet<NSString *> *)bundles probe:(BOOL)probe;
- (BOOL)checkRoute;
- (void)stop;
@end
