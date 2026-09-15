#import <Foundation/Foundation.h>

NSString *twiddleControlPath(void);
NSDictionary *twiddleParseCommand(NSArray<NSString *> *arguments);
NSDictionary *twiddleControlRequest(NSString *path, NSDictionary *request);
int twiddleCLI(int argc, const char *argv[]);

@interface TwiddleControlServer : NSObject
- (instancetype)initWithPath:(NSString *)path handler:(NSDictionary *(^)(NSDictionary *command))handler;
- (BOOL)start;
- (void)stop;
@end
