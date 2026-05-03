#!/usr/bin/env bash
# Build Slayout.app and package it as a zip for distribution to other Macs.
# Uses `ditto` (not `zip`) to preserve extended attributes and the code signature.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Slayout.app/Contents/Info.plist 2>/dev/null || echo "dev")
ZIP="Slayout-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent Slayout.app "$ZIP"

SIZE=$(du -h "$ZIP" | cut -f1)
echo "==> packaged $ZIP ($SIZE)"
echo
echo "To install on another Mac:"
echo "  1. Transfer $ZIP (AirDrop, scp, cloud storage, GitHub release...)"
echo "  2. unzip $ZIP -d /Applications/"
echo "     (or double-click the zip, then drag Slayout.app to /Applications/)"
echo "  3. Right-click /Applications/Slayout.app \xe2\x86\x92 Open the FIRST time"
echo "     (Gatekeeper bypass for ad-hoc-signed apps)"
echo "  4. Grant Accessibility + Input Monitoring (see README.md)"
