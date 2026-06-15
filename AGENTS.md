# AGENTS.md

Guidance for Codex when working in this repository.

## What this is

Codex Usage Bar is a native macOS menu-bar app built with SwiftUI
`MenuBarExtra`. It shows Codex usage as a ring plus percentage in the top panel,
and a small dropdown with rate limits and token totals. It is intentionally
single-file and dependency-free: `swiftc` builds `Sources/main.swift` directly.

## Data source

The app reads local Codex session logs from:

```text
~/.codex/sessions/**/*.jsonl
```

Each `event_msg` with payload type `token_count` contains:

- `info.last_token_usage`: per-turn token usage
- `info.total_token_usage`: cumulative session usage
- `rate_limits.primary`: current Codex usage window, usually 5 hours
- `rate_limits.secondary`: weekly window
- `plan_type`: displayed in the dropdown when present

Do not estimate percentages from guessed token budgets. Use the `rate_limits`
fields logged by Codex when they exist. Token totals are local-log sums of
`last_token_usage`.

## UI / scope

- Menu bar: ring filled to current-session percent plus a percentage label.
- Dropdown: current session, current week, token grid, per-model totals, Refresh,
  and Quit.
- Token windows: current session, Today, and All.
- Token rows: input, cached input, output, reasoning, and total.
- Ring/bar color: green <50, yellow <70, orange <90, red >=90.

## Architecture

Everything lives in `Sources/main.swift`.

- `Limit`, `TokenTotals`, `ModelUsage`, `UsageBreakdown`, `Usage`: value models.
- `UsageSource`: JSONL discovery, JSON parsing, rate-limit extraction, token sums.
- `UsageMonitor`: refresh timer and published state.
- `makeRingImage`, `PercentRow`, `TokenGrid`, `PopoverView`: menu-bar and popover UI.
- `CodexUsageBarApp`: `@main` `MenuBarExtra` scene.

Keep the app single-file unless there is a strong reason not to. Avoid adding a
Swift Package or Xcode project for small changes.

## Build / run

```bash
./build.sh
./run.sh
```

`build.sh` creates `CodexUsageBar.app` and ad-hoc signs it. `run.sh` builds,
kills a running `CodexUsageBar`, and relaunches it.

Gotchas:

- `-parse-as-library` is required because `main.swift` uses `@main`.
- Target macOS 13 or newer; `MenuBarExtra` requires Ventura.
- `LSUIElement` keeps the app out of the Dock.
