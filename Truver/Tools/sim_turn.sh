#!/bin/bash
# One iOS simulator at a time on this Mac (16 GB can't hold six booted simulators).
#   Truver/Tools/sim_turn.sh <UDID> <script.sh>
# Waits for the turn (a lock directory), boots the simulator, runs <script.sh> (install, launch, screenshots —
# everything that needs the simulator, as ONE batch), shuts the simulator down and releases the turn.
# Build the app BEFORE taking the turn; never hold it while compiling or running flutter tests.
set -u
UDID="$1"; SCRIPT="$2"
LOCK=/tmp/truver-sim-turn.lock
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  # A holder that died leaves a stale lock: free it after 15 minutes.
  # (a holder writes `since` right after mkdir: an empty value means «just taken», not stale)
  since=$(cat "$LOCK/since" 2>/dev/null || true)
  if [ -n "$since" ] && [ $(( $(date +%s) - since )) -gt 900 ]; then
    echo "sim_turn: stale lock from $(cat "$LOCK/owner" 2>/dev/null), removing"; rm -rf "$LOCK"; continue
  fi
  [ $((waited % 60)) -eq 0 ] && echo "sim_turn: waiting for the simulator turn (held by $(cat "$LOCK/owner" 2>/dev/null))…"
  sleep 5; waited=$((waited + 5))
done
date +%s > "$LOCK/since"; echo "$UDID" > "$LOCK/owner"
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; rm -rf "$LOCK"' EXIT
xcrun simctl boot "$UDID" >/dev/null 2>&1
xcrun simctl bootstatus "$UDID" >/dev/null 2>&1
bash "$SCRIPT"
