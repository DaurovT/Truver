#!/usr/bin/env bash
# Regenerates the Android launcher icon (adaptive + monochrome + legacy) from the iOS icon geometry.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
# make_icon.swift writes the iOS icons into its first argument; send them to the temp dir.
sed '/^let out = /s/.*/let out = CommandLine.arguments[1]/' "$here/../Truver/Tools/make_icon.swift" > "$tmp/combined.swift"
sed '/^import AppKit$/d' "$here/tool/make_android_icon.swift" >> "$tmp/combined.swift"
swift "$tmp/combined.swift" "$tmp" "$here/android/app/src/main/res" | grep -v "^wrote"
mkdir -p "$here/android/app/src/main/res/mipmap-anydpi-v26"
cat > "$here/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
XML
rm -rf "$tmp"
