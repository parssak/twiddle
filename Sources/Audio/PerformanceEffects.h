#pragma once
#include "AudioDSP.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    double rate, smoothing, tapeRead, tapeSpeed;
    float tapeMix;
    float *history;
    unsigned historySize, historyWrite;
    bool tapeHeld;
} PerformanceEffects;
static inline void performanceDestroy(PerformanceEffects *d) {
    free(d->history);
    memset(d, 0, sizeof(*d));
}
static inline bool performanceInit(PerformanceEffects *d, double rate) {
    performanceDestroy(d);
    if (!isfinite(rate) || rate < 8000 || rate > 192000) return false;
    d->rate = rate;
    d->smoothing = 1 - exp(-1 / (.015 * rate));
    // The 0.9-second slowdown falls at most 0.45 seconds behind live audio.
    d->historySize = (unsigned)ceil(rate);
    d->history = calloc(d->historySize * 2, sizeof(float));
    if (!d->history) { performanceDestroy(d); return false; }
    return true;
}
static inline float performanceSmooth(float current, float target, double smoothing) {
    current += (target - current) * smoothing;
    return fabsf(current - target) < 1e-4f ? target : current;
}
static inline void performanceFrame(PerformanceEffects *d, bool tapeHeld, float audio[2]) {
    d->tapeMix = performanceSmooth(d->tapeMix, tapeHeld ? 1 : 0, d->smoothing);
    if (tapeHeld && !d->tapeHeld) { d->tapeRead = d->historyWrite; d->tapeSpeed = 1; }
    d->tapeHeld = tapeHeld;
    unsigned read = (unsigned)d->tapeRead;
    float fraction = d->tapeRead - read;
    for (unsigned ch = 0; ch < 2; ch++) {
        float x = isfinite(audio[ch]) ? audio[ch] : 0;
        d->history[d->historyWrite * 2 + ch] = x;
        if (d->tapeMix) {
            float tape = d->history[read * 2 + ch] + fraction *
                (d->history[((read + 1) % d->historySize) * 2 + ch] - d->history[read * 2 + ch]);
            tape *= sqrt(fmax(0, d->tapeSpeed));
            x += d->tapeMix * (tape - x);
        }
        audio[ch] = d->tapeMix ? audioSoftLimit(x) : x;
    }
    if (d->tapeMix) {
        d->tapeRead += d->tapeSpeed;
        if (d->tapeRead >= d->historySize) d->tapeRead -= d->historySize;
        d->tapeSpeed = fmax(0, d->tapeSpeed - 1 / (.9 * d->rate));
    }
    d->historyWrite = (d->historyWrite + 1) % d->historySize;
}
