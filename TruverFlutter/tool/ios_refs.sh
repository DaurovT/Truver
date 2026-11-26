#!/usr/bin/env bash
# Captures iOS reference screenshots from the simulator for the states in test/reference/ios/states.txt.
#   tool/ios_refs.sh            all states        tool/ios_refs.sh tuner_   only names starting with tuner_
# One simulator for everyone: run it alone. Each launch waits 8 s (first frames can be black).
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
SIM="${TRUVER_SIM:-5552CC6A-1A11-42D8-8263-64FA4376990F}"
base="-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio"
filter="${1:-}"
grep -v '^#' "$here/test/reference/ios/states.txt" | while IFS='|' read -r name args; do
  name="$(echo "$name" | xargs)"; args="$(echo "$args" | xargs)"
  [ -z "$name" ] && continue
  [[ -n "$filter" && "$name" != $filter* ]] && continue
  xcrun simctl terminate "$SIM" app.truver.ios >/dev/null 2>&1
  # shellcheck disable=SC2086
  xcrun simctl launch "$SIM" app.truver.ios $base $args >/dev/null
  sleep 8
  xcrun simctl io "$SIM" screenshot "$here/test/reference/ios/$name.png" >/dev/null 2>&1 && echo "✓ $name"
done
xcrun simctl terminate "$SIM" app.truver.ios >/dev/null 2>&1
