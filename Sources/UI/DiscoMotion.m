#import "DiscoMotion.h"

static const float PullSnapDistance = .15f;
static const double SpinFriction = 1.8, MaximumSpin = 8;

@implementation DiscoMotion {
    vector_float2 _position, _velocity, _grabOffset;
    double _changedAt, _paletteChangedAt;
    double _spinAngle, _spinVelocity, _spinChangedAt;
}
- (vector_float2)offsetAt:(double)time {
    if (_dragging) return _position;
    double t = MAX(0, time - _changedAt);
    if (t > 2) return (vector_float2){0, 0};
    return (float)exp(-7*t) * (_position*(float)cos(11*t) +
        (_velocity + 7*_position)*(float)(sin(11*t)/11));
}
- (void)beginAt:(double)time {
    _position = [self offsetAt:time];
    _grabOffset = _position;
    _velocity = (vector_float2){0, 0};
    _changedAt = time;
    _dragging = YES;
}
- (BOOL)pull:(vector_float2)translation at:(double)time {
    if (!_dragging) return NO;
    vector_float2 target = _grabOffset + translation * (vector_float2){.65, .75};
    target.x = .16f*tanhf(target.x/.16f);
    target.y = fmaxf(-.035f, .36f*tanhf(target.y/.36f));
    double dt = time - _changedAt;
    if (dt > .001) {
        vector_float2 velocity = (target - _position)/(float)dt;
        float speed = simd_length(velocity);
        if (speed > .6f) velocity *= .6f/speed;
        _velocity = .5f*_velocity + .5f*velocity;
    }
    _position = target;
    _changedAt = time;
    if (target.y < PullSnapDistance) return NO;
    _palette++;
    _paletteChangedAt = time;
    // Crossing the latch releases the cord immediately, once per grab.
    _velocity.y = fminf(_velocity.y, 0);
    [self releaseAt:time];
    return YES;
}
- (float)pullProgress { return fmaxf(0, fminf(1, _position.y/PullSnapDistance)); }
- (void)releaseAt:(double)time {
    if (!_dragging) return;
    if (time - _changedAt > .08) _velocity = (vector_float2){0, 0};
    _changedAt = time;
    _dragging = NO;
}
- (double)spinAngleAt:(double)time {
    double elapsed = fmax(0, time-_spinChangedAt);
    return _spinAngle + _spinVelocity*(-expm1(-SpinFriction*elapsed))/SpinFriction;
}
- (double)spinVelocityAt:(double)time {
    return _spinVelocity*exp(-SpinFriction*fmax(0, time-_spinChangedAt));
}
- (void)addSpin:(double)impulse at:(double)time {
    if (!isfinite(impulse) || !isfinite(time)) return;
    _spinAngle = remainder([self spinAngleAt:time], 2*M_PI);
    _spinVelocity = fmax(-MaximumSpin, fmin(MaximumSpin, [self spinVelocityAt:time]+impulse));
    _spinChangedAt = time;
}
- (void)reset {
    _dragging = NO;
    _spinAngle = _spinVelocity = _spinChangedAt = 0;
    _position = _velocity = _grabOffset = (vector_float2){0, 0};
}
- (float)paletteBlendAt:(double)time {
    return (float)fmax(0, fmin(1, (time - _paletteChangedAt)/.25));
}
@end
