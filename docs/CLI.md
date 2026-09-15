# Twiddle CLI

The CLI controls a running Twiddle app. Commands return one JSON object on stdout, making them suitable for scripts and agents. Available in Twiddle v0.3 and later.

## Install

`bash install.sh` installs the app and creates `~/.local/bin/twiddle`. Ensure `~/.local/bin` is on your PATH. For an app copied into Applications, create the link yourself:

```sh
mkdir -p ~/.local/bin
ln -s /Applications/Twiddle.app/Contents/MacOS/Twiddle ~/.local/bin/twiddle
```

The equivalent direct invocation is:

```sh
/Applications/Twiddle.app/Contents/MacOS/Twiddle --cli status
```

Launch Twiddle normally before using commands. Its usual audio permissions and Apps to Twiddle selection still apply.

## Commands

```sh
twiddle status
twiddle set -0.5       # Low-pass; values range from -1 to 1
twiddle set 0.5        # High-pass
twiddle set 0          # Bypass immediately
twiddle preset -0.7    # Save the Auto-apply amount
twiddle apply          # Apply that amount as the manual filter
twiddle reset          # Fade back to bypass
twiddle disco on
twiddle disco off
twiddle settings
twiddle help
```

`--json` is accepted for explicitness; output is always JSON except help. Invalid arguments exit with code 2. Connection or app errors exit with code 1. Successful commands exit with code 0.

`set`, `apply`, and `reset` override currently active automatic triggers until they all release, matching manual bypass behavior. `preset` persists the new amount and updates the filter immediately if Auto-apply is active. `disco on` also activates the Auto-apply trigger; `disco off` releases that trigger without interrupting another active trigger.

Responses include `ok`, the current interpolated `value`, destination `target`, manual `baseline`, saved `preset`, `autoApplyActive`, `automationSuppressed`, `disco`, `targetApps`, `triggerApps`, and `audioError`. `running` indicates whether audio processing is running, not whether the UI process exists. A command can succeed while processing is stopped; inspect `running` and `audioError` when you need to verify the audio state. Filter values are normalized knob positions, not frequencies in Hz.

The control channel is a Unix socket in the user's private macOS temporary directory. It accepts only connections from the same user, dispatches commands on the app's main thread, and opens no network port. Each connection carries one newline-delimited JSON request and response, with bounded input and a two-second socket timeout. Scripts should not automatically retry timed-out mutations because the app may already have applied them.
