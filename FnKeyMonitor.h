#import <Foundation/Foundation.h>

// Listens only to modifier changes; does not intercept or record typed keys.
@interface FnKeyMonitor : NSObject
@property (copy) void (^changed)(BOOL held);
@property (readonly) BOOL enabled;
@property (readonly, copy) NSString *errorMessage;
- (BOOL)enableRequestingPermission:(BOOL)request;
- (void)disable;
@end
