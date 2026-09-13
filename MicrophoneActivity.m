#import "MicrophoneActivity.h"
#import "CoreAudioUtilities.h"
#include <unistd.h>

BOOL microphoneActive(NSString *scope) {
    AudioObjectPropertyAddress property = address(kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &property, 0, NULL, &size) || !size) return NO;
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &property, 0, NULL, &size, data.mutableBytes)) return NO;
    const AudioObjectID *processes = data.bytes;
    for (NSUInteger i = 0; i < size / sizeof(AudioObjectID); i++) {
        pid_t pid = 0;
        if (readProperty(processes[i], kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, sizeof(pid), &pid)) continue;
        // Our process tap also counts as input; it must never hold its own preset.
        if (pid == getpid()) continue;
        NSString *bundle = stringProperty(processes[i], kAudioProcessPropertyBundleID);
        if ([bundle isEqualToString:NSBundle.mainBundle.bundleIdentifier]) continue;
        if (![scope isEqualToString:@"any"] &&
            ![bundle isEqualToString:@"com.electron.wispr-flow"] && ![bundle hasPrefix:@"com.electron.wispr-flow."]) continue;
        UInt32 active = 0;
        if (readProperty(processes[i], kAudioProcessPropertyIsRunningInput, kAudioObjectPropertyScopeGlobal, sizeof(active), &active) || !active) continue;
        // Background services can report active input without using any device.
        // Require a device assigned specifically to this process's input scope.
        AudioObjectPropertyAddress inputs = address(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeInput);
        UInt32 inputSize = 0;
        if (!AudioObjectGetPropertyDataSize(processes[i], &inputs, 0, NULL, &inputSize) &&
            inputSize >= sizeof(AudioObjectID)) return YES;
    }
    return NO;
}
