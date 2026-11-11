#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <stdbool.h>

// macOS voice processing (ChatGPT voice mode, FaceTime, most call apps) ducks
// other apps by about 30 dB. Twiddle mutes its target apps at the source and
// replays them from its own process, which the system does not duck, so the
// replay applies the same reduction while a call is active.
static const float voiceDuckGain = 0.0316228f; // -30 dB
static const double voiceDuckAttackSeconds = .05, voiceDuckReleaseSeconds = .4;

// Double precision lets the slow release reach unity instead of stalling below it.
typedef struct { double gain; } VoiceDuck;

static inline void voiceDuckReset(VoiceDuck *d) { d->gain = 1; }

// One-pole gain ramp applied to every channel; returns without touching audio at full level.
static inline void voiceDuckProcess(VoiceDuck *d, bool ducked, double sampleRate, AudioBufferList *audio, unsigned frames) {
    double target = ducked ? voiceDuckGain : 1;
    if (d->gain == target && target == 1) return;
    if (!(sampleRate > 0)) sampleRate = 48000;
    double coefficient = 1 - exp(-1 / ((ducked ? voiceDuckAttackSeconds : voiceDuckReleaseSeconds) * sampleRate));
    double gain = d->gain;
    for (unsigned i = 0; i < frames; i++) {
        gain += (target - gain) * coefficient;
        if (fabs(target - gain) < 1e-4) gain = target;
        for (UInt32 b = 0; b < audio->mNumberBuffers; b++) {
            UInt32 channels = audio->mBuffers[b].mNumberChannels;
            float *samples = (float *)audio->mBuffers[b].mData + i * channels;
            for (UInt32 c = 0; c < channels; c++) samples[c] *= (float)gain;
        }
    }
    d->gain = gain;
}
