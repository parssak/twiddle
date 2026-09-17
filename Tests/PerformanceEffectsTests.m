#include "PerformanceEffects.h"
#include <stdio.h>
#define VERIFY_EFFECT(x) do { if (!(x)) { fprintf(stderr, "Performance effects failed: %s line %d\n", #x, __LINE__); performanceDestroy(&d); return 1; } } while (0)
int performanceEffectsTests(void) {
    const double rates[] = {44100, 48000, 96000};
    for (unsigned r = 0; r < 3; r++) {
        double rate = rates[r];
        PerformanceEffects d = {0};
        VERIFY_EFFECT(performanceInit(&d, rate));
        for (unsigned i = 0; i < rate; i++) {
            float dry = .2f * sin(2*M_PI*220*i/rate), x[] = {dry, -dry};
            performanceFrame(&d, 0, false, x);
            VERIFY_EFFECT(x[0] == dry && x[1] == -dry);
        }
        double difference = 0;
        for (unsigned i = 0; i < rate * 2; i++) {
            float dry = .2f * sin(2*M_PI*220*i/rate), x[] = {dry, -dry};
            performanceFrame(&d, 1, false, x);
            VERIFY_EFFECT(isfinite(x[0]) && fabsf(x[0]) <= 1 && x[0] == -x[1]);
            if (i > rate) difference += (x[0] - dry) * (x[0] - dry);
        }
        VERIFY_EFFECT(difference > 1);
        VERIFY_EFFECT(performanceInit(&d, rate));
        unsigned early = 0, late = 0;
        float previous = 0;
        // Hold well past the ring length: it must stay silent, never wrap to live audio.
        for (unsigned i = 0; i < rate * 4; i++) {
            float dry = .2f * sin(2*M_PI*440*i/rate), x[] = {dry, dry};
            performanceFrame(&d, 0, true, x);
            if (previous <= 0 && x[0] > 0) {
                if (i > rate*.1 && i < rate*.25) early++;
                if (i > rate*.5 && i < rate*.65) late++;
            }
            previous = x[0];
            if (i > rate*1.1) VERIFY_EFFECT(fabsf(x[0]) < 1e-6);
        }
        VERIFY_EFFECT(early > 30 && late > 5 && late < early*.7);
        // Release returns to the current live samples, not stored playback.
        for (unsigned i = 0; i < rate; i++) {
            float x[] = {.17f, -.23f}; performanceFrame(&d, 0, false, x);
            if (i > rate*.9) VERIFY_EFFECT(x[0] == .17f && x[1] == -.23f);
        }
        for (unsigned i = 0; i < rate*4; i++) {
            float x[] = {.95f, -.95f}; performanceFrame(&d, 1, (i%4000) < 2000, x);
            VERIFY_EFFECT(isfinite(x[0]) && fabsf(x[0]) <= 1 && isfinite(x[1]) && fabsf(x[1]) <= 1);
        }
        for (unsigned i = 0; i < rate; i++) {
            float x[] = {.17f, -.23f}; performanceFrame(&d, 0, false, x);
            if (i > rate*.9) VERIFY_EFFECT(x[0] == .17f && x[1] == -.23f);
        }
        performanceDestroy(&d);
        VERIFY_EFFECT(!performanceInit(&d, NAN));
        performanceDestroy(&d);
        printf("Performance %.0f Hz: phaser, tape slowdown/long hold/release, combined peaks, exact reset passed.\n", rate);
    }
    return 0;
}
