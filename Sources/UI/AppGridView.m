#import "AppGridView.h"
#import "ApplicationInfo.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat TileWidth = 56, TileHeight = 70, TileGap = 20, IconSize = 48;

@interface AppGridItem : NSButton
@property (copy) NSString *bundle;
@end
@implementation AppGridItem {
    NSTrackingArea *_tracking;
    BOOL _hovered;
}
- (BOOL)isFlipped { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)event { _hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect icon = NSMakeRect((NSWidth(self.bounds) - IconSize) / 2, 20, IconSize, IconSize);
    [self.image drawInRect:icon fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
        fraction:self.highlighted ? .65 : 1 respectFlipped:YES hints:nil];
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.title drawWithRect:NSMakeRect(0, 0, NSWidth(self.bounds), 16)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11],
            NSForegroundColorAttributeName: NSColor.labelColor, NSParagraphStyleAttributeName: style}];
    if (_hovered || self.window.firstResponder == self) {
        NSRect badge = NSMakeRect(NSMaxX(icon) - 16, NSMaxY(icon) - 20, 20, 20);
        [NSColor.windowBackgroundColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(badge, 2, 2)] fill];
        NSImage *mark = [[NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:nil]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.secondaryLabelColor]]];
        [mark drawInRect:badge fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    }
}
@end

@interface AppGridDocument : NSView
@property (copy) NSArray<NSString *> *(^readBundles)(NSArray<NSURL *> *urls);
@property (copy) void (^addURLs)(NSArray<NSURL *> *urls);
@end
@implementation AppGridDocument
- (BOOL)isFlipped { return YES; }
- (NSArray<NSURL *> *)URLsFromDrag:(id<NSDraggingInfo>)info {
    return [info.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
    return self.readBundles([self URLsFromDrag:info]).count ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    NSArray *urls = [self URLsFromDrag:info];
    if (!self.readBundles(urls).count) return NO;
    self.addURLs(urls);
    return YES;
}
@end

@implementation AppGridView {
    NSScrollView *_scroll;
    AppGridDocument *_grid;
    NSMutableArray<AppGridItem *> *_items;
    NSUInteger _generation;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _items = [NSMutableArray new];
        _scroll = [[NSScrollView alloc] initWithFrame:self.bounds];
        _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _scroll.hasVerticalScroller = YES;
        _scroll.borderType = NSNoBorder;
        _scroll.drawsBackground = NO;
        _scroll.scrollerStyle = NSScrollerStyleOverlay;
        _grid = [[AppGridDocument alloc] initWithFrame:_scroll.bounds];
        [_grid registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        __weak AppGridView *weakSelf = self;
        _grid.readBundles = ^NSArray *(NSArray *urls) { return [weakSelf bundlesFromURLs:urls]; };
        _grid.addURLs = ^(NSArray *urls) { [weakSelf addURLs:urls]; };
        _scroll.documentView = _grid;
        [self addSubview:_scroll];
    }
    return self;
}
- (NSArray<NSString *> *)bundles { return [NSUserDefaults.standardUserDefaults stringArrayForKey:self.preferenceKey] ?: @[]; }
- (void)reload {
    _generation++;
    for (NSView *item in _items) [item removeFromSuperview];
    [_items removeAllObjects];
    for (NSString *bundle in self.bundles) {
        AppGridItem *item = [[AppGridItem alloc] initWithFrame:NSMakeRect(0, 0, TileWidth, TileHeight)];
        item.bundle = bundle;
        item.title = [ApplicationInfo nameForBundle:bundle];
        item.image = [[ApplicationInfo iconForBundle:bundle] copy];
        item.image.size = NSMakeSize(IconSize, IconSize);
        item.bordered = NO;
        item.wantsLayer = YES;
        item.target = self;
        item.action = @selector(removeApp:);
        item.accessibilityLabel = [@"Remove " stringByAppendingString:item.title];
        item.toolTip = item.accessibilityLabel;
        [_grid addSubview:item];
        [_items addObject:item];
    }
    [self layoutItems:NO];
}
- (void)layout {
    [super layout];
    [self layoutItems:NO];
}
- (void)layoutItems:(BOOL)animated {
    CGFloat width = NSWidth(_scroll.contentView.bounds);
    NSUInteger columns = MAX(1, (NSUInteger)floor((width + TileGap) / (TileWidth + TileGap)));
    NSUInteger rows = (_items.count + columns - 1) / columns;
    _grid.frame = NSMakeRect(0, 0, width, MAX(NSHeight(_scroll.contentView.bounds), rows * (TileHeight + TileGap) - (rows ? TileGap : 0)));
    for (NSUInteger i = 0; i < _items.count; i++) {
        NSRect frame = NSMakeRect((i % columns) * (TileWidth + TileGap), (i / columns) * (TileHeight + TileGap), TileWidth, TileHeight);
        if (animated) _items[i].animator.frame = frame;
        else _items[i].frame = frame;
    }
}
- (NSArray<NSString *> *)bundlesFromURLs:(NSArray<NSURL *> *)urls {
    NSMutableOrderedSet *bundles = [NSMutableOrderedSet new];
    for (NSURL *url in urls) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"app"]) continue;
        NSString *bundle = [NSBundle bundleWithURL:url].bundleIdentifier;
        if (bundle.length && ![bundle isEqualToString:NSBundle.mainBundle.bundleIdentifier]) [bundles addObject:bundle];
    }
    return bundles.array;
}
- (void)addURLs:(NSArray<NSURL *> *)urls {
    NSMutableOrderedSet *bundles = [NSMutableOrderedSet orderedSetWithArray:self.bundles];
    [bundles addObjectsFromArray:[self bundlesFromURLs:urls]];
    [NSUserDefaults.standardUserDefaults setObject:bundles.array forKey:self.preferenceKey];
    [self reload];
    if (self.changed) self.changed();
}
- (void)addApps:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) [self addURLs:panel.URLs];
    }];
}
- (void)removeApp:(AppGridItem *)item {
    if (!item.enabled) return;
    item.enabled = NO;
    NSString *bundle = item.bundle;
    NSUInteger generation = _generation;
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (!reduceMotion) {
        CABasicAnimation *shrink = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        shrink.fromValue = @1;
        shrink.toValue = @.05;
        shrink.duration = .18;
        [item.layer addAnimation:shrink forKey:@"remove"];
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = reduceMotion ? 0 : .18;
        item.animator.alphaValue = 0;
    } completionHandler:^{
        // A settings refresh or another edit must not delete a newly added tile.
        if (generation != self->_generation) return;
        NSMutableArray *bundles = [self.bundles mutableCopy];
        [bundles removeObject:bundle];
        [NSUserDefaults.standardUserDefaults setObject:bundles forKey:self.preferenceKey];
        [item removeFromSuperview];
        [self->_items removeObject:item];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = reduceMotion ? 0 : .18;
            [self layoutItems:YES];
        } completionHandler:nil];
        if (self.changed) self.changed();
    }];
}
@end
