#!/bin/bash
# At most 3 heavy jobs (flutter test, xcodebuild, swift build, gradle) at once on this 8-core / 16 GB Mac.
#   Truver/Tools/heavy_slot.sh <command> [args…]
# Waits for a free slot, runs the command, frees the slot. Exit code is the command's.
set -u
SLOTS=${TRUVER_HEAVY_SLOTS:-3}
waited=0
while :; do
  for i in $(seq 1 "$SLOTS"); do
    LOCK=/tmp/truver-heavy-slot.$i
    if mkdir "$LOCK" 2>/dev/null; then
      date +%s > "$LOCK/since"; echo "$$ $*" > "$LOCK/owner"
      trap 'rm -rf "$LOCK"' EXIT
      "$@"
      exit $?
    fi
    # A holder that died leaves a stale slot: free it after 25 minutes or when its process is gone.
    pid=$(cut -d' ' -f1 "$LOCK/owner" 2>/dev/null)
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || \
       { [ -f "$LOCK/since" ] && [ $(( $(date +%s) - $(cat "$LOCK/since") )) -gt 1500 ]; }; then
      rm -rf "$LOCK"
    fi
  done
  [ $((waited % 60)) -eq 0 ] && echo "heavy_slot: all $SLOTS slots busy, waiting…"
  sleep 5; waited=$((waited + 5))
done
