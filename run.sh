#!/usr/bin/env bash
# Build and launch CodexUsageBar.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/build.sh"
# Kill any running instance, then relaunch.
pkill -x CodexUsageBar >/dev/null 2>&1 || true
open "$ROOT/CodexUsageBar.app"
echo "Launched - look at the right side of your macOS menu bar for the ring."
