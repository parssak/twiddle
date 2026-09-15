#import "CreditView.h"
#import "HoverButton.h"

@implementation CreditView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        HoverButton *link = [[HoverButton alloc] initWithFrame:NSZeroRect];
        link.title = @"Parssa Kyanzadeh";
        link.font = [NSFont systemFontOfSize:10];
        link.target = self;
        link.action = @selector(openWebsite:);
        link.toolTip = @"parssak.com";
        link.accessibilityLabel = @"Parssa Kyanzadeh’s website";
        [self addSubview:link];
        [self layout];
        self.accessibilityLabel = @"Made for fun by Parssa Kyanzadeh";
    }
    return self;
}
- (void)openWebsite:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://parssak.com"]];
}
- (NSAttributedString *)prefix {
    return [[NSAttributedString alloc] initWithString:@"Made for fun by "
        attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10], NSForegroundColorAttributeName:NSColor.secondaryLabelColor}];
}
- (void)layout {
    [super layout];
    HoverButton *link = self.subviews.firstObject;
    NSDictionary *attributes = @{NSFontAttributeName:link.font};
    CGFloat prefixWidth = self.prefix.size.width;
    CGFloat nameWidth = [link.title sizeWithAttributes:attributes].width;
    CGFloat left = (NSWidth(self.bounds) - prefixWidth - nameWidth) / 2;
    // Hover padding overlaps the text layout, so it does not add a second word space.
    link.frame = NSMakeRect(left + prefixWidth - 6, 0, nameWidth + 12, NSHeight(self.bounds));
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    HoverButton *link = self.subviews.firstObject;
    NSAttributedString *prefix = self.prefix;
    NSSize size = prefix.size;
    [prefix drawAtPoint:NSMakePoint(NSMinX(link.frame) + 6 - size.width,
        (NSHeight(self.bounds) - size.height) / 2)];
}
@end
