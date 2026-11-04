#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/nac-model-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path /private/tmp/nac-swift-module-cache \
  "$ROOT/app/Sources/NACProtocol/"*.swift \
  "$ROOT/app/Sources/NACService.swift" "$ROOT/app/Sources/HeartbeatProbe.swift" \
  "$ROOT/app/Sources/NACModel.swift" "$ROOT/app/Sources/LocalDeviceInformation.swift" "$ROOT/app/Checks/NACModelCheck.swift" -o "$CHECK_DIR/check"
"$CHECK_DIR/check"
