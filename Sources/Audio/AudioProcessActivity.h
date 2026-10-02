#import <Foundation/Foundation.h>

// Core Audio process discovery only. These queries never capture audio.
// Microphone scope is "any" or "wispr".
BOOL microphoneActive(NSString *scope);

// Active output streams for selected apps and /usr/bin/say (including silent
// streams), without capturing trigger audio. System speech needs no selection.
NSArray<NSNumber *> *activeOutputProcesses(NSSet<NSString *> *bundles);

BOOL audioProcessMatchesPlaybackTrigger(NSString *processBundle, NSString *executablePath,
                                       NSSet<NSString *> *bundles);

// Exact tap identities for selected apps and their existing audio helpers, even
// while those helpers are silent. Core Audio does not expand bundle ID prefixes.
NSArray<NSString *> *captureBundleIDs(NSSet<NSString *> *bundles);
NSArray<NSString *> *audioCaptureBundleIDs(NSSet<NSString *> *bundles, NSArray<NSString *> *processBundles);

// Match an app or its dot-delimited helpers, including Arc’s differently cased IDs.
BOOL audioProcessMatchesBundle(NSString *processBundle, NSString *appBundle);
