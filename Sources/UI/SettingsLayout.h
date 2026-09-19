#import <Cocoa/Cocoa.h>

@interface SettingsPageDocument : NSView
@end
@interface SettingsNavigationTable : NSTableView
@end

extern const CGFloat SettingsPageWidth, SettingsPageHeight;
extern const CGFloat SettingsCardInset, SettingsContentInset, SettingsContentWidth;
extern const CGFloat SettingsDescriptionOffset;
void addSettingsCard(NSView *page, CGFloat y, CGFloat height);
void addSettingsSeparator(NSView *page, CGFloat y);
NSTextField *addSettingsRowTitle(NSView *page, NSString *title, CGFloat center, CGFloat width, NSFontWeight weight);
