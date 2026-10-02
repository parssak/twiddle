#import "AudioProcessActivity.h"
#import "CoreAudioUtilities.h"
#include <unistd.h>
#include <libproc.h>

BOOL audioProcessMatchesBundle(NSString *processBundle, NSString *appBundle) {
    if (!processBundle.length || !appBundle.length) return NO;
    NSString *process = processBundle.lowercaseString;
    NSString *app = appBundle.lowercaseString;
    return [process isEqualToString:app] || [process hasPrefix:[app stringByAppendingString:@"."]];
}

BOOL audioProcessMatchesPlaybackTrigger(NSString *processBundle, NSString *executablePath,
                                       NSSet<NSString *> *bundles) {
    if ([executablePath isEqualToString:@"/usr/bin/say"]) return YES;
    for (NSString *bundle in bundles)
        if (audioProcessMatchesBundle(processBundle, bundle)) return YES;
    return NO;
}

static NSData *audioProcessList(void) {
    AudioObjectPropertyAddress property = address(kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &property, 0, NULL, &size) || !size) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &property, 0, NULL, &size, data.mutableBytes)) return nil;
    data.length = size;
    return data;
}

NSArray<NSString *> *audioCaptureBundleIDs(NSSet<NSString *> *bundles, NSArray<NSString *> *processBundles) {
    NSMutableSet *identities = [bundles mutableCopy] ?: [NSMutableSet new];
    for (NSString *processBundle in processBundles) {
        for (NSString *bundle in bundles) {
            if (audioProcessMatchesBundle(processBundle, bundle)) {
                [identities addObject:processBundle];
                break;
            }
        }
    }
    return [identities.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

NSArray<NSString *> *captureBundleIDs(NSSet<NSString *> *bundles) {
    NSData *data = audioProcessList();
    const AudioObjectID *processes = data.bytes;
    NSMutableArray *identities = [NSMutableArray new];
    for (NSUInteger i = 0; i < data.length / sizeof(AudioObjectID); i++) {
        pid_t pid = 0;
        if (readProperty(processes[i], kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, sizeof(pid), &pid) || pid == getpid()) continue;
        NSString *bundle = stringProperty(processes[i], kAudioProcessPropertyBundleID);
        if (bundle.length && ![bundle isEqualToString:NSBundle.mainBundle.bundleIdentifier]) [identities addObject:bundle];
    }
    return audioCaptureBundleIDs(bundles, identities);
}

static BOOL processActive(NSString *scope, NSSet<NSString *> *bundles, NSMutableArray<NSNumber *> *outputs) {
    NSData *data = audioProcessList();
    const AudioObjectID *processes = data.bytes;
    for (NSUInteger i = 0; i < data.length / sizeof(AudioObjectID); i++) {
        pid_t pid = 0;
        if (readProperty(processes[i], kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, sizeof(pid), &pid)) continue;
        // Our process tap also counts as input; it must never hold its own preset.
        if (pid == getpid()) continue;
        NSString *bundle = stringProperty(processes[i], kAudioProcessPropertyBundleID);
        if ([bundle isEqualToString:NSBundle.mainBundle.bundleIdentifier]) continue;
        if (bundles) {
            UInt32 active = 0;
            if (readProperty(processes[i], kAudioProcessPropertyIsRunningOutput,
                kAudioObjectPropertyScopeGlobal, sizeof(active), &active) || !active) continue;
            if (!audioProcessMatchesPlaybackTrigger(bundle, nil, bundles)) {
                // CLI speech has no app bundle. Resolve only active, unmatched
                // outputs and require the system executable, not its name.
                char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
                if (proc_pidpath(pid, path, sizeof(path)) <= 0 ||
                    !audioProcessMatchesPlaybackTrigger(bundle, [NSString stringWithUTF8String:path], bundles)) continue;
            }
            [outputs addObject:@(processes[i])];
            continue;
        } else if (![scope isEqualToString:@"any"] &&
            !audioProcessMatchesBundle(bundle, @"com.electron.wispr-flow")) continue;
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

BOOL microphoneActive(NSString *scope) { return processActive(scope, nil, nil); }
NSArray<NSNumber *> *activeOutputProcesses(NSSet<NSString *> *bundles) {
    NSMutableArray *outputs = [NSMutableArray new];
    processActive(nil, bundles ?: [NSSet set], outputs);
    return [outputs sortedArrayUsingSelector:@selector(compare:)];
}
