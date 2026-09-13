#import "GlobalFilterHotkeys.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <IOKit/hidsystem/IOLLEvent.h>

@interface GlobalFilterHotkeys () {
    EventHandlerRef _handler;
    EventHotKeyRef _hotkeys[3];
    CFMachPortRef _mediaTap;
    CFRunLoopSourceRef _mediaSource;
}
@property (readwrite, copy) NSString *errorMessage;
- (BOOL)receiveMediaEvent:(NSEvent *)event;
- (void)reenableMediaTap;
@end

static OSStatus filterHotkeyPressed(EventHandlerCallRef nextHandler, EventRef event, void *context) {
    EventHotKeyID identifier = {0};
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
        NULL, sizeof(identifier), NULL, &identifier);
    if (status != noErr || identifier.signature != 'Twdl') return eventNotHandledErr;
    GlobalFilterHotkeys *hotkeys = (__bridge GlobalFilterHotkeys *)context;
    GlobalFilterHotkeyAction action = (GlobalFilterHotkeyAction)identifier.id;
    if (action < GlobalFilterHotkeyToggle || action > GlobalFilterHotkeyIncrease) return eventNotHandledErr;
    if (hotkeys.performed) hotkeys.performed(action);
    return noErr;
}

static CGEventRef mediaKeyEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    GlobalFilterHotkeys *hotkeys = (__bridge GlobalFilterHotkeys *)context;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        [hotkeys reenableMediaTap];
        return event;
    }
    NSEvent *appKitEvent = [NSEvent eventWithCGEvent:event];
    return [hotkeys receiveMediaEvent:appKitEvent] ? NULL : event;
}

@implementation GlobalFilterHotkeys
- (BOOL)isEnabled { return _handler != NULL && _mediaTap != NULL; }
- (BOOL)start {
    if (self.enabled) return YES;
    if (!_handler) {
        EventTypeSpec type = {kEventClassKeyboard, kEventHotKeyPressed};
        OSStatus status = InstallEventHandler(GetApplicationEventTarget(), filterHotkeyPressed,
            1, &type, (__bridge void *)self, &_handler);
        if (status != noErr) {
            self.errorMessage = [NSString stringWithFormat:@"Could not install global filter shortcuts (%d).", status];
            [self stop];
            return NO;
        }
        const UInt32 keys[] = {kVK_F10, kVK_F11, kVK_F12};
        for (NSUInteger i = 0; i < 3; i++) {
            EventHotKeyID identifier = {.signature = 'Twdl', .id = (UInt32)i + 1};
            status = RegisterEventHotKey(keys[i], optionKey, identifier, GetApplicationEventTarget(),
                kEventHotKeyExclusive, &_hotkeys[i]);
            if (status != noErr) {
                self.errorMessage = [NSString stringWithFormat:@"Could not register ⌥F%lu (%d).", i + 10, status];
                [self stop];
                return NO;
            }
        }
    }
    if (!CGPreflightPostEventAccess() && !CGRequestPostEventAccess()) {
        self.errorMessage = @"Allow Twiddle in System Settings → Privacy & Security → Accessibility to use the top-row shortcuts without Fn.";
        return NO;
    }
    _mediaTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
        CGEventMaskBit(NX_SYSDEFINED), mediaKeyEvent, (__bridge void *)self);
    if (!_mediaTap) {
        self.errorMessage = @"Could not capture the top-row media keys. Check Accessibility permission and reopen Twiddle.";
        return NO;
    }
    _mediaSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _mediaTap, 0);
    if (!_mediaSource) {
        CFMachPortInvalidate(_mediaTap);
        CFRelease(_mediaTap);
        _mediaTap = NULL;
        self.errorMessage = @"Could not start the top-row shortcut listener.";
        return NO;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), _mediaSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_mediaTap, true);
    self.errorMessage = nil;
    return YES;
}
- (BOOL)receiveMediaEvent:(NSEvent *)event {
    if (event.type != NSEventTypeSystemDefined || event.subtype != NX_SUBTYPE_AUX_CONTROL_BUTTONS) return NO;
    NSEventModifierFlags relevant = event.modifierFlags & (NSEventModifierFlagCommand |
        NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    if (relevant != NSEventModifierFlagOption) return NO;
    uint32_t data = (uint32_t)event.data1;
    unsigned key = data >> 16;
    unsigned state = (data >> 8) & 0xff;
    if (state != NX_KEYDOWN && state != NX_KEYUP) return NO;
    GlobalFilterHotkeyAction action;
    if (key == NX_KEYTYPE_MUTE) action = GlobalFilterHotkeyToggle;
    else if (key == NX_KEYTYPE_SOUND_DOWN) action = GlobalFilterHotkeyDecrease;
    else if (key == NX_KEYTYPE_SOUND_UP) action = GlobalFilterHotkeyIncrease;
    else return NO;
    BOOL repeat = (data & 1) != 0;
    if (state == NX_KEYDOWN && (!repeat || action != GlobalFilterHotkeyToggle) && self.performed)
        self.performed(action);
    return YES;
}
- (void)reenableMediaTap { if (_mediaTap) CGEventTapEnable(_mediaTap, true); }
- (void)stop {
    if (_mediaSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _mediaSource, kCFRunLoopCommonModes);
        CFRelease(_mediaSource);
        _mediaSource = NULL;
    }
    if (_mediaTap) {
        CFMachPortInvalidate(_mediaTap);
        CFRelease(_mediaTap);
        _mediaTap = NULL;
    }
    for (NSUInteger i = 0; i < 3; i++) {
        if (_hotkeys[i]) {
            UnregisterEventHotKey(_hotkeys[i]);
            _hotkeys[i] = NULL;
        }
    }
    if (_handler) {
        RemoveEventHandler(_handler);
        _handler = NULL;
    }
}
- (void)dealloc { [self stop]; }
@end
