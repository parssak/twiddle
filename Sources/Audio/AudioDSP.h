#pragma once
#include <math.h>

static inline float audioUnitAmount(float value) {
    return isfinite(value) ? fminf(1, fmaxf(0, value)) : 0;
}
static inline float audioSoftLimit(float value) {
    return fabsf(value) <= .85f ? value : copysignf(.85f + .15f * tanhf((fabsf(value) - .85f) / .15f), value);
}
