#import <Foundation/Foundation.h>

@class CATapDescription;

// Core Audio process discovery only. These queries never capture audio.
// Microphone scope is "any" or "wispr".
BOOL microphoneActive(NSString *scope);

// Active output streams for selected apps and /usr/bin/say (including silent
// streams), without capturing trigger audio. System speech needs no selection.
NSArray<NSNumber *> *activeOutputProcesses(NSSet<NSString *> *bundles);

// A process running microphone input and output together, as macOS voice
// processing does during calls and assistant voice modes. Twiddle's target apps
// are excluded: their call audio already passes through Twiddle and must not be ducked.
BOOL voiceChatActive(NSSet<NSString *> *excludedBundles);
BOOL audioProcessIsVoiceChat(NSString *processBundle, BOOL runningInput, BOOL hasInputDevice, BOOL runningOutput,
                             NSSet<NSString *> *excludedBundles);

BOOL audioProcessMatchesPlaybackTrigger(NSString *processBundle, NSString *executablePath,
                                       NSSet<NSString *> *bundles);

// Live Core Audio object IDs and their exact bundle identifiers, excluding Twiddle.
NSDictionary<NSNumber *, NSString *> *audioProcessBundles(void);

// Update a selected-app tap with live process objects and bundle IDs for restoration.
// A failed enumeration (nil) leaves the previous live objects in place.
BOOL updateCaptureDescription(CATapDescription *description, NSSet<NSString *> *bundles,
                              NSDictionary<NSNumber *, NSString *> *processBundles);

// Match an app or its dot-delimited helpers, including Arc’s differently cased IDs.
BOOL audioProcessMatchesBundle(NSString *processBundle, NSString *appBundle);
