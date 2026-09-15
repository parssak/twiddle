#pragma once
#include <stdbool.h>
#include <math.h>

// UI-independent control state. A held preset never overwrites the baseline.
typedef struct {
    double baseline, preset, from, to, started, duration;
    bool held, suppressTriggers;
    unsigned triggers;
} FilterControl;

static inline double controlValue(const FilterControl *c, double now) {
    double t = c->duration > 0 ? fmin(1, fmax(0, (now - c->started) / c->duration)) : 1;
    double eased = t * t * (3 - 2 * t);
    return c->from + (c->to - c->from) * eased;
}

static inline void controlTransition(FilterControl *c, double value, double duration, double now) {
    c->from = controlValue(c, now);
    c->to = fmin(1, fmax(-1, value));
    c->started = now;
    c->duration = duration;
}

static inline void controlSetBaseline(FilterControl *c, double value, double now) {
    c->baseline = fmin(1, fmax(-1, value));
    if (!c->held) controlTransition(c, c->baseline, 0, now);
}

static inline void controlStepBaseline(FilterControl *c, int direction, double now) {
    const double step = 1.0 / 10.0;
    double position = c->baseline / step;
    double target = direction < 0 ? floor(position - 1e-9) * step : ceil(position + 1e-9) * step;
    c->baseline = fmin(1, fmax(-1, target));
    if (!c->held) controlTransition(c, c->baseline, .16, now);
}

static inline void controlSetHeld(FilterControl *c, bool held, double now) {
    if (held == c->held) return;
    c->held = held;
    controlTransition(c, held ? c->preset : c->baseline, held ? .18 : .4, now);
}

enum { PresetTriggerShortcut = 1, PresetTriggerMicrophone = 2, PresetTriggerPlayback = 4, PresetTriggerDisco = 8 };

static inline void controlSetTrigger(FilterControl *c, unsigned source, bool active, double now) {
    unsigned triggers = active ? c->triggers | source : c->triggers & ~source;
    if (triggers == c->triggers) return;
    c->triggers = triggers;
    if (!triggers) c->suppressTriggers = false;
    bool wasHeld = c->held;
    controlSetHeld(c, triggers && !c->suppressTriggers, now);
    if (wasHeld && !c->held && source == PresetTriggerPlayback) c->duration = .18;
}

static inline void controlSetPreset(FilterControl *c, double value, double now) {
    c->preset = fmin(1, fmax(-1, value));
    if (c->held) controlTransition(c, c->preset, .18, now);
}

static inline void controlReset(FilterControl *c, double now) {
    c->held = false;
    c->suppressTriggers = c->triggers != 0;
    c->baseline = 0;
    controlTransition(c, 0, .18, now);
}

static inline void controlTogglePreset(FilterControl *c, double now) {
    bool active = c->held || fabs(c->baseline) > 1e-6;
    c->held = false;
    c->suppressTriggers = c->triggers != 0;
    c->baseline = active ? 0 : c->preset;
    controlTransition(c, c->baseline, .18, now);
}
