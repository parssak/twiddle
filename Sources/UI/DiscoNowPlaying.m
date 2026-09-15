#import "DiscoNowPlaying.h"
#import "SpotifyNowPlaying.h"
#import "ViewAnimations.h"
#import "AlbumPalette.h"
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@interface DiscoTrackPanel : NSPanel
@property NSTextField *song;
@property NSTextField *artist;
@property NSImageView *artwork;
@property NSView *trackContent;
@property BOOL showing;
@property NSUInteger transition;
- (void)setShown:(BOOL)shown;
- (void)presentTitle:(NSString *)title artist:(NSString *)artist artwork:(NSImage *)image available:(BOOL)available;
- (void)setArtwork:(NSImage *)image available:(BOOL)available;
@end
@implementation DiscoTrackPanel {
    NSString *_nextTitle, *_nextArtist;
    NSImage *_nextArtwork;
    BOOL _nextArtworkAvailable;
    NSImageView *_outgoing;
    CALayer *_artworkClip, *_textClip;
}
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)setShown:(BOOL)shown {
    if (_showing == shown) return;
    _showing = shown;
    [_outgoing removeFromSuperview];
    _outgoing = nil;
    self.trackContent.alphaValue = 1;
    clearBlur(self.trackContent);
    NSUInteger transition = ++_transition;
    if (shown && !self.visible) {
        self.alphaValue = 0;
        [self orderFrontRegardless];
    }
    animateBlur(self.trackContent, shown ? 8 : 0, shown ? 0 : 8, .4);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = .4;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        self.animator.alphaValue = shown ? 1 : 0;
    } completionHandler:^{
        if (self.transition != transition) return;
        if (!shown) [self orderOut:nil];
        clearBlur(self.trackContent);
    }];
}
- (void)presentTitle:(NSString *)title artist:(NSString *)artist artwork:(NSImage *)image available:(BOOL)available {
    BOOL changed = ![_nextTitle isEqualToString:title] || ![_nextArtist isEqualToString:artist ?: @""];
    _nextTitle = [title copy];
    _nextArtist = [artist copy] ?: @"";
    _nextArtwork = image;
    _nextArtworkAvailable = available;
    if (!self.showing) {
        [self applyTrack];
        [self setShown:YES];
    } else if (changed) {
        NSUInteger transition = ++_transition;
        // Crossfade two complete compositions, rather than replacing text at a blackout.
        NSBitmapImageRep *bitmap = [self.trackContent bitmapImageRepForCachingDisplayInRect:self.trackContent.bounds];
        if (bitmap) [self.trackContent cacheDisplayInRect:self.trackContent.bounds toBitmapImageRep:bitmap];
        NSImage *snapshot = [[NSImage alloc] initWithSize:self.trackContent.bounds.size];
        if (bitmap) [snapshot addRepresentation:bitmap];
        [_outgoing removeFromSuperview];
        NSImageView *outgoing = [[NSImageView alloc] initWithFrame:self.trackContent.frame];
        outgoing.image = snapshot;
        outgoing.imageScaling = NSImageScaleAxesIndependently;
        outgoing.wantsLayer = YES;
        [self.contentView addSubview:outgoing positioned:NSWindowAbove relativeTo:self.trackContent];
        _outgoing = outgoing;
        [self applyTrack];
        self.trackContent.alphaValue = 0;
        animateBlur(outgoing, 0, 8, .38);
        animateBlur(self.trackContent, 8, 0, .38);
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = .38;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            outgoing.animator.alphaValue = 0;
            self.trackContent.animator.alphaValue = 1;
        } completionHandler:^{
            [outgoing removeFromSuperview];
            if (self.transition != transition) return;
            self->_outgoing = nil;
            clearBlur(self.trackContent);
        }];
    } else {
        [self applyTrack];
    }
}
- (void)applyTrack {
    self.song.stringValue = _nextTitle ?: @"";
    self.artist.stringValue = _nextArtist ?: @"";
    self.song.accessibilityLabel = [@"Now playing: " stringByAppendingString:self.song.stringValue];
    [self applyArtwork];
}
- (void)setArtwork:(NSImage *)image available:(BOOL)available {
    _nextArtwork = image;
    _nextArtworkAvailable = available;
    [self applyArtwork];
}
- (void)applyArtwork {
    NSImage *image = _nextArtwork;
    BOOL available = _nextArtworkAvailable;
    self.artwork.hidden = !available;
    self.artwork.image = image;
    CGFloat x = available ? 160 : 20;
    CGFloat width = NSWidth(self.trackContent.bounds)-x-20;
    CGFloat songHeight = self.song.intrinsicContentSize.height;
    CGFloat artistHeight = self.artist.stringValue.length ? self.artist.intrinsicContentSize.height : 0;
    CGFloat gap = artistHeight ? 5 : 0;
    CGFloat bottom = NSMidY(self.artwork.frame)-(songHeight+artistHeight+gap)/2;
    self.artist.frame = NSMakeRect(x, bottom, width, artistHeight);
    self.song.frame = NSMakeRect(x, bottom+artistHeight+gap, width, songHeight);
    // Clip after compositing the blurred incoming and outgoing layers. Clipping
    // only the image itself allows the parent blur to bleed beyond its corners.
    if (!_artworkClip) {
        CALayer *mask = [CALayer layer];
        _artworkClip = [CALayer layer];
        _artworkClip.backgroundColor = NSColor.whiteColor.CGColor;
        _artworkClip.cornerRadius = self.artwork.layer.cornerRadius;
        _artworkClip.cornerCurve = kCACornerCurveContinuous;
        _textClip = [CALayer layer];
        _textClip.backgroundColor = NSColor.whiteColor.CGColor;
        [mask addSublayer:_artworkClip];
        [mask addSublayer:_textClip];
        self.contentView.layer.mask = mask;
    }
    [CATransaction begin];
    CATransaction.disableActions = YES;
    self.contentView.layer.mask.frame = self.contentView.bounds;
    _artworkClip.frame = self.artwork.frame;
    _artworkClip.hidden = !available;
    CGFloat textLeft = available ? 150 : 0;
    _textClip.frame = NSMakeRect(textLeft, 0, NSWidth(self.contentView.bounds)-textLeft, NSHeight(self.contentView.bounds));
    [CATransaction commit];
}
@end

@implementation DiscoNowPlaying {
    SpotifyNowPlaying *_source;
    NSMutableArray<DiscoTrackPanel *> *_panels;
    NSTimer *_timer;
    NSUInteger _generation, _artworkGeneration;
    NSURLSessionDataTask *_artworkTask;
    NSString *_artworkURL;
    NSImage *_artwork;
    NSArray<NSColor *> *_artworkColors;
}
- (instancetype)init {
    if ((self = [super init])) {
        _source = [SpotifyNowPlaying new];
        _panels = [NSMutableArray new];
    }
    return self;
}
- (void)show {
    [self hide];
    for (NSScreen *screen in NSScreen.screens) {
        NSRect area = screen.visibleFrame;
        CGFloat width = fmin(760, NSWidth(area)-24);
        DiscoTrackPanel *panel = [[DiscoTrackPanel alloc] initWithContentRect:
            NSMakeRect(NSMinX(area)+12, NSMinY(area)+12, width, 168)
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO screen:screen];
        panel.opaque = NO;
        panel.backgroundColor = NSColor.clearColor;
        panel.hasShadow = NO;
        panel.ignoresMouseEvents = YES;
        panel.level = CGWindowLevelForKey(kCGScreenSaverWindowLevelKey)-1;
        panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary |
            NSWindowCollectionBehaviorIgnoresCycle;
        panel.contentView.wantsLayer = YES;
        panel.trackContent = [[NSView alloc] initWithFrame:panel.contentView.bounds];
        panel.trackContent.wantsLayer = YES;
        [panel.contentView addSubview:panel.trackContent];
        panel.artwork = [[NSImageView alloc] initWithFrame:NSMakeRect(20, 24, 120, 120)];
        panel.artwork.imageScaling = NSImageScaleProportionallyUpOrDown;
        panel.artwork.wantsLayer = YES;
        panel.artwork.layer.cornerRadius = 10;
        panel.artwork.layer.cornerCurve = kCACornerCurveContinuous;
        panel.artwork.layer.masksToBounds = YES;
        panel.artwork.layer.backgroundColor = [NSColor.whiteColor colorWithAlphaComponent:.08].CGColor;
        panel.artwork.accessibilityLabel = @"Album artwork";
        [panel.trackContent addSubview:panel.artwork];
        panel.song = [NSTextField labelWithString:@""];
        panel.song.font = [NSFont systemFontOfSize:32 weight:NSFontWeightSemibold];
        panel.song.textColor = NSColor.whiteColor;
        panel.artist = [NSTextField labelWithString:@""];
        panel.artist.font = [NSFont systemFontOfSize:20];
        panel.artist.textColor = [NSColor.whiteColor colorWithAlphaComponent:.65];
        for (NSTextField *label in @[panel.song, panel.artist]) {
            label.selectable = NO;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            [panel.trackContent addSubview:label];
        }
        [panel setArtwork:nil available:NO];
        [_panels addObject:panel];
    }
    __weak DiscoNowPlaying *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh];
    }];
    _timer.tolerance = .3;
    [self refresh];
}
- (void)loadArtwork:(NSString *)URLString {
    if ([_artworkURL isEqualToString:URLString]) {
        if (!_artworkTask && self.paletteChanged) self.paletteChanged(_artworkColors ?: @[]);
        return;
    }
    [_artworkTask cancel];
    _artworkTask = nil;
    NSUInteger artworkGeneration = ++_artworkGeneration;
    _artworkURL = [URLString copy];
    _artwork = nil;
    _artworkColors = nil;
    NSURL *url = [NSURL URLWithString:URLString ?: @""];
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) {
        if (self.paletteChanged) self.paletteChanged(@[]);
        return;
    }
    NSUInteger generation = _generation;
    __weak DiscoNowPlaying *weakSelf = self;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10;
    _artworkTask = [NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSImage *image = !error && data.length < 8*1024*1024 &&
                [(NSHTTPURLResponse *)response statusCode] == 200 ? [[NSImage alloc] initWithData:data] : nil;
            NSArray<NSColor *> *colors = albumPalette(image);
            dispatch_async(dispatch_get_main_queue(), ^{
                DiscoNowPlaying *self = weakSelf;
                if (!self || self->_generation != generation || self->_artworkGeneration != artworkGeneration) return;
                self->_artworkTask = nil;
                self->_artwork = image;
                self->_artworkColors = colors;
                if (self.paletteChanged) self.paletteChanged(colors);
                for (DiscoTrackPanel *panel in self->_panels) [panel setArtwork:image available:image != nil];
            });
        }];
    [_artworkTask resume];
}
- (void)refresh {
    NSUInteger generation = _generation;
    __weak DiscoNowPlaying *weakSelf = self;
    [_source refreshDetailsWithCompletion:^(NSString *title, NSString *artist, BOOL playing, NSString *artworkURL) {
        DiscoNowPlaying *self = weakSelf;
        if (!self || self->_generation != generation || !self->_timer) return;
        if (playing && title.length) [self loadArtwork:artworkURL];
        else if (self.paletteChanged) self.paletteChanged(@[]);
        for (DiscoTrackPanel *panel in self->_panels) {
            if (!playing || !title.length) { [panel setShown:NO]; continue; }
            [panel presentTitle:title artist:artist artwork:self->_artwork
                available:self->_artwork != nil || self->_artworkTask != nil];
        }
    }];
}
- (void)hide {
    _generation++;
    if (self.paletteChanged) self.paletteChanged(@[]);
    [_timer invalidate];
    _timer = nil;
    [_artworkTask cancel];
    _artworkTask = nil;
    _artworkURL = nil;
    _artwork = nil;
    _artworkColors = nil;
    for (DiscoTrackPanel *panel in _panels) [panel setShown:NO];
    [_panels removeAllObjects];
}
- (void)dealloc { [self hide]; }
@end
