# CLAUDE.md — claude-usage-widget

KDE Plasma 6 (Plasma 6.6, Qt6/KF6) panel widget showing Claude session usage +
reset timer. Built for Craig's Fedora 43 / KDE Wayland workstation.

## Working on this

- Source of truth is this project. `package/` is **symlinked** into
  `~/.local/share/plasma/plasmoids/com.cbo.claudeusage`. The helper now lives
  **inside** the package at `contents/code/claude-usage.py` (resolved at runtime
  via `Qt.resolvedUrl`), so there's no separate `~/.local/bin` install. Run
  `./install.sh` to (re)create the symlink, clear the QML cache, and restart
  plasmashell. Build a distributable with `kpackagetool6 --type Plasma/Applet
  --package package -o dist/claude-usage.plasmoid`.
- **Always clear `~/.cache/plasmashell/qmlcache/` after editing `main.qml`** —
  Plasma runs the *compiled* cache, not your source, so a plain restart shows no
  change. This is the single biggest footgun here. `install.sh` handles it.
- Validate QML offscreen without disturbing the live panel:
  `plasmoidviewer -a com.cbo.claudeusage` (needs the `plasma-sdk` package).
  `plasmoidviewer -f vertical -a com.cbo.claudeusage` renders the in-panel form.

## Data source

- Endpoint: `https://api.anthropic.com/api/oauth/usage` (same as Claude Code's
  `/usage`). Auth: `Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20`.
- Token comes from `~/.claude/.credentials.json` -> `claudeAiOauth.accessToken`
  (override the path with `CLAUDE_CREDENTIALS`).
- `five_hour` / `seven_day` give `{utilization, resets_at}` for the headline.
  Per-model weekly caps come from the **`limits` array** (`kind`, `group`,
  `percent`, `resets_at`, `scope.model.display_name`, `is_active`) — the legacy
  `seven_day_opus` / `seven_day_sonnet` fields return `null` now, so don't rely
  on them. The helper pre-converts every `resets_at` to epoch ms (`resets_ms`)
  so the QML never parses dates, and stamps `fetched_ms` on every emit.
- No standalone OAuth refresh — relies on Claude Code keeping the token fresh.

## Conventions

- Panel text: utilization `%` above, minutes-only countdown below (no seconds).
- Colour thresholds: >=90 negative (red), >=70 neutral (orange), else positive.
- Poll every 60s; internal clock ticks every 15s (minute-resolution display).
- Manual refresh: popup button, middle-click on the panel entry, and the
  right-click contextual action all call `root.refresh()`. It appends
  `" # <seq>"` to the command so each run is a *distinct* DataSource source —
  without that, reconnecting the same source name is a no-op and the forced
  refresh silently does nothing. **`seq` wraps at 8 — never make it unbounded.**
  Plasma5Support keeps source names in a `QQmlPropertyMap` backed by an
  append-only `QQmlOpenMetaObject`, and rebuilds the entire metaobject on every
  connect *and* disconnect, so an unbounded counter makes each poll cost
  O(polls so far). The 3 s siblings (`cpu-widget`, `memory-widget`) pinned
  plasmashell's main thread at 100% this way after a day of uptime; at 60 s this
  one is slower to bite but grows exactly the same. 8 names means one is reused
  only after 8 minutes.
