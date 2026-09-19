#!/bin/bash
set -euo pipefail

pending=${1:?Usage: bash scripts/notarize-dmg.sh PENDING_DMG OUTPUT_DMG KEYCHAIN_PROFILE}
output=${2:?Usage: bash scripts/notarize-dmg.sh PENDING_DMG OUTPUT_DMG KEYCHAIN_PROFILE}
profile=${3:?Usage: bash scripts/notarize-dmg.sh PENDING_DMG OUTPUT_DMG KEYCHAIN_PROFILE}
[[ -f "$pending" ]] || { echo "Pending DMG not found: $pending" >&2; exit 1; }

submission="${output%.dmg}.notary-submission.json"
result="$output.notary.json"
if [[ -f "$submission" ]]; then
    submission_id=$(/usr/bin/python3 - "$submission" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("id", ""))
PY
    )
    [[ -n "$submission_id" ]] || { echo "Invalid notarization state: $submission" >&2; exit 1; }
    echo "Resuming Apple notarization submission $submission_id"
else
    submission_tmp="$submission.tmp"
    xcrun notarytool submit "$pending" --keychain-profile "$profile" \
        --output-format json > "$submission_tmp"
    submission_id=$(/usr/bin/python3 - "$submission_tmp" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("id", ""))
PY
    )
    [[ -n "$submission_id" ]] || { echo "Apple did not return a notarization submission ID." >&2; exit 1; }
    mv "$submission_tmp" "$submission"
    echo "Submitted Apple notarization request $submission_id"
fi

result_tmp="$result.tmp"
xcrun notarytool wait "$submission_id" --keychain-profile "$profile" \
    --timeout "${TWIDDLE_NOTARY_TIMEOUT:-15m}" --output-format json > "$result_tmp"
mv "$result_tmp" "$result"
/usr/bin/python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    submission = json.load(f)
if submission.get("status") != "Accepted":
    sys.exit("Notarization not accepted; inspect " + sys.argv[1])
PY

xcrun stapler staple "$pending"
xcrun stapler validate "$pending"
spctl --assess --type open --context context:primary-signature "$pending"
mv "$pending" "$output"
rm -f "$submission"
