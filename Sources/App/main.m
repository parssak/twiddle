#import "AppDelegate.h"
#import "AudioEngine.h"
#import "TwiddleControl.h"

int selfTest(void);

int main(int argc, const char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return selfTest();
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "--cli")) return twiddleCLI(argc-2, argv+2);
        if ([[@(argv[0]) lastPathComponent] isEqualToString:@"twiddle"]) return twiddleCLI(argc-1, argv+1);
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
        [appMenu addItemWithTitle:@"Quit Twiddle" action:@selector(terminate:) keyEquivalent:@"q"];
        item.submenu = appMenu;
        app.mainMenu = menu;
        [app run];
    }
    return 0;
}
