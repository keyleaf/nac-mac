#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/nac-password-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library -module-cache-path /private/tmp/nac-swift-module-cache \
 "$ROOT/app/Sources/PasswordStore.swift" "$ROOT/app/Checks/PasswordStoreCheck.swift" -o "$CHECK_DIR/check"
"$CHECK_DIR/check"
