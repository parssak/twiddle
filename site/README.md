# Landing page

Static HTML and CSS for twiddle.fun, with a vanilla JavaScript preview of Twiddle's menu bar popover. No dependencies or build step. Geist is self-hosted with its SIL Open Font License in `assets/Geist-OFL.txt` (from https://github.com/vercel/geist-font).

Preview from the repository root:

```sh
/usr/bin/python3 -m http.server 8765 --directory site
```

Open http://localhost:8765.

Vercel project: `goose-party/twiddle`, serving `twiddle.fun`. From the repository root, run `npx vercel@59.16.0 link --yes --project twiddle --scope goose-party` once, then `npx vercel@59.16.0 --prod --scope goose-party`. The root `vercel.json` sets `site` as the output directory with no build command; `.vercelignore` allows only public website files and `vercel.json`. Before deploying, run `npx vercel@59.16.0 deploy --dry --json --scope goose-party` and check that the manifest includes `site/index.html` and both appcasts, with no files outside `site/` other than `vercel.json`.

The download in `index.html` points to the signed and notarized v0.9.3 DMG. Update the versioned asset URL when publishing a new release.

Brand assets are derived from `Assets/TwiddleWordmark.svg`, `Assets/AppIcon.png`, and `Assets/KnobMetal.png` in this repository. The desktop scene uses an original CSS gradient; third-party marks and font provenance are listed in [asset sources](assets/SOURCES.md). The popover follows the native 240 × 216 layout, dial geometry, and filter-frequency curves. Drag, scroll, or use arrow keys (Shift for fine control); double-click or press 0 for bypass. The menu bar icon toggles the preview.

The first dial interaction or player click starts an original, locally synthesized eight-second music loop through a Web Audio low/high-pass filter. The player button pauses playback. The webpage does not access other apps or their audio. Geist and all assets are self-hosted.
