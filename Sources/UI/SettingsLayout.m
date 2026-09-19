#import "SettingsLayout.h"

// The document has a top origin; child pages keep their existing control coordinates.
@implementation SettingsPageDocument
- (BOOL)isFlipped { return YES; }
@end

@implementation SettingsNavigationTable
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
@end

const CGFloat SettingsPageWidth = 490, SettingsPageHeight = 640;
const CGFloat SettingsCardInset = 28, SettingsContentInset = 48, SettingsContentWidth = 394;
const CGFloat SettingsDescriptionOffset = 18;

void addSettingsCard(NSView *page, CGFloat y, CGFloat height) {
    NSBox *card = [[NSBox alloc] initWithFrame:NSMakeRect(SettingsCardInset, y,
        SettingsPageWidth - 2 * SettingsCardInset, height)];
    card.titlePosition = NSNoTitle;
    [page addSubview:card];
}
void addSettingsSeparator(NSView *page, CGFloat y) {
    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(SettingsContentInset, y, SettingsContentWidth, 1)];
    divider.boxType = NSBoxSeparator;
    [page addSubview:divider];
}
NSTextField *addSettingsRowTitle(NSView *page, NSString *title, CGFloat center, CGFloat width, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:13 weight:weight];
    CGFloat height = label.intrinsicContentSize.height;
    label.frame = NSMakeRect(SettingsContentInset, center - height / 2, width, height);
    [page addSubview:label];
    return label;
}
