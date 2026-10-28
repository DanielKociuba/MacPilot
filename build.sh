#!/bin/bash
# Builds MacPilot.app into ./build. Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacPilot"

APP="build/MacPilot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacPilot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"   # ad-hoc signature, fine for personal use

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/MacPilot.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/MacPilot.app"
else
    echo "Built $APP  (run: open $APP)"
fi
