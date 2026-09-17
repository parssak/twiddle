#import "AudioEngine.h"
#import "CoreAudioUtilities.h"
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <stdatomic.h>
#include <unistd.h>
#include "Filter.h"
#include "PerformanceEffects.h"
#include "NativeEffects.h"

typedef struct {
    Filter filter;
    PerformanceEffects performance;
    NativeEffect reverbEffect, pitchEffect;
    _Atomic(bool) tapeStop;
    _Atomic(float) reverb, pitch, phaser;
    _Atomic(float) target, peak;
    _Atomic(unsigned) callbacks;
    _Atomic(bool) badLayout;
} AudioState;

// The POC accepts one stereo float stream, or two mono float streams.
static bool stereoBuffers(const AudioBufferList *list) {
    if (!list) return false;
    return (list->mNumberBuffers == 1 && list->mBuffers[0].mNumberChannels == 2) ||
           (list->mNumberBuffers == 2 && list->mBuffers[0].mNumberChannels == 1 && list->mBuffers[1].mNumberChannels == 1);
}

static OSStatus audioCallback(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    AudioState *state = context;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    if (!stereoBuffers(input) || !stereoBuffers(output)) {
        atomic_store_explicit(&state->badLayout, true, memory_order_relaxed);
        return noErr;
    }
    UInt32 frames = UINT32_MAX;
    for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
        if (!input->mBuffers[b].mData) return noErr;
        frames = MIN(frames, input->mBuffers[b].mDataByteSize / (sizeof(float) * input->mBuffers[b].mNumberChannels));
    }
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        if (!output->mBuffers[b].mData) return noErr;
        frames = MIN(frames, output->mBuffers[b].mDataByteSize / (sizeof(float) * output->mBuffers[b].mNumberChannels));
    }
    float target = atomic_load_explicit(&state->target, memory_order_relaxed), peak = 0;
    float reverb = atomic_load(&state->reverb);
    float phaser = atomic_load(&state->phaser);
    bool tapeStop = atomic_load(&state->tapeStop);
    for (UInt32 i = 0; i < frames; i++) {
        float in[2];
        for (unsigned ch = 0; ch < 2; ch++) {
            const AudioBuffer *b = &input->mBuffers[input->mNumberBuffers == 1 ? 0 : ch];
            in[ch] = ((const float *)b->mData)[i * b->mNumberChannels + (b->mNumberChannels == 2 ? ch : 0)];
            peak = fmaxf(peak, fabsf(in[ch]));
        }
        performanceFrame(&state->performance, phaser, tapeStop, in);
        for (unsigned ch = 0; ch < 2; ch++) {
            AudioBuffer *b = &output->mBuffers[output->mNumberBuffers == 1 ? 0 : ch];
            ((float *)b->mData)[i * b->mNumberChannels + (b->mNumberChannels == 2 ? ch : 0)] = in[ch];
        }
    }
    if (filterProcess(&state->filter, target, output, frames))
        atomic_store_explicit(&state->badLayout, true, memory_order_relaxed);
    if (nativeEffectProcess(&state->pitchEffect, output, frames, atomic_load(&state->pitch)))
        atomic_store_explicit(&state->badLayout, true, memory_order_relaxed);
    if (nativeEffectProcess(&state->reverbEffect, output, frames, reverb))
        atomic_store_explicit(&state->badLayout, true, memory_order_relaxed);
    atomic_store_explicit(&state->peak, peak, memory_order_relaxed);
    atomic_fetch_add_explicit(&state->callbacks, 1, memory_order_relaxed);
    return noErr;
}

@interface AudioEngine () {
    AudioObjectID _tap, _aggregate, _output;
    AudioDeviceIOProcID _io;
    AudioState _audio;
    BOOL _running;
}
@property (readwrite, copy) NSString *outputName, *errorMessage;
@end

@implementation AudioEngine
- (instancetype)init {
    if ((self = [super init])) {
        atomic_init(&_audio.target, 0);
        atomic_init(&_audio.tapeStop, false);
        atomic_init(&_audio.reverb, 0); atomic_init(&_audio.pitch, 0); atomic_init(&_audio.phaser, 0);
        atomic_init(&_audio.peak, 0);
        atomic_init(&_audio.callbacks, 0);
        atomic_init(&_audio.badLayout, false);
    }
    return self;
}
- (BOOL)tapeStop { return atomic_load(&_audio.tapeStop); }
- (void)setTapeStop:(BOOL)value { atomic_store(&_audio.tapeStop, value); }
- (float)phaser { return atomic_load(&_audio.phaser); }
- (void)setPhaser:(float)value { atomic_store(&_audio.phaser, audioUnitAmount(value)); }
- (float)reverb { return atomic_load(&_audio.reverb); }
- (void)setReverb:(float)v { atomic_store(&_audio.reverb, audioUnitAmount(v)); }
- (float)pitch { return atomic_load(&_audio.pitch); }
- (void)setPitch:(float)v { atomic_store(&_audio.pitch, isfinite(v) ? fminf(12, fmaxf(-12, v)) : 0); }
- (BOOL)running { return _running; }
- (float)target { return atomic_load(&_audio.target); }
- (void)setTarget:(float)value { atomic_store(&_audio.target, isfinite(value) ? fminf(1, fmaxf(-1, value)) : 0); }
- (float)peak { return atomic_load(&_audio.peak); }
- (unsigned)callbacks { return atomic_load(&_audio.callbacks); }
- (BOOL)check:(OSStatus)status operation:(NSString *)operation {
    if (status == noErr) return YES;
    [self stop];
    self.errorMessage = [NSString stringWithFormat:@"%@ failed (%d).", operation, (int)status];
    NSLog(@"%@ failed: %d", operation, (int)status);
    return NO;
}
- (BOOL)validateStreams:(AudioObjectPropertyScope)scope {
    AudioObjectPropertyAddress a = address(kAudioDevicePropertyStreams, scope);
    UInt32 size = 0;
    if (![self check:AudioObjectGetPropertyDataSize(_aggregate, &a, 0, NULL, &size) operation:@"Read audio streams"]) return NO;
    AudioStreamID *streams = calloc(1, size);
    OSStatus status = AudioObjectGetPropertyData(_aggregate, &a, 0, NULL, &size, streams);
    BOOL valid = status == noErr;
    UInt32 channels = 0;
    for (unsigned i = 0; valid && i < size / sizeof(AudioStreamID); i++) {
        AudioStreamBasicDescription format = {0};
        valid = readProperty(streams[i], kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal, sizeof(format), &format) == noErr;
        NSLog(@"%@ stream %u: %u channels, %.0f Hz, %u bits, flags 0x%x; tap %.0f Hz",
            scope == kAudioObjectPropertyScopeInput ? @"Input" : @"Output", streams[i],
            format.mChannelsPerFrame, format.mSampleRate, format.mBitsPerChannel,
            (unsigned)format.mFormatFlags, _audio.filter.sampleRate);
        valid = valid && format.mFormatID == kAudioFormatLinearPCM &&
            (format.mFormatFlags & kAudioFormatFlagIsFloat) && !(format.mFormatFlags & kAudioFormatFlagIsBigEndian) &&
            format.mBitsPerChannel == 32 && format.mSampleRate == _audio.filter.sampleRate &&
            format.mFramesPerPacket == 1 && format.mBytesPerFrame == sizeof(float) *
                ((format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : format.mChannelsPerFrame);
        channels += format.mChannelsPerFrame;
    }
    free(streams);
    if (!valid || channels != 2) {
        [self stop];
        self.errorMessage = [NSString stringWithFormat:@"Unsupported %@ format (%u channels). This POC needs stereo 32-bit float audio at the output's sample rate.",
            scope == kAudioObjectPropertyScopeInput ? @"capture" : @"playback", channels];
        return NO;
    }
    return YES;
}
- (BOOL)startWithBundles:(NSSet<NSString *> *)bundles probe:(BOOL)probe {
    [self stop];
    self.errorMessage = nil;
    if (bundles) {
        NSMutableSet *safeBundles = [bundles mutableCopy];
        [safeBundles removeObject:NSBundle.mainBundle.bundleIdentifier ?: @"com.parssa.lowpasser.poc"];
        bundles = safeBundles;
    }
    if (![self check:readProperty(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, sizeof(_output), &_output) operation:@"Find output"]) return NO;
    NSString *outputUID = stringProperty(_output, kAudioDevicePropertyDeviceUID);
    NSString *outputName = stringProperty(_output, kAudioObjectPropertyName);
    NSLog(@"Output device: %@", outputName);
    if (!outputUID) { self.errorMessage = @"No output device found."; return NO; }
    pid_t pid = getpid();
    AudioObjectID ownProcess = kAudioObjectUnknown;
    AudioObjectPropertyAddress a = address(kAudioHardwarePropertyTranslatePIDToProcessObject, kAudioObjectPropertyScopeGlobal);
    UInt32 size = sizeof(ownProcess);
    if (![self check:AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof(pid), &pid, &size, &ownProcess) operation:@"Exclude our own audio"]) return NO;
    if (!ownProcess) { self.errorMessage = @"Could not exclude this app from capture."; return NO; }
    // A global mixdown tap runs at 48 kHz even when the output runs at 44.1 kHz.
    // Capture this output's stream so the tap and playback share the same format.
    CATapDescription *description = [[CATapDescription alloc] initExcludingProcesses:@[@(ownProcess)]
        andDeviceUID:outputUID withStream:0];
    BOOL selectedOnly = bundles != nil;
    if (selectedOnly) {
        if (!bundles.count) {
            self.errorMessage = @"Choose at least one app, or enable Filter all apps.";
            NSLog(@"No apps selected; audio capture was not started.");
            return NO;
        }
        description.exclusive = NO;
        description.processes = @[];
        description.bundleIDs = bundles.allObjects;
        description.processRestoreEnabled = YES;
        NSLog(@"Filtering app identities: %@", [[bundles.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]);
    }
    description.name = @"Twiddle system audio";
    description.private = YES;
    description.muteBehavior = CATapMutedWhenTapped;
    if (![self check:AudioHardwareCreateProcessTap(description, &_tap) operation:@"Create audio tap"]) return NO;
    AudioStreamBasicDescription format = {0};
    if (![self check:readProperty(_tap, kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal, sizeof(format), &format) operation:@"Read tap format"]) return NO;
    atomic_store(&_audio.callbacks, 0);
    atomic_store(&_audio.badLayout, false);
    atomic_store(&_audio.peak, 0);
    NSString *tapUID = stringProperty(_tap, kAudioTapPropertyUID);
    if (!tapUID || !isfinite(format.mSampleRate) || format.mSampleRate <= 0) { [self stop]; self.errorMessage = @"Invalid tap format."; return NO; }
    if (![self check:filterInit(&_audio.filter, format.mSampleRate) operation:@"Prepare main Apple filters"]) return NO;
    if (!performanceInit(&_audio.performance, format.mSampleRate)) {
        [self stop]; self.errorMessage = @"Could not allocate the tape stop buffer."; return NO;
    }
    if (![self check:nativeEffectInit(&_audio.reverbEffect, format.mSampleRate, NativeEffectReverb) operation:@"Prepare reverb"]) return NO;
    if (![self check:nativeEffectInit(&_audio.pitchEffect, format.mSampleRate, NativeEffectPitch) operation:@"Prepare pitch"]) return NO;
    NSDictionary *config = @{
        @kAudioAggregateDeviceNameKey: @"Twiddle private audio",
        @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceIsPrivateKey: @YES,
        @kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        @kAudioAggregateDeviceSubDeviceListKey: @[@{
            @kAudioSubDeviceUIDKey: outputUID
        }],
        @kAudioAggregateDeviceTapListKey: @[@{
            @kAudioSubTapUIDKey: tapUID,
            @kAudioSubTapDriftCompensationKey: @YES
        }]
    };
    if (![self check:AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)config, &_aggregate) operation:@"Create audio route"]) return NO;
    if (![self validateStreams:kAudioObjectPropertyScopeInput] || ![self validateStreams:kAudioObjectPropertyScopeOutput]) return NO;
    if (probe) { [self stop]; return YES; }
    if (![self check:AudioDeviceCreateIOProcID(_aggregate, audioCallback, &_audio, &_io) operation:@"Create audio callback"]) return NO;
    if (![self check:AudioDeviceStart(_aggregate, _io) operation:@"Start audio (permission required)"]) return NO;
    _running = YES;
    self.outputName = outputName ?: @"current output";
    return YES;
}
- (void)stop {
    if (_io) {
        AudioDeviceStop(_aggregate, _io);
        AudioDeviceDestroyIOProcID(_aggregate, _io);
        _io = NULL;
    }
    if (_aggregate) { AudioHardwareDestroyAggregateDevice(_aggregate); _aggregate = 0; }
    if (_tap) { AudioHardwareDestroyProcessTap(_tap); _tap = 0; }
    performanceDestroy(&_audio.performance);
    atomic_store(&_audio.tapeStop, false);
    filterDestroy(&_audio.filter);
    nativeEffectDestroy(&_audio.reverbEffect); nativeEffectDestroy(&_audio.pitchEffect);
    _running = NO;
}
- (BOOL)checkRoute {
    if (!_running) return NO;
    AudioObjectID current = 0;
    UInt32 alive = 0;
    OSStatus status = readProperty(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, sizeof(current), &current);
    readProperty(_output, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal, sizeof(alive), &alive);
    if (status || current != _output || !alive || atomic_load(&_audio.badLayout)) {
        [self stop];
        self.errorMessage = @"Audio route changed or is unsupported. Normal playback restored; press Start to retry.";
        return NO;
    }
    return YES;
}
- (void)dealloc { [self stop]; }
@end
