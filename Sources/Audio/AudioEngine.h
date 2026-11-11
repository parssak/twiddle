#import <Foundation/Foundation.h>
#import "NativeEffects.h"

// Main-thread API. Only the internal audio callback touches DSP state.
@interface AudioEngine : NSObject
@property float target;
@property BOOL tapeStop;
@property float reverb, pitch;
// Applies macOS-style call ducking to the replayed apps while another app runs voice chat.
@property BOOL voiceChatDucking;
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
