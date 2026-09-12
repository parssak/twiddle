#import "WisprActivity.h"
#import "CoreAudioUtilities.h"

BOOL wisprMicrophoneActive(void) {
    AudioObjectPropertyAddress property = address(kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &property, 0, NULL, &size) || !size) return NO;
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &property, 0, NULL, &size, data.mutableBytes)) return NO;
    const AudioObjectID *processes = data.bytes;
    for (NSUInteger i = 0; i < size / sizeof(AudioObjectID); i++) {
        NSString *bundle = stringProperty(processes[i], kAudioProcessPropertyBundleID);
        if (![bundle isEqualToString:@"com.electron.wispr-flow"] && ![bundle hasPrefix:@"com.electron.wispr-flow."]) continue;
        UInt32 active = 0;
        if (!readProperty(processes[i], kAudioProcessPropertyIsRunningInput, kAudioObjectPropertyScopeGlobal, sizeof(active), &active) && active) return YES;
    }
    return NO;
}
