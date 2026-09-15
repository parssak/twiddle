#import "UpdateChecker.h"

@interface UpdateChecker () {
    BOOL _checkingForUpdates;
}
@property (weak) NSWindow *window;
@end

@implementation UpdateChecker
- (void)checkFromWindow:(NSWindow *)window {
    self.window = window;
    if (_checkingForUpdates) return;
    _checkingForUpdates = YES;
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/parssak/twiddle/releases/latest"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSString *current = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
    [request setValue:[@"Twiddle/" stringByAppendingString:current] forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    __weak UpdateChecker *weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:
        ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
        NSError *jsonError = nil;
        NSDictionary *payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
        NSString *tag = [payload isKindOfClass:NSDictionary.class] ? payload[@"tag_name"] : nil;
        NSString *releasePage = [payload isKindOfClass:NSDictionary.class] ? payload[@"html_url"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            UpdateChecker *self = weakSelf;
            if (!self) return;
            self->_checkingForUpdates = NO;
            NSAlert *alert = [NSAlert new];
            if (error || http.statusCode != 200 || !tag.length) {
                alert.messageText = @"Couldn’t check for updates";
                alert.informativeText = error.localizedDescription ?: jsonError.localizedDescription ?:
                    @"GitHub didn’t return a release. Try again in a moment.";
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
                return;
            }
            NSString *latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
            if ([latest compare:current options:NSNumericSearch] == NSOrderedDescending) {
                alert.messageText = [NSString stringWithFormat:@"Twiddle %@ is available", tag];
                alert.informativeText = [NSString stringWithFormat:@"You’re currently using v%@.", current];
                [alert addButtonWithTitle:@"Download"];
                [alert addButtonWithTitle:@"Later"];
                [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
                    if (result != NSAlertFirstButtonReturn) return;
                    NSURL *downloadURL = [NSURL URLWithString:releasePage ?: @"https://github.com/parssak/twiddle/releases/latest"];
                    [NSWorkspace.sharedWorkspace openURL:downloadURL];
                }];
            } else {
                alert.messageText = @"Twiddle is up to date";
                alert.informativeText = [NSString stringWithFormat:@"You’re using the latest version, v%@.", current];
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
            }
        });
    }] resume];
}
@end
