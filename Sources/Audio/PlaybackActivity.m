#import "PlaybackActivity.h"
#import "CoreAudioUtilities.h"
#import "AudioActivity.h"
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <stdatomic.h>
#include <mach/mach_time.h>

typedef struct { _Atomic(uint64_t) lastSound; } PlaybackState;
static OSStatus measurePlayback(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    // This tap never replays audio. The original apps remain unmuted.
    if (output) for (UInt32 b = 0; b < output->mNumberBuffers; b++)
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    if (input) for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &input->mBuffers[b];
        if (buffer->mData && audioSamplesAudible(buffer->mData, buffer->mDataByteSize / sizeof(float))) {
            atomic_store_explicit(&((PlaybackState *)context)->lastSound, mach_absolute_time(), memory_order_relaxed);
            break;
        }
    }
    return noErr;
}

@implementation PlaybackActivity {
    AudioObjectID _tap, _aggregate;
    AudioDeviceIOProcID _io;
    NSArray<NSNumber *> *_processes;
    PlaybackState _state;
    double _secondsPerTick, _retryAfter;
    NSString *_errorMessage;
}
- (instancetype)init {
    if ((self = [super init])) {
        atomic_init(&_state.lastSound, 0);
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        _secondsPerTick = (double)timebase.numer / timebase.denom / 1e9;
    }
    return self;
}
- (NSString *)errorMessage { return _errorMessage; }
- (BOOL)isMonitoring { return _io != NULL; }
- (BOOL)audible {
    uint64_t last = atomic_load_explicit(&_state.lastSound, memory_order_relaxed);
    return last && audioRecentlyAudible((mach_absolute_time() - last) * _secondsPerTick);
}
- (BOOL)check:(OSStatus)status operation:(NSString *)operation {
    if (status == noErr) return YES;
    [self stop];
    _errorMessage = [NSString stringWithFormat:@"%@ failed (%d)", operation, (int)status];
    NSLog(@"Playback detection: %@", _errorMessage);
    _retryAfter = NSProcessInfo.processInfo.systemUptime + 5;
    return NO;
}
- (void)updateProcesses:(NSArray<NSNumber *> *)processes {
    if (!processes.count) { [self stop]; return; }
    if ([_processes isEqualToArray:processes] && _io) return;
    if (NSProcessInfo.processInfo.systemUptime < _retryAfter) return;
    [self stop];
    CATapDescription *description = [[CATapDescription alloc] initStereoMixdownOfProcesses:processes];
    description.name = @"Twiddle playback detection";
    description.private = YES;
    description.muteBehavior = CATapUnmuted;
    if (![self check:AudioHardwareCreateProcessTap(description, &_tap) operation:@"Create monitoring tap"]) return;
    AudioStreamBasicDescription format = {0};
    if (![self check:readProperty(_tap, kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal, sizeof(format), &format) operation:@"Read monitoring format"]) return;
    if (format.mFormatID != kAudioFormatLinearPCM || !(format.mFormatFlags & kAudioFormatFlagIsFloat) ||
        (format.mFormatFlags & kAudioFormatFlagIsBigEndian) || format.mBitsPerChannel != 32) {
        [self check:kAudioHardwareUnsupportedOperationError operation:@"Unsupported monitoring format"];
        return;
    }
    NSString *uid = stringProperty(_tap, kAudioTapPropertyUID);
    if (!uid) { [self check:kAudioHardwareUnspecifiedError operation:@"Read monitoring UID"]; return; }
    NSDictionary *config = @{
        @kAudioAggregateDeviceNameKey: @"Twiddle playback monitor",
        @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceIsPrivateKey: @YES,
        @kAudioAggregateDeviceTapAutoStartKey: @YES,
        @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: uid, @kAudioSubTapDriftCompensationKey: @YES}]
    };
    if (![self check:AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)config, &_aggregate) operation:@"Create monitoring device"]) return;
    if (![self check:AudioDeviceCreateIOProcID(_aggregate, measurePlayback, &_state, &_io) operation:@"Create monitoring callback"]) return;
    if (![self check:AudioDeviceStart(_aggregate, _io) operation:@"Start monitoring"]) return;
    _processes = [processes copy];
    _errorMessage = nil;
}
- (void)stop {
    if (_io) {
        AudioDeviceStop(_aggregate, _io);
        AudioDeviceDestroyIOProcID(_aggregate, _io);
        _io = NULL;
    }
    if (_aggregate) { AudioHardwareDestroyAggregateDevice(_aggregate); _aggregate = 0; }
    if (_tap) { AudioHardwareDestroyProcessTap(_tap); _tap = 0; }
    _processes = nil;
    atomic_store(&_state.lastSound, 0);
}
- (void)dealloc { [self stop]; }
@end
