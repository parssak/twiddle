#import "LidAngleMonitor.h"
#import <IOKit/hid/IOHIDManager.h>

@implementation LidAngleMonitor {
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    NSUInteger _generation;
    double _angle;
    BOOL _available;
}
- (instancetype)init {
    if ((self = [super init])) {
        _angle = 90;
        _queue = dispatch_queue_create("com.twiddle.lid-angle", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (double)angle { return _angle; }
- (BOOL)isAvailable { return _available; }
- (void)start {
    if (_timer) return;
    NSUInteger generation = ++_generation;
    // These sensor usages are exposed by supported MacBooks, but are not a
    // guaranteed macOS API. Missing/denied sensors leave the static photo intact.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    _timer = timer;
    __weak LidAngleMonitor *weakSelf = self;
    __block IOHIDManagerRef manager = NULL;
    __block IOHIDDeviceRef sensor = NULL;
    __block BOOL searched = NO;
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 30, NSEC_PER_MSEC * 2);
    dispatch_source_set_event_handler(timer, ^{
        if (!searched) {
            searched = YES;
            manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
            IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)@{
                @kIOHIDVendorIDKey: @0x05ac, @kIOHIDDeviceUsagePageKey: @0x20,
                @kIOHIDDeviceUsageKey: @0x8a});
            if (IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone) == kIOReturnSuccess) {
                NSSet *devices = CFBridgingRelease(IOHIDManagerCopyDevices(manager));
                for (id candidate in devices) {
                    IOHIDDeviceRef device = (__bridge IOHIDDeviceRef)candidate;
                    uint8_t report[8] = {0}; CFIndex length = sizeof(report);
                    if (IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, report, &length) == kIOReturnSuccess && length >= 3) {
                        sensor = (IOHIDDeviceRef)CFRetain(device);
                        break;
                    }
                }
            }
            if (!sensor) dispatch_source_set_timer(timer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        }
        if (!sensor) return;
        uint8_t report[8] = {0}; CFIndex length = sizeof(report);
        IOReturn result = IOHIDDeviceGetReport(sensor, kIOHIDReportTypeFeature, 1, report, &length);
        double angle = report[1] | (report[2] << 8);
        BOOL valid = result == kIOReturnSuccess && length >= 3 && angle <= 180;
        dispatch_async(dispatch_get_main_queue(), ^{
            LidAngleMonitor *self = weakSelf;
            if (!self || self->_generation != generation) return;
            self->_available = valid;
            if (valid) self->_angle = angle;
        });
    });
    dispatch_source_set_cancel_handler(timer, ^{
        if (sensor) CFRelease(sensor);
        if (manager) { IOHIDManagerClose(manager, kIOHIDOptionsTypeNone); CFRelease(manager); }
    });
    dispatch_resume(timer);
}
- (void)stop {
    ++_generation;
    if (_timer) dispatch_source_cancel(_timer);
    _timer = nil;
    _available = NO;
}
- (void)dealloc { [self stop]; }
@end
