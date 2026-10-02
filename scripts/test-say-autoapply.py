#!/usr/bin/env python3
"""Live acceptance check against a running, audio-enabled Twiddle app."""

import json
import math
import subprocess
import tempfile
import time
from pathlib import Path


def status():
    return json.loads(subprocess.check_output(["twiddle", "status"], text=True))


before = status()
assert before["running"] and before["audioError"] is None, "Twiddle must be capturing audio"
assert not before["autoApplyActive"], "Stop other Auto-apply triggers before this check"
assert not before["automationSuppressed"], "Release manual suppression before this check"
assert not math.isclose(before["preset"], before["baseline"], abs_tol=0.01), "Choose a distinct preset"

speech = subprocess.Popen([
    "/usr/bin/say", "-r", "150",
    "Twiddle should automatically apply its saved amount while this sentence is spoken, then restore the previous amount when the speech finishes.",
])
activated = False
try:
    while speech.poll() is None:
        current = status()
        assert current["audioError"] is None, "Audio capture failed during speech"
        activated |= current["autoApplyActive"] and math.isclose(
            current["target"], before["preset"], abs_tol=0.001
        )
        time.sleep(0.1)
finally:
    speech.wait()
assert activated, "say spoke, but Auto-apply never reached the saved preset"

deadline = time.monotonic() + 3
while time.monotonic() < deadline:
    after = status()
    if not after["autoApplyActive"] and math.isclose(after["value"], before["baseline"], abs_tol=0.001):
        break
    time.sleep(0.1)
else:
    raise AssertionError("Auto-apply did not restore the baseline after speech")

# Generating a speech file has no audible output and must not trigger filtering.
with tempfile.TemporaryDirectory(prefix="twiddle-speech-test-") as directory:
    render = subprocess.Popen([
        "/usr/bin/say", "-o", str(Path(directory) / "speech.aiff"),
        "This speech is written to a file and should not activate automatic filtering.",
    ])
    try:
        while render.poll() is None:
            assert not status()["autoApplyActive"], "File-only speech activated Auto-apply"
            time.sleep(0.1)
    finally:
        assert render.wait() == 0, "Speech file generation failed"

after = status()
assert after["triggerApps"] == before["triggerApps"], "Trigger app selection changed"
assert after["targetApps"] == before["targetApps"], "Filtered app selection changed"
assert math.isclose(after["preset"], before["preset"]), "Saved preset changed"
print("PASS: say applies the preset, restores the baseline, and ignores file-only speech")
