#import <Foundation/Foundation.h>

// Reads Core Audio process activity only; never opens or reads the microphone.
BOOL microphoneActive(NSString *scope);
