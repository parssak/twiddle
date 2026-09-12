#import <Cocoa/Cocoa.h>

@interface FilterKnob : NSControl
@property (nonatomic) BOOL editingPreset;
@property (nonatomic) SEL resetAction;
@end
