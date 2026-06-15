# Codex Usage Bar

A tiny native **macOS menu-bar app** that shows Codex usage as a **ring +
percentage** in the top panel. Auto-refreshes every 5 minutes.

The ring + percentage live in your menu bar. Click it for:

- **Current session** usage from Codex's logged 5-hour rate-limit window
- **Current week** usage from Codex's logged weekly rate-limit window
- **Token totals** from local Codex session logs
- **By model** token totals when the session log identifies a model

No extra service, keychain access, or API call is required. The app only reads
local files under `~/.codex/sessions`.

---

## How it works

Codex writes session JSONL files in:

```text
~/.codex/sessions/**/*.jsonl
```

The app reads `event_msg` entries whose payload type is `token_count`.

- Percentages come from logged `rate_limits.primary` and `rate_limits.secondary`.
- Token totals come from `info.last_token_usage`.
- The current-session token window is based on the primary rate-limit reset time
  and window length when present, otherwise a rolling 5 hours.
- The Today window starts at local midnight.

---

## Requirements

- macOS 13 (Ventura) or newer
- Codex installed and used at least once so `~/.codex/sessions` has logs
- Swift toolchain (Xcode Command Line Tools) to build:

```bash
xcode-select --install
```

---

## Build And Run

```bash
./run.sh
```

`run.sh` builds `CodexUsageBar.app`, relaunches it, and the ring appears on the
right side of the macOS menu bar.

To build without launching:

```bash
./build.sh
```

To install it permanently:

```bash
cp -R CodexUsageBar.app /Applications/
```

### Launch At Login

System Settings -> General -> Login Items -> "+" -> pick `CodexUsageBar.app`.

---

## Using It

| Element             | Meaning                                           |
|---------------------|---------------------------------------------------|
| **Menu-bar ring**   | Current session usage. Green -> red.              |
| **Menu-bar number** | Same value as a percentage.                       |
| **Dropdown**        | Session/week percentages, reset times, token grid.|
| **Tokens grid**     | Input/cached/output/reasoning for 5h/Today/All.   |
| **By model**        | Total tokens per model for the same windows.      |
| **Refresh**         | Force an immediate update.                        |
| **Quit**            | Exit the app.                                     |

Colors: green <50%, yellow <70%, orange <90%, red >=90%.

---

## Project Layout

```text
Sources/main.swift   # the entire app
Info.plist           # bundle metadata, LSUIElement menu-bar mode
build.sh             # swiftc -> CodexUsageBar.app
run.sh               # build + relaunch
AGENTS.md            # contributor notes for Codex
```

Single file, no dependencies, built straight with `swiftc`.

---

## Troubleshooting

- **No token-count events found yet**: run Codex through at least one interaction
  that emits usage logs, then Refresh.
- **A percentage row shows "-"**: the latest local logs did not include that
  rate-limit field yet.
- **Do not see it in the menu bar**: the bar may be full; the app has no Dock
  icon by design. Check `CodexUsageBar` in Activity Monitor.
- **Build fails**: ensure `swiftc --version` works and you are on macOS 13+.
