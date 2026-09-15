#import <Cocoa/Cocoa.h>

// Shared app grid with Finder drops and per-app removal.
@interface AppGridView : NSView
@property (copy) NSString *preferenceKey;
@property (copy) void (^changed)(void);
- (void)reload;
- (void)addApps:(id)sender;
@end
