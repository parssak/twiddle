#import <Foundation/Foundation.h>

// Core Audio process discovery only. These queries never capture audio.
// Microphone scope is "any" or "wispr".
BOOL microphoneActive(NSString *scope);

// Active output streams (including silent streams), without capturing trigger audio.
NSArray<NSNumber *> *activeOutputProcesses(NSSet<NSString *> *bundles);

// Exact tap identities for selected apps and their existing audio helpers, even
// while those helpers are silent. Core Audio does not expand bundle ID prefixes.
NSArray<NSString *> *captureBundleIDs(NSSet<NSString *> *bundles);
NSArray<NSString *> *audioCaptureBundleIDs(NSSet<NSString *> *bundles, NSArray<NSString *> *processBundles);

// Match an app or its dot-delimited helpers, including Arc’s differently cased IDs.
BOOL audioProcessMatchesBundle(NSString *processBundle, NSString *appBundle);
