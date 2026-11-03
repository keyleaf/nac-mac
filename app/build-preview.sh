#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$APP_DIR/local/NAC Preview.app"
CONTENTS_DIR="$OUTPUT_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"
xcrun swiftc \
  -parse-as-library \
  -target "$(uname -m)-apple-macosx15.0" \
  -module-cache-path /private/tmp/nac-swift-module-cache \
  "$APP_DIR/app/Sources/NACPreview.swift" \
  "$APP_DIR/app/Sources/NACService.swift" \
  "$APP_DIR/app/Sources/HeartbeatProbe.swift" \
  "$APP_DIR/app/Sources/NACProtocol/"*.swift \
  -framework SwiftUI \
  -framework AppKit \
  -o "$MACOS_DIR/NACPreview"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NACPreview</string>
    <key>CFBundleIdentifier</key>
    <string>local.nac.preview</string>
    <key>CFBundleName</key>
    <string>NAC Preview</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.8</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Built: $OUTPUT_DIR"
