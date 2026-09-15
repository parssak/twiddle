#import <Cocoa/Cocoa.h>

@interface ApplicationInfo : NSObject
+ (NSString *)nameForBundle:(NSString *)bundle;
+ (NSImage *)iconForBundle:(NSString *)bundle;
@end
