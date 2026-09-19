# Landing page

Static HTML and CSS for twiddle.fun, with a small vanilla JavaScript knob demo. No dependencies or build step. Geist is self-hosted with its SIL Open Font License in `assets/Geist-OFL.txt` (from https://github.com/vercel/geist-font).

Preview from the repository root:

```sh
/usr/bin/python3 -m http.server 8765 --directory site
```

Open http://localhost:8765.

Vercel project: `goose-party/twiddle`, serving `twiddle.fun`. From the repository root, run `npx vercel@59.16.0 link --yes --project twiddle --scope goose-party` once, then `npx vercel@59.16.0 --prod --scope goose-party`. The root `vercel.json` sets `site` as the output directory with no build command; `.vercelignore` excludes local build artifacts.

The download in `index.html` points to the signed and notarized v0.7 DMG. Update the versioned asset URL when publishing a new release.

Assets are derived from `Assets/TwiddleWordmark.svg`, `Assets/AppIcon.png`, and `Assets/KnobMetal.png` in this repository. The knob uses the app’s metal texture and filter-frequency curves. Drag or use arrow keys (Shift for fine control); double-click or press 0 for bypass. Hovering does not move the knob.

Play demo starts an original, locally synthesized eight-second music loop through a Web Audio low/high-pass filter. Playback starts only on click; pause suspends the audio context. The spectrum is an illustration of filter response, not a live analyser. Source icons illustrate the native app’s system-wide support; the webpage does not access those apps or their audio. Geist and all assets are self-hosted.
