#!/usr/bin/env bash
# Build Slayout.app: a real LSUIElement bundle, ad-hoc signed.
# Permissions (Accessibility + Input Monitoring) attach to the bundle's
# signature, so they survive rebuilds (as long as you re-run this script
# after each `swift build`).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="Slayout.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/Slayout"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Build output not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/Slayout"

if [[ ! -f Resources/Slayout.icns ]]; then
    echo "==> rendering icon (Resources/Slayout.icns missing)"
    swift scripts/render-icon.swift
fi
cp Resources/Slayout.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenubarIcon.png "$APP/Contents/Resources/MenubarIcon.png"
cp Resources/MenubarIcon@2x.png "$APP/Contents/Resources/MenubarIcon@2x.png"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Slayout</string>
    <key>CFBundleIdentifier</key><string>com.awhogue.slayout</string>
    <key>CFBundleName</key><string>Slayout</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo "==> done. To install:"
echo "    rm -rf /Applications/Slayout.app && mv Slayout.app /Applications/ && open /Applications/Slayout.app"
