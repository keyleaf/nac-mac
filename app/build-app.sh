#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/local/NAC 小助手-0.11.2.app"
STAGE="$(mktemp -d "${TMPDIR:-/private/tmp}/nac-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/NAC 小助手.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
xcrun swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macosx15.0" \
  -module-cache-path /private/tmp/nac-swift-module-cache \
  "$ROOT/app/Sources/NACPreview.swift" \
  "$ROOT/app/Sources/NACService.swift" \
  "$ROOT/app/Sources/NACModel.swift" "$ROOT/app/Sources/PasswordStore.swift" "$ROOT/app/Sources/LocalDeviceInformation.swift" \
  "$ROOT/app/Sources/HeartbeatProbe.swift" \
  "$ROOT/app/Sources/NACProtocol/"*.swift \
  -framework SwiftUI -framework AppKit \
  -o "$BUNDLE/Contents/MacOS/NACHelper"
xcrun swift -module-cache-path /private/tmp/nac-swift-module-cache \
  "$ROOT/app/scripts/generate-icon.swift" "$STAGE/AppIcon.iconset"
iconutil -c icns "$STAGE/AppIcon.iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NACHelper</string>
<key>CFBundleIdentifier</key><string>io.github.keyleaf.nac-mac</string>
<key>CFBundleName</key><string>NAC 小助手</string>
<key>CFBundleDisplayName</key><string>NAC 小助手</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.11.2</string>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
plutil -lint "$BUNDLE/Contents/Info.plist"
codesign --force --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
if [[ -e "$OUTPUT" ]]; then
  echo "Output already exists; move it aside before rebuilding: $OUTPUT" >&2
  exit 1
fi
mkdir -p "$ROOT/local"
ditto "$BUNDLE" "$OUTPUT"
echo "Packaged: $OUTPUT"
