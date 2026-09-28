# Twiddle agent entrypoint

This repository is public. Do not commit credentials, private keys, local operator notes, personal paths, or private telemetry. Keep release credentials outside Git.

Read `docs/DEVELOPMENT.md` before changing the macOS app or publishing a release. `Info.plist` is the source of truth for the version and update feed. Do not infer release state from an old `build/` bundle, a mounted DMG, or `/Applications/Twiddle.app`.

For native issues, check high-level errors and `twiddle status` first, then inspect the relevant macOS logs and code.

## Build and release

- `bash build.sh` builds a local app and runs the native self-tests. `bash package.sh` makes a **locally signed** DMG. Neither is a public release.
- `bash scripts/release.sh` uses the dedicated release keychain, Developer ID signing, Apple notarization, stapling, and the Sparkle v2 key. `bash scripts/release.sh --resume` continues an interrupted notarization. Never replace or rotate a signing key just to get past a Keychain prompt.
- `bash scripts/verify-release.sh` checks the finished local DMG, its signature, installer assets, checksum, and appcast before upload. Keep the illustrated Finder layout in `Assets/DMG/.background.png` and `.DS_Store`; open the **final DMG** in Finder to check its actual size and appearance.
- Install and test the app from the exact candidate DMG. Confirm Spotify low-pass and high-pass are audible, `audioCallbacks` advance, `inputPeak` responds, and the output device is correct. Test fresh permission grant and an upgrade from the previous public version, including output changes and sleep/wake. Self-tests and a green permission indicator do not prove live capture works. If a UI or permission check cannot be performed, report it as unverified; do not call the audio fix complete.
- Publish the GitHub release only after these checks. Verify the public asset's SHA-256 against the local DMG. Then change website download links, deploy `site/`, and verify `twiddle.fun`, `appcast-v2.xml`, and the old `appcast.xml`. Never make the website point to an asset that is not public yet. Use Chrome for visual website checks.

## Signing and updates

The signing scripts locate credentials on the release host and require private key backups with restricted permissions. Keep an encrypted backup outside that host and verify that it can be restored. A local keychain or a second file on the same Mac does not provide disaster recovery. Check any private operator notes on the release host; never copy their contents into this repository or public logs.

Twiddle 0.9.1 changed the Developer ID identity and Sparkle signing key. `site/appcast.xml` remains for older installations; 0.9 and earlier need one manual download of 0.9.1, after which `appcast-v2.xml` is the feed. Do not delete the old feed or change `SUPublicEDKey` casually. A signing identity change can invalidate the macOS Screen & System Audio Recording grant, so test permission migration on the installed public app.
