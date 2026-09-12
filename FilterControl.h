#pragma once
#include <stdbool.h>
#include <math.h>

// UI-independent control state. A held preset never overwrites the baseline.
typedef struct {
    double baseline, preset, from, to, started, duration;
    bool held;
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

static inline void controlSetHeld(FilterControl *c, bool held, double now) {
    if (held == c->held) return;
    c->held = held;
    controlTransition(c, held ? c->preset : c->baseline, held ? .18 : .4, now);
}

static inline void controlSetPreset(FilterControl *c, double value, double now) {
    c->preset = fmin(1, fmax(-1, value));
    if (c->held) controlTransition(c, c->preset, .18, now);
}

static inline void controlReset(FilterControl *c, double now) {
    c->held = false;
    c->baseline = 0;
    controlTransition(c, 0, .18, now);
}
