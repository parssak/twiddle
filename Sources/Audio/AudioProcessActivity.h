#import <Foundation/Foundation.h>

// Core Audio process discovery only. These queries never capture audio.
// Microphone scope is "any" or "wispr".
BOOL microphoneActive(NSString *scope);

// Active output streams (including silent streams), without capturing trigger audio.
NSArray<NSNumber *> *activeOutputProcesses(NSSet<NSString *> *bundles);

// Match an app or its dot-delimited helpers, including Arc’s differently cased IDs.
BOOL audioProcessMatchesBundle(NSString *processBundle, NSString *appBundle);
