# Live effects

Open **FX** in the main popover. Reverb uses the same knob component as the main dial, in a 0–100% mode: drag vertically, scroll, or use arrow keys; double-click or press Return to reset a knob. Pitch ranges from −12 to +12 semitones, with stepped dragging and smooth scrolling. Hold Tape Stop to wind down over 0.9 seconds; release to return to live playback. Closing the popover releases Tape Stop and retains the Reverb and Pitch settings.

Reverb uses Apple's MatrixReverb with the selected room defaults, blending up to 70% wet with 65% original. Pitch uses Apple's pitch Audio Unit. Tape Stop uses one second of stereo history, about 375 KiB at 48 kHz. Audio buffers and units are prepared before capture and released after the callback stops. Pitch shifting and reverb can add latency and tails.

The main dial uses Apple's low/high-pass units, with 5 dB resonance, the existing frequency mapping, 25 ms movement smoothing, and exact center bypass. The chain is tape stop → main filter → pitch → reverb. Reverb tails can ring after Tape Stop reaches silence.

`bash build.sh` runs checks for 44.1/48/96 kHz filter response, exact bypass/reset, fractional and octave pitch, reverb decay, planar/interleaved buffers, and tape slowdown/long holds/release. These checks do not replace listening or device latency measurements.
