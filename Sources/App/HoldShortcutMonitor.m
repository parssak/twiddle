#import "HoldShortcutMonitor.h"
#import <CoreGraphics/CoreGraphics.h>

@interface HoldShortcutMonitor () {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
    BOOL _held, _keyDown, _functionHeld;
    NSInteger _keyCode;
    CGEventFlags _modifiers;
}
@property (readwrite, copy) NSString *errorMessage;
- (void)receiveType:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef shortcutEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    [(__bridge HoldShortcutMonitor *)context receiveType:type event:event];
    return event;
}

@implementation HoldShortcutMonitor
- (instancetype)init {
    if ((self = [super init])) _keyCode = -1;
    return self;
}
- (void)releaseHeld {
    _keyDown = NO;
    _functionHeld = NO;
    BOOL wasHeld = _held;
    _held = NO;
    if (wasHeld && self.changed) self.changed(NO);
}
- (void)setKeyCode:(NSInteger)keyCode modifiers:(CGEventFlags)modifiers {
    [self releaseHeld];
    _keyCode = keyCode;
    _modifiers = modifiers;
}
- (void)setRecording:(BOOL)recording {
    _recording = recording;
    [self releaseHeld];
}
- (BOOL)configured { return _keyCode >= 0 || _modifiers != 0; }
- (BOOL)enabled { return _tap && CGEventTapIsEnabled(_tap); }
- (BOOL)enableRequestingPermission:(BOOL)request {
    if (!self.configured) { [self disable]; self.errorMessage = nil; return NO; }
    if (self.enabled) return YES;
    [self disable];
    if (!CGPreflightListenEventAccess() && !(request && CGRequestListenEventAccess())) {
        self.errorMessage = @"Allow Twiddle in System Settings → Privacy & Security → Input Monitoring, then reopen it.";
        return NO;
    }
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
        CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp), shortcutEvent, (__bridge void *)self);
    if (!_tap) {
        self.errorMessage = @"Shortcut listener unavailable. Check Input Monitoring permission and reopen Twiddle.";
        return NO;
    }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    if (!_source) { [self disable]; self.errorMessage = @"Could not start the shortcut listener."; return NO; }
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
    self.errorMessage = nil;
    return YES;
}
- (void)receiveType:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        [self releaseHeld];
        if (_tap) CGEventTapEnable(_tap, true);
        return;
    }
    if (_recording || (type != kCGEventFlagsChanged && type != kCGEventKeyDown && type != kCGEventKeyUp)) return;
    if (type != kCGEventFlagsChanged && CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == _keyCode) {
        if (type == kCGEventKeyUp) _keyDown = NO;
        else if (!CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat)) _keyDown = YES;
    }
    // Arrow and function-key events can carry SecondaryFn without a physical Fn press.
    // Only flagsChanged is evidence of that modifier being held.
    if (type == kCGEventFlagsChanged) _functionHeld = (CGEventGetFlags(event) & kCGEventFlagMaskSecondaryFn) != 0;
    else if (_keyCode < 0) return;
    CGEventFlags flags = CGEventGetFlags(event) & ~kCGEventFlagMaskSecondaryFn;
    if (_functionHeld) flags |= kCGEventFlagMaskSecondaryFn;
    BOOL modifiersHeld = (flags & _modifiers) == _modifiers;
    BOOL held = modifiersHeld && (_keyCode < 0 ? _modifiers != 0 : _keyDown);
    if (held == _held) return;
    _held = held;
    if (self.changed) self.changed(held);
}
- (void)disable {
    [self releaseHeld];
    if (_source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
        _source = NULL;
    }
    if (_tap) { CFMachPortInvalidate(_tap); CFRelease(_tap); _tap = NULL; }
}
- (void)dealloc { [self disable]; }
@end
