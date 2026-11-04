#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/nac-protocol-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
for check in "$SCRIPT_DIR"/Checks/*Check.swift; do
    case "$(basename "$check")" in NACModelCheck.swift|ServicePreflightCheck.swift|HeartbeatTransportCheck.swift|HeartbeatDiagnosticCheck.swift|AccountPolicyDiagnosticCheck.swift) continue ;; esac
    check_name="$(basename "$check" .swift)"
    xcrun swiftc -parse-as-library \
        -module-cache-path /private/tmp/nac-swift-module-cache \
        "$SCRIPT_DIR"/Sources/NACProtocol/*.swift "$check" -o "$CHECK_DIR/$check_name"
    "$CHECK_DIR/$check_name"
done
