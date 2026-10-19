#!/bin/bash
# Builds "Orbit.app"
#   ./build.sh           → build/Orbit.app
#   ./build.sh install   → also copies it to ~/Applications
#   ./build.sh release   → Universal (Apple Silicon + Intel) build zipped to build/Orbit.zip
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "release" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ClaudeSchedule"
else
    swift build -c release
    BIN=.build/release/ClaudeSchedule
fi

# App icon (regenerated when the source image changes)
if [ ! -f Resources/AppIcon.icns ] || [ Resources/icon-source.jpeg -nt Resources/AppIcon.icns ]; then
    tmp=$(mktemp -d)
    swift scripts/make_icon.swift Resources/icon-source.jpeg "$tmp/icon.png"
    mkdir "$tmp/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
    rm -rf "$tmp"
fi

APP="build/Orbit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Orbit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/rocket.png "$APP/Contents/Resources/rocket.png"
cp Resources/art/*.png "$APP/Contents/Resources/"
# Art you may not redistribute stays out of release builds (Resources/art-local is git-ignored)
if [ "${1:-}" != "release" ] && ls Resources/art-local/*.png >/dev/null 2>&1; then
    cp Resources/art-local/*.png "$APP/Contents/Resources/"
fi
if [ -f Resources/Supabase.plist ]; then
    cp Resources/Supabase.plist "$APP/Contents/Resources/Supabase.plist"
else
    echo "ℹ️  No Resources/Supabase.plist — the Friends feature will be disabled (see README)."
fi
codesign --force --sign - "$APP" >/dev/null

echo "✅ Built: $APP"

if [ "${1:-}" = "release" ]; then
    rm -f build/Orbit.zip
    ditto -c -k --keepParent "$APP" build/Orbit.zip
    echo "✅ Release zip: build/Orbit.zip ($(du -h build/Orbit.zip | cut -f1))"
fi

if [ "${1:-}" = "install" ]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Orbit.app
    cp -R "$APP" ~/Applications/
    echo "✅ Installed: ~/Applications/Orbit.app"
fi
