#import "TwiddleControl.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>

static NSDictionary *failure(NSString *message) { return @{@"ok":@NO, @"error":message}; }
NSString *twiddleControlPath(void) {
    char directory[PATH_MAX];
    if (!confstr(_CS_DARWIN_USER_TEMP_DIR, directory, sizeof(directory))) return nil;
    return [[@(directory) stringByAppendingPathComponent:@"twiddle-control"] stringByAppendingPathComponent:@"control.sock"];
}
NSDictionary *twiddleParseCommand(NSArray<NSString *> *arguments) {
    if (![arguments isKindOfClass:NSArray.class] || !arguments.count || arguments.count > 2)
        return failure(@"Expected a command; run twiddle help.");
    for (id value in arguments) if (![value isKindOfClass:NSString.class]) return failure(@"Arguments must be strings.");
    NSString *command = arguments[0];
    if ([@[@"status", @"reset", @"apply", @"settings", @"update"] containsObject:command] && arguments.count == 1)
        return @{@"command":command};
    if ([command isEqual:@"disco"] && arguments.count == 2 && [@[@"on", @"off"] containsObject:arguments[1]])
        return @{@"command":command, @"enabled":@([arguments[1] isEqual:@"on"])};
    if ([@[@"set", @"preset"] containsObject:command] && arguments.count == 2) {
        NSScanner *scanner = [NSScanner scannerWithString:arguments[1]];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        double value;
        if ([scanner scanDouble:&value] && scanner.isAtEnd && isfinite(value) && value >= -1 && value <= 1)
            return @{@"command":command, @"value":@(value)};
        return failure(@"Value must be a finite number from -1 to 1 (negative: low-pass, 0: bypass, positive: high-pass).");
    }
    return failure(@"Unknown command or arguments; run twiddle help.");
}
static BOOL addressForPath(NSString *path, struct sockaddr_un *address) {
    const char *name = path.fileSystemRepresentation;
    if (!name || strlen(name) >= sizeof(address->sun_path)) return NO;
    memset(address, 0, sizeof(*address));
    address->sun_family = AF_UNIX;
    strlcpy(address->sun_path, name, sizeof(address->sun_path));
    return YES;
}
static void configureSocket(int fd) {
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct timeval timeout = {2, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
}
static BOOL writeJSON(int fd, NSDictionary *object) {
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] mutableCopy];
    if (!data) return NO;
    [data appendBytes:"\n" length:1];
    NSUInteger sent = 0;
    while (sent < data.length) {
        ssize_t n = send(fd, (const char *)data.bytes+sent, data.length-sent, MSG_NOSIGNAL);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        sent += n;
    }
    return YES;
}
static NSDictionary *readJSON(int fd) {
    NSMutableData *data = [NSMutableData new];
    char buffer[1024];
    while (data.length < 16384) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return nil;
        char *end = memchr(buffer, '\n', n);
        [data appendBytes:buffer length:end ? (NSUInteger)(end-buffer) : (NSUInteger)n];
        if (end) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            return [object isKindOfClass:NSDictionary.class] ? object : nil;
        }
    }
    return nil;
}
NSDictionary *twiddleControlRequest(NSString *path, NSDictionary *request) {
    struct sockaddr_un address;
    if (!addressForPath(path, &address)) return failure(@"Could not locate Twiddle's control socket.");
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return failure(@"Could not create a control connection.");
    configureSocket(fd);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return failure(@"Twiddle is not running or its control channel is unavailable. Open Twiddle first.");
    }
    NSDictionary *response = writeJSON(fd, request) ? readJSON(fd) : nil;
    close(fd);
    return response ?: failure(@"Twiddle did not return a valid response within two seconds.");
}

@implementation TwiddleControlServer {
    NSString *_path;
    NSDictionary *(^_handler)(NSDictionary *);
    dispatch_source_t _listener;
    BOOL _ownsSocket;
}
- (instancetype)initWithPath:(NSString *)path handler:(NSDictionary *(^)(NSDictionary *))handler {
    if ((self = [super init])) { _path = [path copy]; _handler = [handler copy]; }
    return self;
}
- (BOOL)start {
    if (_listener) return YES;
    struct sockaddr_un address;
    if (!addressForPath(_path, &address)) return NO;
    NSString *directory = _path.stringByDeletingLastPathComponent;
    if (mkdir(directory.fileSystemRepresentation, 0700) != 0 && errno != EEXIST) return NO;
    struct stat info;
    if (lstat(directory.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid() || (info.st_mode & 077)) return NO;
    if (!lstat(_path.fileSystemRepresentation, &info)) {
        if (!S_ISSOCK(info.st_mode) || info.st_uid != getuid()) return NO;
        int probe = socket(AF_UNIX, SOCK_STREAM, 0);
        if (probe < 0) return NO;
        int result = connect(probe, (struct sockaddr *)&address, sizeof(address));
        int connectionError = errno;
        close(probe);
        if (!result || (connectionError != ECONNREFUSED && connectionError != ENOENT)) return NO;
        if (unlink(_path.fileSystemRepresentation) != 0 && errno != ENOENT) return NO;
    }
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { close(fd); return NO; }
    _ownsSocket = YES;
    if (chmod(_path.fileSystemRepresentation, 0600) || listen(fd, 8)) { close(fd); [self stop]; return NO; }
    fcntl(fd, F_SETFL, O_NONBLOCK);
    dispatch_queue_t queue = dispatch_queue_create("com.twiddle.control", DISPATCH_QUEUE_SERIAL);
    _listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    __weak TwiddleControlServer *weakSelf = self;
    dispatch_source_set_event_handler(_listener, ^{
        int client;
        while ((client = accept(fd, NULL, NULL)) >= 0) {
            fcntl(client, F_SETFL, 0);
            configureSocket(client);
            uid_t uid; gid_t gid;
            if (getpeereid(client, &uid, &gid) || uid != getuid()) { close(client); continue; }
            NSDictionary *request = readJSON(client);
            if (!request) { close(client); continue; }
            NSDictionary *command = twiddleParseCommand(request[@"arguments"]);
            __block NSDictionary *response = command;
            if (!command[@"error"]) dispatch_sync(dispatch_get_main_queue(), ^{
                TwiddleControlServer *self = weakSelf;
                response = self && self->_listener ? self->_handler(command) : failure(@"Twiddle is shutting down.");
            });
            writeJSON(client, response);
            close(client);
        }
    });
    dispatch_source_set_cancel_handler(_listener, ^{ close(fd); });
    dispatch_resume(_listener);
    return YES;
}
- (void)stop {
    if (_listener) { dispatch_source_cancel(_listener); _listener = nil; }
    if (_ownsSocket) { unlink(_path.fileSystemRepresentation); _ownsSocket = NO; }
}
- (void)dealloc { [self stop]; }
@end

int twiddleCLI(int argc, const char *argv[]) {
    NSMutableArray *arguments = [NSMutableArray new];
    for (int i=0; i<argc; i++) if (strcmp(argv[i], "--json")) [arguments addObject:@(argv[i])];
    if (!arguments.count || [@[@"help", @"--help", @"-h"] containsObject:arguments[0]]) {
        puts("Usage: twiddle <command> [--json]\n\n"
            "  status          Read current state\n"
            "  set VALUE       Set filter (-1..1); overrides active automation until it releases\n"
            "  preset VALUE    Save the Auto-apply value (-1..1)\n"
            "  apply           Apply the saved preset as the manual filter\n"
            "  reset           Bypass; suppress active automation until it releases\n"
            "  disco on|off    Enter or leave disco mode\n"
            "  settings        Open Settings\n"
            "  update          Check for updates\n\n"
            "Twiddle must be running. Responses are JSON. Exit codes: 0 success, 1 unavailable, 2 invalid arguments.");
        return 0;
    }
    NSDictionary *command = twiddleParseCommand(arguments);
    BOOL invalid = command[@"error"] != nil;
    NSDictionary *response = invalid ? command : twiddleControlRequest(twiddleControlPath(), @{@"arguments":arguments});
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout);
    return invalid ? 2 : [response[@"ok"] boolValue] ? 0 : 1;
}
