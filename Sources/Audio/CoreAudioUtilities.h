#pragma once
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

static inline AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){selector, scope, kAudioObjectPropertyElementMain};
}

static inline OSStatus readProperty(AudioObjectID object, AudioObjectPropertySelector selector,
                             AudioObjectPropertyScope scope, UInt32 size, void *value) {
    AudioObjectPropertyAddress a = address(selector, scope);
    return AudioObjectGetPropertyData(object, &a, 0, NULL, &size, value);
}

static inline NSString *stringProperty(AudioObjectID object, AudioObjectPropertySelector selector) {
    CFStringRef value = NULL;
    if (readProperty(object, selector, kAudioObjectPropertyScopeGlobal, sizeof(value), &value)) return nil;
    return CFBridgingRelease(value);
}
