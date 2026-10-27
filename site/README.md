# Landing page

Static HTML and CSS for twiddle.fun, with vanilla JavaScript for the demo and feature cards. Dark mode only. No dependencies or build step. Geist is self-hosted with its SIL Open Font License in `assets/Geist-OFL.txt` (from https://github.com/vercel/geist-font).

Preview from the repository root:

```sh
/usr/bin/python3 -m http.server 8765 --directory site
```

Open http://localhost:8765.

Vercel project: `goose-party/twiddle`, serving `twiddle.fun`. From the repository root, run `npx vercel@59.16.0 link --yes --project twiddle --scope goose-party` once, then `npx vercel@59.16.0 --prod --scope goose-party`. The root `vercel.json` sets `site` as the output directory with no build command; `.vercelignore` allows only public website files and `vercel.json`. Before deploying, run `npx vercel@59.16.0 deploy --dry --json --scope goose-party` and check that the manifest includes `site/index.html` and both appcasts, with no files outside `site/` other than `vercel.json`.

The three download links in `index.html` (navigation, hero and Install) point to the signed and notarized v0.9.3 DMG, and the hero shows the version and links to its release notes. Update all of them when publishing a new release. Stylesheet and script URLs carry `?v=` with the first 10 hex characters of each file's SHA-256; update them when a file changes.

Brand assets are derived from `Assets/TwiddleWordmark.svg`, `Assets/AppIcon.png` (`assets/icon.png` and `assets/icon-224.jpg`), and `Assets/KnobMetal.png` in this repository. The desktop scene uses an original CSS gradient; third-party marks and font provenance are listed in [asset sources](assets/SOURCES.md).

## Scripts

- `dial.js`: the shared knob (geometry, ticks and accent colour), the app's cutoff mapping (low-pass 20 kHz to 115 Hz, high-pass 20 Hz to 10 kHz), biquad response curves, and layout helpers.
- `demo.js`: the scripted desktop demo. Each chapter (Turn, Shortcuts, Auto-apply, Effects, Disco) is a function of time, so pause, replay, chapter seeking and looping are exact. The popover follows the native 240 × 216 layout and the 140-point FX tray. The stage is laid out at 1200 × 720, or 640 × 900 for narrow frames, and scaled to fit. The demo plays only while it is on screen, and does not autoplay with Reduce Motion.
- `features.js`: the animated feature cards. Each plays while visible and has a pause button.
- `disco.js`: renders `disco.frag.glsl` for the demo, the disco card, and the page easter egg: sweep the pointer across every letter of the navigation wordmark or the headline.

Grabbing any demo control pauses the script and hands it over: drag, scroll or use the arrow keys (Shift for fine control); double-click or press 0 for bypass. The menu bar icon toggles the panel, and FX opens reverb, pitch, tape stop and disco. Play resumes the script.

**Play with sound**, the Sound toggle, or the first knob interaction starts “Lights Down Low”, an original four-bar disco loop that `demo.js` renders locally with an `OfflineAudioContext`. Web Audio applies the filter with the app's 5 dB resonance, a reverb mix that matches the app's 70% wet and 65% dry maximum, pitch by re-rendering the loop in semitones, and a 0.9-second tape stop. The webpage does not access other apps or their audio. Geist and all assets are self-hosted.
