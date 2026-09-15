#import "ApplicationInfo.h"

static NSArray<NSArray<NSString *> *> *apps(void) {
    return @[@[@"com.spotify.client", @"Spotify"], @[@"com.apple.Music", @"Music"],
             @[@"com.google.Chrome", @"Chrome"], @[@"company.thebrowser.Browser", @"Arc"],
             @[@"company.thebrowser.dia", @"Dia"]];
}

@implementation ApplicationInfo
+ (NSString *)nameForBundle:(NSString *)bundle {
    for (NSArray *app in apps()) if ([app[0] isEqualToString:bundle]) return app[1];
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundle];
    return url ? [[NSFileManager.defaultManager displayNameAtPath:url.path] stringByDeletingPathExtension] : bundle;
}
+ (NSImage *)iconForBundle:(NSString *)bundle {
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundle];
    NSImage *image = url ? [NSWorkspace.sharedWorkspace iconForFile:url.path] :
        [NSImage imageWithSystemSymbolName:@"app" accessibilityDescription:nil];
    image.size = NSMakeSize(20, 20);
    return image;
}
@end
