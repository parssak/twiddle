#pragma once
#include <math.h>
#include <string.h>

typedef struct { double b0, b1, b2, a1, a2, z1[2], z2[2]; } Biquad;
typedef struct { Biquad low, high; double position, sampleRate; unsigned tick; } Filter;

static void coefficients(Biquad *b, double hz, double rate, int high) {
    double w = 2 * M_PI * fmin(hz, rate * .45) / rate;
    double c = cos(w), alpha = sin(w) / sqrt(2.0), a0 = 1 + alpha;
    b->b0 = (high ? 1 + c : 1 - c) / (2 * a0);
    b->b1 = (high ? -(1 + c) : 1 - c) / a0;
    b->b2 = b->b0;
    b->a1 = -2 * c / a0;
    b->a2 = (1 - alpha) / a0;
}

static double biquad(Biquad *b, double x, unsigned ch) {
    double y = b->b0 * x + b->z1[ch];
    b->z1[ch] = b->b1 * x - b->a1 * y + b->z2[ch];
    b->z2[ch] = b->b2 * x - b->a2 * y;
    return y;
}

static void filterFrame(Filter *f, float target, const float in[2], float out[2]) {
    if ((f->tick++ & 15) == 0) {
        f->position += (target - f->position) * (1 - exp(-16 / (.025 * f->sampleRate)));
        if (fabs(target - f->position) < 1e-7) f->position = target;
        double lowAmount = fmax(0, -f->position), highAmount = fmax(0, f->position);
        coefficients(&f->low, 20000 * pow(115.0 / 20000, lowAmount), f->sampleRate, 0);
        coefficients(&f->high, 20 * pow(10000.0 / 20, highAmount), f->sampleRate, 1);
    }
    double wet = fmin(1, fabs(f->position) / .03);
    for (unsigned ch = 0; ch < 2; ch++) {
        double lo = biquad(&f->low, in[ch], ch), hi = biquad(&f->high, in[ch], ch);
        double filtered = f->position < 0 ? lo : hi;
        out[ch] = (float)(in[ch] + wet * (filtered - in[ch]));
    }
}
