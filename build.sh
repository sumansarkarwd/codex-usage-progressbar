#!/usr/bin/env bash
# Build CodexUsageBar.app from Sources/main.swift - no Xcode project required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/CodexUsageBar.app"
MACOS="$APP/Contents/MacOS"
BIN="$MACOS/CodexUsageBar"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx13.0"

echo "-> Cleaning previous bundle"
rm -rf "$APP"
mkdir -p "$MACOS"

echo "-> Compiling ($TARGET)"
swiftc \
  -O \
  -parse-as-library \
  -target "$TARGET" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$BIN" \
  "$ROOT/Sources/main.swift"

echo "-> Assembling bundle"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc codesign so it runs without Gatekeeper griping locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
