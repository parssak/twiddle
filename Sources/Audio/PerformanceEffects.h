#pragma once
#include "AudioDSP.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    double rate, smoothing, tapeRead, tapeSpeed, phaserPhase;
    float phaserAmount, tapeMix, allpass[2][6], phaserFeedback[2];
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
static inline void performanceFrame(PerformanceEffects *d, float phaser, bool tapeHeld, float audio[2]) {
    d->phaserAmount = performanceSmooth(d->phaserAmount, audioUnitAmount(phaser), d->smoothing);
    d->tapeMix = performanceSmooth(d->tapeMix, tapeHeld ? 1 : 0, d->smoothing);
    if (tapeHeld && !d->tapeHeld) { d->tapeRead = d->historyWrite; d->tapeSpeed = 1; }
    d->tapeHeld = tapeHeld;
    double hz = 180 * pow(18, .5 + .5 * sin(d->phaserPhase));
    double tangent = tan(M_PI * fmin(hz, d->rate * .2) / d->rate);
    double coefficient = (tangent - 1) / (tangent + 1);
    unsigned read = (unsigned)d->tapeRead;
    float fraction = d->tapeRead - read;
    for (unsigned ch = 0; ch < 2; ch++) {
        float x = isfinite(audio[ch]) ? audio[ch] : 0;
        d->history[d->historyWrite * 2 + ch] = x;
        float tape = d->history[read * 2 + ch] + fraction *
            (d->history[((read + 1) % d->historySize) * 2 + ch] - d->history[read * 2 + ch]);
        tape *= sqrt(fmax(0, d->tapeSpeed));
        x += d->tapeMix * (tape - x);
        float phased = x + .55f * d->phaserFeedback[ch];
        for (unsigned stage = 0; stage < 6; stage++) {
            float next = coefficient * phased + d->allpass[ch][stage];
            d->allpass[ch][stage] = phased - coefficient * next;
            phased = next;
        }
        d->phaserFeedback[ch] = audioSoftLimit(phased);
        x += d->phaserAmount * (.5f * (x + phased) - x);
        audio[ch] = d->tapeMix || d->phaserAmount ? audioSoftLimit(x) : x;
    }
    if (d->tapeMix) {
        d->tapeRead += d->tapeSpeed;
        if (d->tapeRead >= d->historySize) d->tapeRead -= d->historySize;
        d->tapeSpeed = fmax(0, d->tapeSpeed - 1 / (.9 * d->rate));
    }
    d->phaserPhase += 2 * M_PI * (.1 + 1.5 * d->phaserAmount) / d->rate;
    if (d->phaserPhase >= 2 * M_PI) d->phaserPhase -= 2 * M_PI;
    d->historyWrite = (d->historyWrite + 1) % d->historySize;
}
