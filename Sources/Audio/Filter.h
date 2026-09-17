#pragma once
#include "NativeEffects.h"
#include <math.h>
#include <string.h>

// The main knob keeps its original cutoff mapping and 25 ms movement smoothing.
typedef struct {
    NativeEffect low, high;
    double position, sampleRate;
} Filter;

static void filterDestroy(Filter *f) {
    nativeEffectDestroy(&f->low); nativeEffectDestroy(&f->high);
    memset(f, 0, sizeof(*f));
}
static OSStatus filterInit(Filter *f, double rate) {
    filterDestroy(f);
    f->sampleRate = rate;
    OSStatus status = nativeEffectInit(&f->low, rate, NativeEffectLowPass);
    if (!status) status = nativeEffectInit(&f->high, rate, NativeEffectHighPass);
    if (status) { filterDestroy(f); return status; }
    f->low.cutoffStart = 20000; f->low.cutoffEnd = 115;
    f->high.cutoffStart = 20; f->high.cutoffEnd = 10000;
    return noErr;
}
static OSStatus filterProcess(Filter *f, float target, AudioBufferList *audio, unsigned frames) {
    target = isfinite(target) ? fminf(1, fmaxf(-1, target)) : 0;
    // Small chunks keep cutoff movement smooth regardless of the device buffer size.
    for (unsigned base = 0; base < frames; base += 64) {
        unsigned count = MIN(64, frames - base);
        f->position += (target - f->position) * (1 - exp(-(double)count / (.025 * f->sampleRate)));
        if (fabs(target - f->position) < 1e-7) f->position = target;
        struct { UInt32 count; AudioBuffer buffers[2]; } slice = {audio->mNumberBuffers, {0}};
        for (unsigned b = 0; b < audio->mNumberBuffers; b++) {
            unsigned channels = audio->mBuffers[b].mNumberChannels;
            slice.buffers[b] = (AudioBuffer){channels, count * channels * sizeof(float),
                (float *)audio->mBuffers[b].mData + base * channels};
        }
        OSStatus status = nativeEffectProcess(&f->low, (AudioBufferList *)&slice, count, fmax(0, -f->position));
        if (!status) status = nativeEffectProcess(&f->high, (AudioBufferList *)&slice, count, fmax(0, f->position));
        if (status) return status;
    }
    return noErr;
}
