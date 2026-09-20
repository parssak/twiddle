#include "NativeEffects.h"
#include "AudioDSP.h"
#include <math.h>
#include <string.h>

static OSStatus effectInput(void *context, AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    NativeEffect *r = context;
    if (frames > EffectBlockSize || data->mNumberBuffers != 2) return kAudio_ParamError;
    for (unsigned ch = 0; ch < 2; ch++) {
        data->mBuffers[ch].mData = r->dry[ch];
        data->mBuffers[ch].mDataByteSize = frames * sizeof(float);
        data->mBuffers[ch].mNumberChannels = 1;
    }
    return noErr;
}
void nativeEffectDestroy(NativeEffect *r) {
    if (r->unit) { AudioUnitUninitialize(r->unit); AudioComponentInstanceDispose(r->unit); }
    memset(r, 0, sizeof(*r));
}
OSStatus nativeEffectInit(NativeEffect *r, double rate, NativeEffectKind kind) {
    nativeEffectDestroy(r);
    if (kind < 0 || kind >= NativeEffectCount) return kAudio_ParamError;
    r->cutoffStart = kind == NativeEffectLowPass ? 18000 : 20;
    r->cutoffEnd = kind == NativeEffectLowPass ? 120 : 6000;
    r->kind = kind; r->lastPitch = r->lastControl = NAN;
    const OSType subtypes[] = {kAudioUnitSubType_MatrixReverb, kAudioUnitSubType_Pitch, kAudioUnitSubType_LowPassFilter, kAudioUnitSubType_HighPassFilter};
    AudioComponentDescription desc = {kAudioUnitType_Effect, subtypes[kind], kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    if (!component) return kAudio_ParamError;
    OSStatus status = AudioComponentInstanceNew(component, &r->unit);
    if (status) return status;
    AudioStreamBasicDescription format = {.mSampleRate = rate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = sizeof(float), .mFramesPerPacket = 1, .mBytesPerFrame = sizeof(float),
        .mChannelsPerFrame = 2, .mBitsPerChannel = 32};
    UInt32 maximum = EffectBlockSize;
    AURenderCallbackStruct callback = {effectInput, r};
#define SETUP(call) do { status = (call); if (status) { nativeEffectDestroy(r); return status; } } while (0)
    SETUP(AudioUnitSetProperty(r->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)));
    SETUP(AudioUnitSetProperty(r->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof(format)));
    SETUP(AudioUnitSetProperty(r->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximum, sizeof(maximum)));
    SETUP(AudioUnitSetProperty(r->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback)));
    if (kind == NativeEffectPitch) {
        SETUP(AudioUnitSetParameter(r->unit, kTimePitchParam_EffectBlend, kAudioUnitScope_Global, 0, 100, 0));
    }
#define PARAM(id, value) SETUP(AudioUnitSetParameter(r->unit, id, kAudioUnitScope_Global, 0, value, 0))
    switch (kind) {
        case NativeEffectLowPass: PARAM(kLowPassParam_Resonance, 5); break;
        case NativeEffectHighPass: PARAM(kHipassParam_Resonance, 5); break;
        case NativeEffectReverb: PARAM(kReverbParam_DryWetMix, 100); break;
        default: break;
    }
#undef PARAM
    SETUP(AudioUnitInitialize(r->unit));
    Float64 latency = 0, tail = 0;
    UInt32 size = sizeof(latency);
    SETUP(AudioUnitGetProperty(r->unit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &latency, &size));
    size = sizeof(tail);
    SETUP(AudioUnitGetProperty(r->unit, kAudioUnitProperty_TailTime, kAudioUnitScope_Global, 0, &tail, &size));
    r->latencyFrames = (unsigned)ceil(fmax(0, latency) * rate);
    r->tailFrames = (unsigned)ceil((fmax(0, latency) + fmax(0, tail)) * rate);
#undef SETUP
    r->smoothing = 1 - exp(-1 / (.012 * rate));
    return noErr;
}
OSStatus nativeEffectProcess(NativeEffect *r, AudioBufferList *audio, unsigned frames, float target) {
    if (!r->unit) return kAudio_ParamError;
    if (r->kind == NativeEffectPitch) {
        float cents = isfinite(target) ? fminf(12, fmaxf(-12, target)) * 100 : 0;
        if (cents != r->lastPitch) {
            OSStatus status = AudioUnitSetParameter(r->unit, kTimePitchParam_Pitch, kAudioUnitScope_Global, 0, cents, 0);
            if (status) return status;
            r->lastPitch = cents;
        }
        target = cents != 0 ? 1 : 0;
    } else if (r->kind == NativeEffectReverb) target = sqrtf(audioUnitAmount(target));
    else {
        float control = audioUnitAmount(target);
        if (fabsf(control) < 1e-6f) control = 0;
        if (control != r->lastControl) {
#define CONTROL(id, value) do { OSStatus status = AudioUnitSetParameter(r->unit, id, kAudioUnitScope_Global, 0, value, 0); if (status) return status; } while (0)
            switch (r->kind) {
                case NativeEffectLowPass: CONTROL(kLowPassParam_CutoffFrequency, r->cutoffStart * powf(r->cutoffEnd / r->cutoffStart, control)); break;
                case NativeEffectHighPass: CONTROL(kHipassParam_CutoffFrequency, r->cutoffStart * powf(r->cutoffEnd / r->cutoffStart, control)); break;
                default: break;
            }
#undef CONTROL
            r->lastControl = control;
        }
        target = fminf(1, control * 20);
    }
    if (target > 0 && !r->engaged && !r->amount) r->warmupFrames = r->latencyFrames;
    r->engaged = target > 0;
    // Finish the fade and drain with silence before sleeping. Matrix Reverb's
    // reset alone leaves delay-line audio behind, so freezing it replays old tails.
    if (!target && !r->amount && !r->drainFrames) {
        if (r->rendering) {
            OSStatus status = AudioUnitReset(r->unit, kAudioUnitScope_Global, 0);
            if (status) return status;
            r->rendering = false;
            r->time = 0;
        }
        return noErr;
    }
    r->rendering = true;
    for (unsigned base = 0; base < frames; base += EffectBlockSize) {
        unsigned count = MIN(EffectBlockSize, frames - base);
        if (target > 0 || r->amount > 0) r->drainFrames = r->tailFrames;
        else r->drainFrames -= MIN(count, r->drainFrames);
        for (unsigned ch = 0; ch < 2; ch++) {
            AudioBuffer *buffer = &audio->mBuffers[audio->mNumberBuffers == 1 ? 0 : ch];
            for (unsigned i = 0; i < count; i++) {
                float sample = ((float *)buffer->mData)[(base + i) * buffer->mNumberChannels + (buffer->mNumberChannels == 2 ? ch : 0)];
                sample = (target > 0 || r->amount > 1e-6) && isfinite(sample) ? sample : 0;
                r->dry[ch][i] = sample;
            }
        }
        struct { UInt32 count; AudioBuffer buffers[2]; } wet = {2, {{1, count * sizeof(float), r->wet[0]}, {1, count * sizeof(float), r->wet[1]}}};
        AudioTimeStamp time = {.mSampleTime = r->time, .mFlags = kAudioTimeStampSampleTimeValid};
        AudioUnitRenderActionFlags flags = 0;
        OSStatus status = AudioUnitRender(r->unit, &flags, &time, 0, count, (AudioBufferList *)&wet);
        r->time += count;
        if (status) return status;
        for (unsigned i = 0; i < count; i++) {
            // Keep dry audio audible while the pitch unit fills its delay line.
            float mixTarget = r->warmupFrames ? 0 : target;
            if (r->warmupFrames) r->warmupFrames--;
            r->amount += (mixTarget - r->amount) * r->smoothing;
            if (!mixTarget && r->amount < 1e-6) r->amount = 0;
            for (unsigned ch = 0; ch < 2; ch++) {
                AudioBuffer *buffer = &audio->mBuffers[audio->mNumberBuffers == 1 ? 0 : ch];
                float *sample = &((float *)buffer->mData)[(base + i) * buffer->mNumberChannels + (buffer->mNumberChannels == 2 ? ch : 0)];
                // Smooth bypass transitions; pitch uses the wet signal at nonzero shifts.
                if (r->kind == NativeEffectReverb)
                    *sample = *sample * (1 - .35f * r->amount) + .7f * r->amount * r->wet[ch][i];
                else
                    *sample += r->amount * (r->wet[ch][i] - *sample);
                if (r->amount > 0) *sample = audioSoftLimit(*sample);
            }
        }
    }
    return noErr;
}
