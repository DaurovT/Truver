#!/usr/bin/env bash
# Builds the Swift core (TruverCore → TruverBridge) for the Flutter app and copies it next to the app.
#   tool/build_core.sh android          arm64-v8a + x86_64 (emulator), release, static Swift runtime
#   tool/build_core.sh android debug    same, debug build (faster to compile, slower DSP)
#   tool/build_core.sh macos            libTruverBridge.dylib for the macOS dev runner (no audio yet)
# Needs: the swift.org toolchain matching the Swift SDK for Android (see DEVELOPMENT.md «Android и Windows»),
# ANDROID_HOME (defaults to ~/Library/Android/sdk).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
core="$here/../TruverCore"
config="${2:-release}"
android_home="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ndk="$(ls -d "$android_home"/ndk/* | sort -V | tail -1)"
llvm="$ndk/toolchains/llvm/prebuilt/darwin-x86_64"
scratch="${TRUVER_CORE_BUILD:-$here/build/core}"
export TOOLCHAINS="${TOOLCHAINS:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$HOME/Library/Developer/Toolchains/swift-6.4.3-RELEASE.xctoolchain/Info.plist")}"

case "${1:-android}" in
android)
  for pair in "aarch64:arm64-v8a:aarch64-linux-android" "x86_64:x86_64:x86_64-linux-android"; do
    IFS=: read -r arch abi ndkTriple <<<"$pair"
    out="$scratch/android-$arch"
    xcrun swift build -c "$config" --package-path "$core" --swift-sdk "$arch-unknown-linux-android28" \
      --static-swift-stdlib --scratch-path "$out" --product TruverBridge
    dest="$here/android/app/src/main/jniLibs/$abi"
    mkdir -p "$dest"
    if [ "$config" = release ]; then
      "$llvm/bin/llvm-strip" --strip-unneeded -o "$dest/libTruverBridge.so" "$out/$config/libTruverBridge.so"
    else
      cp "$out/$config/libTruverBridge.so" "$dest/"
    fi
    cp "$llvm/sysroot/usr/lib/$ndkTriple/libc++_shared.so" "$dest/"
    echo "→ $dest ($(du -h "$dest/libTruverBridge.so" | cut -f1))"
  done
  ;;
macos)
  out="$scratch/macos"
  xcrun swift build -c "$config" --package-path "$core" --scratch-path "$out" --product TruverBridge
  mkdir -p "$here/macos/Frameworks"
  cp "$out/$config/libTruverBridge.dylib" "$here/macos/Frameworks/"
  echo "→ $here/macos/Frameworks/libTruverBridge.dylib"
  ;;
*) echo "usage: $0 android|macos [release|debug]"; exit 1 ;;
esac
