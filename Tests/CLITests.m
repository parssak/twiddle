#import "TwiddleControl.h"
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"CLI check failed: %s (line %d)\n",#c,__LINE__); return 1; } } while (0)

static NSDictionary *roundTrip(NSString *path, NSDictionary *request) {
    __block NSDictionary *response;
    __block BOOL done = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *result = twiddleControlRequest(path, request);
        dispatch_async(dispatch_get_main_queue(), ^{ response = result; done = YES; });
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return response;
}
int cliTests(void) {
    CHECK(!twiddleParseCommand(@[@"status"])[@"error"]);
    CHECK((!twiddleParseCommand(@[@"set", @"-0.5"])[@"error"]));
    CHECK((twiddleParseCommand(@[@"set", @"NaN"])[@"error"]));
    CHECK((twiddleParseCommand(@[@"set", @"1.1"])[@"error"]));
    CHECK((twiddleParseCommand(@[@"set", @"0.5oops"])[@"error"]));
    CHECK((twiddleParseCommand(@[@"disco", @"toggle"])[@"error"]));
    CHECK(twiddleParseCommand(@[])[@"error"]);
    CHECK(twiddleParseCommand((id)@[@42])[@"error"]);
    char directory[] = "/tmp/twiddle-cli-test.XXXXXX";
    CHECK(mkdtemp(directory));
    NSString *path = [@(directory) stringByAppendingPathComponent:@"control.sock"];
    TwiddleControlServer *server = [[TwiddleControlServer alloc] initWithPath:path handler:^NSDictionary *(NSDictionary *command) {
        NSCAssert(NSThread.isMainThread, @"Commands must run on the UI thread");
        return @{@"ok":@YES, @"received":command};
    }];
    CHECK([server start]);
    struct stat info;
    CHECK(stat(path.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0600);
    TwiddleControlServer *duplicate = [[TwiddleControlServer alloc] initWithPath:path handler:nil];
    CHECK(![duplicate start]);
    // A client may time out or exit after sending, before the main thread replies.
    int disconnected = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    CHECK(connect(disconnected, (struct sockaddr *)&address, sizeof(address)) == 0);
    const char *status = "{\"arguments\":[\"status\"]}\n";
    CHECK(send(disconnected, status, strlen(status), MSG_NOSIGNAL) > 0);
    close(disconnected);
    NSDictionary *response = roundTrip(path, @{@"arguments":@[@"set", @"-.5"]});
    CHECK([response[@"ok"] boolValue] && [response[@"received"][@"value"] doubleValue] == -.5);
    response = roundTrip(path, @{@"arguments":@[@"disco", @"on"]});
    CHECK([response[@"received"][@"enabled"] boolValue]);
    response = roundTrip(path, @{@"arguments":@[@"invalid"]});
    CHECK(response[@"error"] && ![response[@"ok"] boolValue]);
    [server stop];
    CHECK(access(path.fileSystemRepresentation, F_OK) != 0);
    CHECK(twiddleControlRequest(path, @{@"arguments":@[@"status"]})[@"error"]);
    CHECK(rmdir(directory) == 0);
    puts("CLI parsing, private socket, main-thread dispatch, duplicate protection, and shutdown checks passed.");
    return 0;
}
