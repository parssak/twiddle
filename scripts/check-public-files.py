#!/usr/bin/env python3
"""Reject private release artifacts and personal paths before publication."""
import pathlib
import re
import subprocess
import sys

PRIVATE_SUFFIXES = {".key", ".p8", ".p12", ".pfx", ".pem", ".cer", ".certsigningrequest", ".keychain", ".keychain-db"}
PRIVATE_NAMES = {"release-keychain-password", "release-keychain-path", "keychain-password"}
PERSONAL_PATH = re.compile(rb"/(?:Users|home)/[A-Za-z][^/\s<>\"']+")

paths = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"])
findings = []
for name in sorted(set(paths.decode().strip("\0").split("\0"))):
    path = pathlib.Path(name)
    if not path.is_file():
        continue
    lower = path.name.lower()
    private = (path.suffix.lower() in PRIVATE_SUFFIXES
               or lower in PRIVATE_NAMES
               or lower.startswith("operator") and lower.endswith(".md")
               or lower.startswith(".env") and lower != ".env.example"
               or "releasesigning" in [part.lower() for part in path.parts]
               or lower.startswith("sparkle-ed25519") and "private-key" in lower)
    if private:
        findings.append((name, "private release artifact"))
    if path.stat().st_size <= 1_000_000:
        data = path.read_bytes()
        if b"\0" not in data and PERSONAL_PATH.search(data):
            findings.append((name, "personal filesystem path"))
for name, reason in findings:
    print(f"{name}: {reason}", file=sys.stderr)
if findings:
    sys.exit(1)
print("Public file checks passed: no private release artifacts or personal paths.")
