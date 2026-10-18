#!/bin/bash
# Builds "Orbit.app"
#   ./build.sh           → build/Orbit.app
#   ./build.sh install   → also copies it to ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

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
cp .build/release/ClaudeSchedule "$APP/Contents/MacOS/Orbit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ -f Resources/Supabase.plist ]; then
    cp Resources/Supabase.plist "$APP/Contents/Resources/Supabase.plist"
else
    echo "ℹ️  No Resources/Supabase.plist — the Friends feature will be disabled (see README)."
fi
codesign --force --sign - "$APP" >/dev/null

echo "✅ Built: $APP"

if [ "${1:-}" = "install" ]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Orbit.app
    cp -R "$APP" ~/Applications/
    echo "✅ Installed: ~/Applications/Orbit.app"
fi
