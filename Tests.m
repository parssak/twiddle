#include "Filter.h"
#include "FilterControl.h"
#include <stdio.h>
#import "FnKeyMonitor.h"
#import <CoreGraphics/CoreGraphics.h>

// Exercise the same modifier-event decoder without listening to or injecting
// events into the user's desktop.
@interface FnKeyMonitor (TestEvents)
- (void)receiveType:(CGEventType)type event:(CGEventRef)event;
@end

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "Failed: %s (line %d)\n", #condition, __LINE__); return 1; } } while (0)

static int controlTests(void) {
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

    @autoreleasepool {
        FnKeyMonitor *monitor = [FnKeyMonitor new];
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
    }
    puts("Hold/release, repeated modifiers, reset interruption, and listener cleanup checks passed.");
    return 0;
}

int selfTest(void) {
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
