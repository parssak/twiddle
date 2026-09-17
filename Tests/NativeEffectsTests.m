#include "NativeEffects.h"
#include <math.h>
#include <stdio.h>
#define CHECK_ROOM(x) do { if (!(x)) { fprintf(stderr, "Reverb failed: %s line %d\n", #x, __LINE__); nativeEffectDestroy(&room); return 1; } } while (0)
int nativeEffectTests(void) {
    double rates[] = {44100, 48000, 96000};
    for (unsigned r = 0; r < 3; r++) {
        NativeEffect room = {0};
        CHECK_ROOM(nativeEffectInit(&room, rates[r], NativeEffectReverb) == noErr);
        float samples[1024];
        AudioBufferList list = {1, {{2, sizeof(samples), samples}}};
        double early = 0, late = 0;
        for (unsigned block = 0; block < (unsigned)(rates[r] * 8 / 512); block++) {
            for (unsigned i = 0; i < 1024; i++) samples[i] = 0;
            if (block == 5) samples[0] = samples[1] = .8;
            CHECK_ROOM(nativeEffectProcess(&room, &list, 512, 1) == noErr);
            for (unsigned i = 0; i < 1024; i++) {
                CHECK_ROOM(isfinite(samples[i]) && fabsf(samples[i]) < 2);
                if (block > 5 && block < rates[r] * 2 / 512) early += samples[i] * samples[i];
                if (block > rates[r] * 7 / 512) late += samples[i] * samples[i];
            }
        }
        CHECK_ROOM(early > .001 && late < early * .01);
        // Planar route and the partial final block follow the same processing path.
        float left[700], right[700];
        struct { UInt32 count; AudioBuffer buffers[2]; } planar = {2, {{1, sizeof(left), left}, {1, sizeof(right), right}}};
        for (unsigned b = 0; b < 30; b++) {
            for (unsigned i = 0; i < 700; i++) { left[i] = .12; right[i] = -.23; }
            CHECK_ROOM(nativeEffectProcess(&room, (AudioBufferList *)&planar, 700, 0) == noErr);
        }
        CHECK_ROOM(left[699] == .12f && right[699] == -.23f);
        printf("Apple Matrix reverb %.0f Hz: wet tail energy %.3f, decay, neutral, planar and interleaved routes passed.\n", rates[r], early);
        nativeEffectDestroy(&room);
        // Maximum Matrix reverb retains the original full-range track.
        double wetEnergy[2] = {0};
        for (unsigned tone = 0; tone < 2; tone++) {
            CHECK_ROOM(nativeEffectInit(&room, rates[r], NativeEffectReverb) == noErr);
            for (unsigned block = 0; block < (unsigned)(rates[r] * 3 / 512); block++) {
                for (unsigned i = 0; i < 512; i++) {
                    float dry = .15f * sin(2 * M_PI * (tone ? 1000 : 60) * (block * 512 + i) / rates[r]);
                    samples[2 * i] = samples[2 * i + 1] = dry;
                }
                CHECK_ROOM(nativeEffectProcess(&room, &list, 512, 1) == noErr);
                if (block * 512 > rates[r] * 2) {
                    for (unsigned i = 0; i < 512; i++) {
                        float dry = .15f * sin(2 * M_PI * (tone ? 1000 : 60) * (block * 512 + i) / rates[r]);
                        CHECK_ROOM(fabsf(samples[2 * i] - (.65f * dry + .7f * room.wet[0][i])) < 1e-5);
                        wetEnergy[tone] += room.wet[0][i] * room.wet[0][i];
                    }
                }
            }
            nativeEffectDestroy(&room);
        }
        CHECK_ROOM(wetEnergy[0] > .001 && wetEnergy[1] > .001);
        printf("Matrix reverb %.0f Hz: full-range wet output and dry signal retained at maximum.\n", rates[r]);
        CHECK_ROOM(nativeEffectInit(&room, rates[r], NativeEffectPitch) == noErr);
        const float shifts[] = {-12, -3.5f, .5f, 12};
        for (unsigned shift = 0; shift < sizeof(shifts) / sizeof(shifts[0]); shift++) {
            unsigned crossings = 0, measured = 0;
            float previous = 0;
            for (unsigned block = 0; block < (unsigned)(rates[r] * 3 / 512); block++) {
                for (unsigned i = 0; i < 512; i++) {
                    float tone = .15f * sin(2 * M_PI * 220 * (block * 512 + i) / rates[r]);
                    samples[i * 2] = tone; samples[i * 2 + 1] = -tone;
                }
                CHECK_ROOM(nativeEffectProcess(&room, &list, 512, shifts[shift]) == noErr);
                for (unsigned i = 0; i < 512; i++) {
                    float value = samples[i * 2];
                    CHECK_ROOM(isfinite(value) && fabsf(value) <= 1);
                    if (block * 512 + i >= rates[r]) {
                        if (previous <= 0 && value > 0) crossings++;
                        measured++;
                    }
                    previous = value;
                }
            }
            double frequency = crossings * rates[r] / measured;
            CHECK_ROOM(fabs(frequency - (220 * pow(2, shifts[shift] / 12.0))) < 3);
            printf("Pitch %.0f Hz: %+.2f semitones produced %.1f Hz from 220 Hz.\n", rates[r], shifts[shift], frequency);
        }
        for (unsigned b = 0; b < 30; b++) {
            for (unsigned i = 0; i < 1024; i++) samples[i] = .12f;
            CHECK_ROOM(nativeEffectProcess(&room, &list, 512, 0) == noErr);
        }
        CHECK_ROOM(samples[1023] == .12f);
        nativeEffectDestroy(&room);
    }
    return 0;
}
