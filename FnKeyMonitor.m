#import "FnKeyMonitor.h"
#import <CoreGraphics/CoreGraphics.h>

@interface FnKeyMonitor () {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
    BOOL _held;
}
@property (readwrite, copy) NSString *errorMessage;
- (void)receiveType:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef modifierEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    [(__bridge FnKeyMonitor *)context receiveType:type event:event];
    return event;
}

@implementation FnKeyMonitor
- (BOOL)enabled { return _tap && CGEventTapIsEnabled(_tap); }
- (BOOL)enableRequestingPermission:(BOOL)request {
    if (self.enabled) return YES;
    [self disable];
    if (!CGPreflightListenEventAccess() && !(request && CGRequestListenEventAccess())) {
        self.errorMessage = @"Allow Lowpasser in System Settings → Privacy & Security → Input Monitoring, then reopen it.";
        return NO;
    }
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
        CGEventMaskBit(kCGEventFlagsChanged), modifierEvent, (__bridge void *)self);
    if (!_tap) {
        self.errorMessage = @"Fn listener unavailable. Check Input Monitoring permission and reopen Lowpasser.";
        return NO;
    }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    if (!_source) { [self disable]; self.errorMessage = @"Could not start the Fn listener."; return NO; }
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
    self.errorMessage = nil;
    return YES;
}
- (void)receiveType:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_held && self.changed) self.changed(NO);
        _held = NO;
        CGEventTapEnable(_tap, true);
        return;
    }
    if (type != kCGEventFlagsChanged) return;
    BOOL held = (CGEventGetFlags(event) & kCGEventFlagMaskSecondaryFn) != 0;
    if (held == _held) return;
    _held = held;
    if (self.changed) self.changed(held);
}
- (void)disable {
    if (_held && self.changed) self.changed(NO);
    _held = NO;
    if (_source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
        _source = NULL;
    }
    if (_tap) { CFMachPortInvalidate(_tap); CFRelease(_tap); _tap = NULL; }
}
- (void)dealloc { [self disable]; }
@end
