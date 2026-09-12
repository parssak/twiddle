#import "AppDelegate.h"
#import "AudioEngine.h"

int selfTest(void);

int main(int argc, const char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return selfTest();
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--probe") == 0) {
            AudioEngine *probe = [AudioEngine new];
            NSMutableSet *selected = nil;
            if (argc > 2) {
                selected = [NSMutableSet set];
                for (int i = 2; i < argc; i++) [selected addObject:@(argv[i])];
            }
            BOOL ok = [probe startWithBundles:selected probe:YES];
            if (!ok) fprintf(stderr, "%s\n", probe.errorMessage.UTF8String);
            return ok ? 0 : 1;
        }
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSMenu *menu = [NSMenu new];
        NSMenuItem *item = [NSMenuItem new];
        [menu addItem:item];
        NSMenu *appMenu = [NSMenu new];
        [appMenu addItemWithTitle:@"Quit Lowpasser" action:@selector(terminate:) keyEquivalent:@"q"];
        item.submenu = appMenu;
        app.mainMenu = menu;
        [app run];
    }
    return 0;
}
