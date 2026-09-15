#pragma once
#include <stdbool.h>
#include <math.h>
#include <stddef.h>

// -60 dBFS ignores numerical noise without requiring normal listening volume.
static inline bool audioSamplesAudible(const float *samples, size_t count) {
    for (size_t i = 0; i < count; i++)
        if (isfinite(samples[i]) && fabsf(samples[i]) >= .001f) return true;
    return false;
}
static inline bool audioRecentlyAudible(double elapsed) {
    return elapsed >= 0 && elapsed < .3;
}
