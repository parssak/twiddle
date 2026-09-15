#include "Filter.h"
#include "FilterControl.h"
#include "AudioActivity.h"
#include <stdio.h>
#import <Cocoa/Cocoa.h>
#import "HoldShortcutMonitor.h"
#import "GlobalFilterHotkeys.h"
#import "FilterKnob.h"
#import "AudioProcessActivity.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <IOKit/hidsystem/IOLLEvent.h>

// Exercise the same shortcut-event decoder without listening to or injecting
// events into the user's desktop.
@interface HoldShortcutMonitor (TestEvents)
- (void)receiveType:(CGEventType)type event:(CGEventRef)event;
@end

@interface GlobalFilterHotkeys (TestEvents)
- (BOOL)receiveMediaEvent:(NSEvent *)event;
@end

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "Failed: %s (line %d)\n", #condition, __LINE__); return 1; } } while (0)

static int controlTests(void) {
    FilterControl disco = {.baseline = .2, .preset = -.7};
    controlSetTrigger(&disco, PresetTriggerDisco, true, 1);
    CHECK(disco.held && fabs(controlValue(&disco, 2)+.7) < .00001);
    controlSetPreset(&disco, -.4, 2);
    CHECK(fabs(controlValue(&disco, 3)+.4) < .00001);
    controlSetTrigger(&disco, PresetTriggerMicrophone, true, 3);
    controlSetTrigger(&disco, PresetTriggerDisco, false, 4);
    CHECK(disco.held);
    controlSetTrigger(&disco, PresetTriggerMicrophone, false, 5);
    CHECK(!disco.held && fabs(controlValue(&disco, 6)-.2) < .00001);

    float quiet[] = {0, 0.0001f, -0.0001f, NAN, INFINITY};
    float sound[] = {0, -.002f, 0};
    CHECK(!audioSamplesAudible(quiet, 5));
    CHECK(audioSamplesAudible(sound, 3));
    CHECK(audioRecentlyAudible(.299));
    CHECK(!audioRecentlyAudible(.301));
    CHECK(!audioRecentlyAudible(-1));
    CHECK(audioProcessMatchesBundle(@"company.thebrowser.browser.helper", @"company.thebrowser.Browser"));
    CHECK(audioProcessMatchesBundle(@"company.thebrowser.Browser", @"company.thebrowser.Browser"));
    CHECK(!audioProcessMatchesBundle(@"company.thebrowser.browserother.helper", @"company.thebrowser.Browser"));
    CHECK(!audioProcessMatchesBundle(@"com.google.Chrome.helper", @"company.thebrowser.Browser"));
    CHECK(!audioProcessMatchesBundle(nil, @"company.thebrowser.Browser"));
    CHECK(!audioProcessMatchesBundle(@"company.thebrowser.browser.helper", @""));
    CHECK([[FilterKnob labelForValue:[FilterKnob defaultPresetValue]] isEqualToString:@"Low-pass · 1100 Hz"]);
    FilterControl c = {.preset = -.8};
    controlSetBaseline(&c, .3, 0);
    controlSetHeld(&c, true, 1);
    CHECK(c.held && fabs(controlValue(&c, 1) - .3) < 1e-6);
    CHECK(fabs(controlValue(&c, 1.09) + .25) < 1e-6);
    controlSetHeld(&c, true, 1.1); // Repeats must not overwrite the baseline.
    CHECK(fabs(controlValue(&c, 1.2) + .8) < 1e-6);
    controlSetHeld(&c, false, 2);
    CHECK(!c.held && fabs(controlValue(&c, 2) + .8) < 1e-6);
    CHECK(controlValue(&c, 2.09) > -.8 && controlValue(&c, 2.09) < .3);
    CHECK(fabs(controlValue(&c, 2.2) + .25) < 1e-6);
    CHECK(fabs(controlValue(&c, 2.45) - .3) < 1e-6);
    controlSetHeld(&c, true, 3);
    controlReset(&c, 3.1);
    CHECK(!c.held && c.baseline == 0);
    controlSetHeld(&c, false, 3.11); // Release after reset must not restore .3.
    CHECK(fabs(controlValue(&c, 3.3)) < 1e-6);
    controlSetBaseline(&c, -1, 4);
    controlReset(&c, 5);
    CHECK(controlValue(&c, 5) == -1); // No jump on reset.
    CHECK(fabs(controlValue(&c, 5.09) + .5) < 1e-6);
    controlSetBaseline(&c, .6, 5.1); // Dragging interrupts a reset immediately.
    CHECK(controlValue(&c, 5.3) == .6);
    controlSetPreset(&c, -.9, 6);
    CHECK(controlValue(&c, 6.2) == .6 && c.baseline == .6);
    controlSetHeld(&c, true, 7);
    CHECK(fabs(controlValue(&c, 7.2) + .9) < 1e-6);
    controlSetPreset(&c, -.4, 7.3); // Adjusting a held preset keeps the baseline intact.
    CHECK(fabs(controlValue(&c, 7.5) + .4) < 1e-6);
    controlSetHeld(&c, false, 8);
    CHECK(fabs(controlValue(&c, 8.5) - .6) < 1e-6);

    FilterControl stepped = {0};
    controlSetBaseline(&stepped, -.72, 0);
    controlStepBaseline(&stepped, -1, 1);
    CHECK(fabs(stepped.baseline + .8) < 1e-6);
    CHECK(fabs(controlValue(&stepped, 1) + .72) < 1e-6);
    CHECK(controlValue(&stepped, 1.08) < -.72 && controlValue(&stepped, 1.08) > -.8);
    CHECK(fabs(controlValue(&stepped, 1.16) + .8) < 1e-6);
    controlStepBaseline(&stepped, 1, 2);
    CHECK(fabs(stepped.baseline + .7) < 1e-6);
    CHECK(fabs(controlValue(&stepped, 2.16) + .7) < 1e-6);

    FilterControl toggled = {.preset = -.65};
    controlTogglePreset(&toggled, 0);
    CHECK(toggled.baseline == -.65 && fabs(controlValue(&toggled, .18) + .65) < 1e-6);
    controlTogglePreset(&toggled, .2);
    CHECK(toggled.baseline == 0 && fabs(controlValue(&toggled, .38)) < 1e-6);
    controlTogglePreset(&toggled, .4);
    controlTogglePreset(&toggled, .45); // A quick repeat reverses the in-flight transition.
    CHECK(toggled.baseline == 0 && fabs(controlValue(&toggled, .63)) < 1e-6);

    FilterControl overlap = {.preset = -.8};
    controlSetBaseline(&overlap, .2, 0);
    controlSetTrigger(&overlap, PresetTriggerShortcut, true, 1);
    controlSetTrigger(&overlap, PresetTriggerMicrophone, true, 1.1);
    controlSetTrigger(&overlap, PresetTriggerShortcut, false, 1.2);
    CHECK(overlap.held && fabs(controlValue(&overlap, 1.3) + .8) < 1e-6);
    controlSetTrigger(&overlap, PresetTriggerMicrophone, false, 2);
    CHECK(!overlap.held && fabs(controlValue(&overlap, 2.5) - .2) < 1e-6);
    controlSetTrigger(&overlap, PresetTriggerMicrophone, true, 3);
    controlReset(&overlap, 3.3);
    controlSetTrigger(&overlap, PresetTriggerShortcut, true, 3.4);
    CHECK(!overlap.held); // Reset stays neutral until both sources have released.
    controlSetTrigger(&overlap, PresetTriggerMicrophone, false, 3.5);
    controlSetTrigger(&overlap, PresetTriggerShortcut, false, 3.6);
    controlSetTrigger(&overlap, PresetTriggerMicrophone, true, 4);
    CHECK(overlap.held && fabs(controlValue(&overlap, 4.3) + .8) < 1e-6);

    FilterControl playback = {.preset = -.6};
    controlSetBaseline(&playback, .25, 0);
    controlSetTrigger(&playback, PresetTriggerPlayback, true, 1);
    controlSetTrigger(&playback, PresetTriggerMicrophone, true, 1.1);
    controlSetTrigger(&playback, PresetTriggerPlayback, false, 1.2);
    CHECK(playback.held); // A browser stopping must not release an active mic preset.
    controlSetTrigger(&playback, PresetTriggerMicrophone, false, 2);
    CHECK(!playback.held && fabs(controlValue(&playback, 2.5) - .25) < 1e-6);
    controlSetTrigger(&playback, PresetTriggerPlayback, true, 3);
    controlReset(&playback, 3.3);
    controlSetTrigger(&playback, PresetTriggerShortcut, true, 3.4);
    controlSetTrigger(&playback, PresetTriggerShortcut, false, 3.5);
    CHECK(!playback.held && playback.suppressTriggers);
    controlSetTrigger(&playback, PresetTriggerPlayback, false, 4);
    controlSetTrigger(&playback, PresetTriggerPlayback, true, 5);
    CHECK(playback.held && fabs(controlValue(&playback, 5.3) + .6) < 1e-6);
    controlSetTrigger(&playback, PresetTriggerPlayback, false, 6);
    CHECK(!playback.held && playback.duration == .18);
    CHECK(fabs(controlValue(&playback, 6.2)) < 1e-6);

    @autoreleasepool {
        HoldShortcutMonitor *monitor = [HoldShortcutMonitor new];
        CHECK(!monitor.configured);
        CHECK(![monitor enableRequestingPermission:NO]);
        [monitor setKeyCode:-1 modifiers:kCGEventFlagMaskSecondaryFn];
        __block unsigned changes = 0;
        __block BOOL held = NO;
        monitor.changed = ^(BOOL down) { changes++; held = down; };
        CGEventRef event = CGEventCreate(NULL);
        CHECK(event != NULL);
        CGEventSetFlags(event, kCGEventFlagMaskShift);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(changes == 0);
        CGEventSetFlags(event, kCGEventFlagMaskSecondaryFn);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(changes == 1 && held);
        CGEventSetFlags(event, kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskShift);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(changes == 1 && held);
        CGEventSetFlags(event, 0);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(changes == 2 && !held);
        CGEventSetFlags(event, kCGEventFlagMaskSecondaryFn);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        [monitor disable];
        CHECK(changes == 4 && !held); // Disabling cannot leave the preset held.
        CFRelease(event);
        event = CGEventCreateKeyboardEvent(NULL, 40, true);
        CHECK(event != NULL);
        // A recorded key chord releases when either its key or modifier is released.
        [monitor setKeyCode:40 modifiers:kCGEventFlagMaskAlternate]; // Option-K
        CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 40);
        CGEventSetFlags(event, kCGEventFlagMaskAlternate);
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(held && changes == 5);
        CGEventSetIntegerValueField(event, kCGKeyboardEventAutorepeat, 1);
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(held && changes == 5);
        CGEventSetFlags(event, 0);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(!held && changes == 6);
        [monitor receiveType:kCGEventKeyUp event:event];
        CGEventSetFlags(event, kCGEventFlagMaskAlternate);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(!held); // A modifier alone cannot reactivate a released key.
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(!held); // An autorepeat cannot initiate a new hold.
        CGEventSetIntegerValueField(event, kCGKeyboardEventAutorepeat, 0);
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(held);
        monitor.recording = YES;
        CHECK(!held);
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(!held); // Recording cannot preview the filter.
        monitor.recording = NO;
        [monitor receiveType:kCGEventKeyUp event:event];
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(held);
        [monitor receiveType:kCGEventTapDisabledByTimeout event:event];
        CHECK(!held); // Tap interruptions cannot leave a held preset stuck.
        [monitor setKeyCode:-1 modifiers:kCGEventFlagMaskControl | kCGEventFlagMaskShift];
        CGEventSetFlags(event, kCGEventFlagMaskControl);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(!held);
        CGEventSetFlags(event, kCGEventFlagMaskControl | kCGEventFlagMaskShift);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(held);
        [monitor setKeyCode:-1 modifiers:kCGEventFlagMaskSecondaryFn];
        CHECK(!held); // Changing a shortcut releases the old hold.
        CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 123);
        CGEventSetFlags(event, kCGEventFlagMaskSecondaryFn);
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(!held); // Arrow keys carry the Fn flag but must not trigger a modifier-only shortcut.
        [monitor setKeyCode:40 modifiers:kCGEventFlagMaskSecondaryFn];
        CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 40);
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(!held); // Nor may a key event synthesize the physical Fn modifier in a chord.
        [monitor receiveType:kCGEventFlagsChanged event:event];
        CHECK(held);
        [monitor receiveType:kCGEventKeyUp event:event];
        CHECK(!held);
        [monitor setKeyCode:-1 modifiers:0];
        CHECK(!monitor.configured && !held);
        [monitor receiveType:kCGEventFlagsChanged event:event];
        [monitor receiveType:kCGEventKeyDown event:event];
        CHECK(!held); // None cannot trigger or request Input Monitoring.
        CHECK(![monitor enableRequestingPermission:NO]);
        CFRelease(event);
    }
    @autoreleasepool {
        GlobalFilterHotkeys *hotkeys = [GlobalFilterHotkeys new];
        __block NSMutableArray<NSNumber *> *actions = [NSMutableArray new];
        hotkeys.performed = ^(GlobalFilterHotkeyAction action) { [actions addObject:@(action)]; };
        NSEvent *(^media)(unsigned, unsigned, NSEventModifierFlags, BOOL) =
            ^NSEvent *(unsigned key, unsigned state, NSEventModifierFlags flags, BOOL repeat) {
                NSInteger data = (key << 16) | (state << 8) | (repeat ? 1 : 0);
                return [NSEvent otherEventWithType:NSEventTypeSystemDefined location:NSZeroPoint
                    modifierFlags:flags timestamp:0 windowNumber:0 context:nil
                    subtype:NX_SUBTYPE_AUX_CONTROL_BUTTONS data1:data data2:0];
            };
        CHECK(![hotkeys receiveMediaEvent:media(NX_KEYTYPE_SOUND_DOWN, NX_KEYDOWN, 0, NO)]);
        CHECK(![hotkeys receiveMediaEvent:media(NX_KEYTYPE_SOUND_DOWN, NX_KEYDOWN,
            NSEventModifierFlagOption | NSEventModifierFlagShift, NO)]);
        CHECK([hotkeys receiveMediaEvent:media(NX_KEYTYPE_MUTE, NX_KEYDOWN, NSEventModifierFlagOption, NO)]);
        CHECK(actions.lastObject.unsignedIntegerValue == GlobalFilterHotkeyToggle);
        CHECK([hotkeys receiveMediaEvent:media(NX_KEYTYPE_MUTE, NX_KEYDOWN, NSEventModifierFlagOption, YES)]);
        CHECK(actions.count == 1);
        CHECK([hotkeys receiveMediaEvent:media(NX_KEYTYPE_SOUND_DOWN, NX_KEYDOWN, NSEventModifierFlagOption, NO)]);
        CHECK(actions.lastObject.unsignedIntegerValue == GlobalFilterHotkeyDecrease);
        CHECK([hotkeys receiveMediaEvent:media(NX_KEYTYPE_SOUND_UP, NX_KEYDOWN, NSEventModifierFlagOption, NO)]);
        CHECK(actions.lastObject.unsignedIntegerValue == GlobalFilterHotkeyIncrease);
        CHECK([hotkeys receiveMediaEvent:media(NX_KEYTYPE_SOUND_UP, NX_KEYUP, NSEventModifierFlagOption, NO)]);
        CHECK(actions.count == 3);
    }
    puts("Hold, fixed-hotkey, reset, and listener cleanup checks passed.");
    return 0;
}

int discoMotionTests(void);
int cliTests(void);

int selfTest(void) {
    if (cliTests()) return 1;
    if (discoMotionTests()) return 1;
    if (controlTests()) return 1;
    const float positions[] = {0, -1, 1};
    const double frequencies[] = {440, 10000, 100};
    const double rates[] = {44100, 48000};
    for (unsigned rate = 0; rate < 2; rate++) {
    for (unsigned test = 0; test < 3; test++) {
        Filter f = {.sampleRate = rates[rate]};
        double energy = 0, reference = 0;
        for (unsigned i = 0; i < 96000; i++) {
            float x = .25 * sin(2 * M_PI * frequencies[test] * i / rates[rate]);
            float in[2] = {x, x}, out[2];
            filterFrame(&f, positions[test], in, out);
            if (!isfinite(out[0]) || out[0] != out[1]) return 1;
            if (test == 0 && out[0] != x) return 2;
            if (i > 48000) { energy += out[0] * out[0]; reference += x * x; }
        }
        double db = 10 * log10(energy / reference);
        printf("%.0f Hz — %s: %.1f dB\n", rates[rate], test == 0 ? "Bypass" : test == 1 ? "Low-pass at 10 kHz" : "High-pass at 100 Hz", db);
        if (test && db > -40) return 3;
    }
    }
    // Feed a reset through the actual DSP and require a finite output throughout,
    // followed by sample-exact bypass once the transition has settled.
    for (unsigned rate = 0; rate < 2; rate++) {
        FilterControl c = {0};
        Filter f = {.sampleRate = rates[rate]};
        controlSetBaseline(&c, -.8, 0);
        for (unsigned i = 0; i < 2 * rates[rate]; i++) {
            double now = i / rates[rate];
            if (i == (unsigned)rates[rate]) controlReset(&c, now);
            float x = .2 * sin(2 * M_PI * 1000 * now), in[2] = {x, x}, out[2];
            filterFrame(&f, controlValue(&c, now), in, out);
            CHECK(isfinite(out[0]) && fabsf(out[0]) < 1);
            if (now > 1.8) CHECK(out[0] == x);
        }
    }
    puts("Filter checks passed.");
    return 0;
}
