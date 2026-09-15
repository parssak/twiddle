#import "ShortcutRecorder.h"

static NSEventModifierFlags shortcutFlags(NSEventModifierFlags flags) {
    return flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption |
                    NSEventModifierFlagShift | NSEventModifierFlagFunction);
}
static NSString *modifierTitle(NSEventModifierFlags flags) {
    NSMutableString *title = [NSMutableString new];
    if (flags & NSEventModifierFlagControl) [title appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption) [title appendString:@"⌥"];
    if (flags & NSEventModifierFlagShift) [title appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [title appendString:@"⌘"];
    if (flags & NSEventModifierFlagFunction) [title appendString:@"Fn"];
    return title;
}
static NSString *keyTitle(NSEvent *event) {
    switch (event.keyCode) {
        case 36: return @"↩"; case 48: return @"⇥"; case 49: return @"Space";
        case 51: return @"⌫"; case 117: return @"⌦";
        case 123: return @"←"; case 124: return @"→"; case 125: return @"↓"; case 126: return @"↑";
    }
    NSString *characters = [event charactersByApplyingModifiers:0];
    if (characters.length) {
        unichar c = [characters characterAtIndex:0];
        if (c >= NSF1FunctionKey && c <= NSF35FunctionKey) return [NSString stringWithFormat:@"F%d", c - NSF1FunctionKey + 1];
        if (c < 0xF700) return characters.uppercaseString;
    }
    return [NSString stringWithFormat:@"Key %hu", event.keyCode];
}

@implementation ShortcutRecorder {
    id _eventMonitor;
    NSEventModifierFlags _recordedFlags;
    NSEvent *_recordedKey;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.shortcutTitle = @"None";
        self.target = self;
        self.action = @selector(toggleRecording:);
    }
    return self;
}
- (void)setShortcutTitle:(NSString *)title {
    _shortcutTitle = [title copy];
    if (!_eventMonitor) self.title = title ?: @"None";
}
- (void)cancelRecording {
    if (!_eventMonitor) return;
    [NSEvent removeMonitor:_eventMonitor];
    _eventMonitor = nil;
    _recordedKey = nil;
    self.title = self.shortcutTitle ?: @"None";
    if (self.recordingChanged) self.recordingChanged(NO);
}
- (void)finishKeyCode:(NSInteger)keyCode modifiers:(NSEventModifierFlags)flags title:(NSString *)title {
    self.shortcutTitle = title;
    if (self.shortcutChanged) self.shortcutChanged(keyCode, flags, title);
    [self cancelRecording];
}
- (void)clearShortcut:(id)sender {
    [self cancelRecording];
    self.shortcutTitle = @"None";
    self.title = self.shortcutTitle;
    if (self.shortcutChanged) self.shortcutChanged(-1, 0, self.shortcutTitle);
}
- (void)toggleRecording:(id)sender {
    if (_eventMonitor) { [self cancelRecording]; return; }
    _recordedFlags = 0;
    self.title = @"Press keys…";
    if (self.recordingChanged) self.recordingChanged(YES);
    __weak ShortcutRecorder *weakSelf = self;
    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged
        handler:^NSEvent *(NSEvent *event) {
            ShortcutRecorder *self = weakSelf;
            if (!self || !self.window.keyWindow) return event;
            if (event.type == NSEventTypeKeyDown) {
                if (event.keyCode == 53) { [self cancelRecording]; return nil; }
                if (event.isARepeat || self->_recordedKey) return nil;
                NSEventModifierFlags flags = shortcutFlags(event.modifierFlags);
                // Arrow/function keys also carry the Function flag without a physical Fn press.
                if (!(self->_recordedFlags & NSEventModifierFlagFunction)) flags &= ~NSEventModifierFlagFunction;
                self->_recordedKey = event;
                self->_recordedFlags = flags;
                self.title = [modifierTitle(flags) stringByAppendingString:keyTitle(event)];
                // Keep consuming repeats until release so recording cannot leak
                // an unhandled key into the window and play the alert sound.
            } else if (event.type == NSEventTypeKeyUp) {
                if (self->_recordedKey && event.keyCode == self->_recordedKey.keyCode)
                    [self finishKeyCode:event.keyCode modifiers:self->_recordedFlags title:self.title];
            } else if (!self->_recordedKey) {
                NSEventModifierFlags flags = shortcutFlags(event.modifierFlags);
                if (flags) self->_recordedFlags |= flags;
                else if (self->_recordedFlags) {
                    [self finishKeyCode:-1 modifiers:self->_recordedFlags title:modifierTitle(self->_recordedFlags)];
                }
            }
            return nil;
        }];
}
- (void)dealloc { if (_eventMonitor) [NSEvent removeMonitor:_eventMonitor]; }
@end
