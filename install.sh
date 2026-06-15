#!/usr/bin/env bash
# Install CodexUsageBar.app to /Applications and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="CodexUsageBar.app"
APP_PATH="$ROOT/$APP_NAME"
TARGET="/Applications/$APP_NAME"

"$ROOT/build.sh"

pkill -x CodexUsageBar >/dev/null 2>&1 || true
rm -rf "$TARGET"
cp -R "$APP_PATH" "$TARGET"
chmod -R u+rwX,go+rX,go-w "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
open "$TARGET"

echo "Installed and launched: $TARGET"

