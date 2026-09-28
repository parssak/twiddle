# Twiddle agent entrypoint

Read `docs/DEVELOPMENT.md` before changing the macOS app or publishing a release. `Info.plist` is the source of truth for the version and update feed. Do not infer release state from an old `build/` bundle, a mounted DMG, or `/Applications/Twiddle.app`.

For issues, check high-level errors and `twiddle status` first, then inspect the relevant macOS logs and code. If connected telemetry is relevant, use Axiom MCP rather than Bogi MCP.

## Build and release

- `bash build.sh` builds a local app and runs the native self-tests. `bash package.sh` makes a **locally signed** DMG. Neither is a public release.
- `bash scripts/release.sh` uses the dedicated release keychain, Developer ID signing, Apple notarization, stapling, and the Sparkle v2 key. `bash scripts/release.sh --resume` continues an interrupted notarization. Never replace or rotate a signing key just to get past a Keychain prompt.
- `bash scripts/verify-release.sh` checks the finished local DMG, its signature, installer assets, checksum, and appcast before upload. Keep the illustrated Finder layout in `Assets/DMG/.background.png` and `.DS_Store`; open the **final DMG** in Finder to check its actual size and appearance.
- Install and test the app from the exact candidate DMG. Confirm Spotify low-pass and high-pass are audible, `audioCallbacks` advance, `inputPeak` responds, and the output device is correct. Test fresh permission grant and an upgrade from the previous public version, including output changes and sleep/wake. Self-tests and a green permission indicator do not prove live capture works. If a UI or permission check cannot be performed, report it as unverified; do not call the audio fix complete.
- Publish the GitHub release only after these checks. Verify the public asset's SHA-256 against the local DMG. Then change website download links, deploy `site/`, and verify `twiddle.fun`, `appcast-v2.xml`, and the old `appcast.xml`. Never make the website point to an asset that is not public yet. Use Chrome for visual website checks.

## Signing state and recovery

The public identity is Developer ID Application, Team `3B8S7SSNL8`. The release keychain is `~/Library/Keychains/twiddle-release-2026.keychain-db`. Its password file, Developer ID private key and certificate, and Sparkle EdDSA private-key backup are in `~/Library/Application Support/Twiddle/ReleaseSigning/`. `scripts/release.sh` checks that the key files exist and have mode 600. None of these secrets belong in Git, logs, or a website.

**The copies on this Mac are not an independent backup.** Before depending on this release setup long term, make and verify an encrypted backup outside this Mac of the Developer ID private key and certificate, Sparkle private key, and release keychain password. Preserve access to the Apple notarization credentials too. `scripts/setup-release-keychain.sh` can reconstruct the dedicated keychain from the key and certificate backups; it does not recover lost private keys.

Twiddle 0.9.1 changed both the Developer ID identity and Sparkle signing key after the old private keys were lost. `site/appcast.xml` remains for older installations; 0.9 and earlier need one manual download of 0.9.1, after which `appcast-v2.xml` is the feed. Do not delete the old feed or change `SUPublicEDKey` casually. A signing identity change can invalidate the macOS Screen & System Audio Recording grant, so test permission migration on the installed public app.
