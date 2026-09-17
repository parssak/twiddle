#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>

enum { EffectBlockSize = 512 };
typedef enum { NativeEffectReverb, NativeEffectPitch, NativeEffectLowPass, NativeEffectHighPass, NativeEffectCount } NativeEffectKind;
typedef struct {
    AudioUnit unit;
    NativeEffectKind kind;
    float lastPitch, lastControl, cutoffStart, cutoffEnd;
    double time, smoothing;
    float amount;
    float dry[2][EffectBlockSize], wet[2][EffectBlockSize];
} NativeEffect;
OSStatus nativeEffectInit(NativeEffect *r, double sampleRate, NativeEffectKind kind);
void nativeEffectDestroy(NativeEffect *r);
OSStatus nativeEffectProcess(NativeEffect *r, AudioBufferList *audio, unsigned frames, float amount);
