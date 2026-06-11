# CLAUDE.md — claude-usage-widget

KDE Plasma 6 (Plasma 6.6, Qt6/KF6) panel widget showing Claude session usage +
reset timer. Built for Craig's Fedora 43 / KDE Wayland workstation.

## Working on this

- Source of truth is this project. `package/` is **symlinked** into
  `~/.local/share/plasma/plasmoids/com.cbo.claudeusage`, and
  `bin/claude-usage-json` into `~/.local/bin/`. Run `./install.sh` to (re)create
  the symlinks, clear the QML cache, and restart plasmashell.
- **Always clear `~/.cache/plasmashell/qmlcache/` after editing `main.qml`** —
  Plasma runs the *compiled* cache, not your source, so a plain restart shows no
  change. This is the single biggest footgun here. `install.sh` handles it.
- Validate QML offscreen without disturbing the live panel:
  `plasmoidviewer -a com.cbo.claudeusage` (needs the `plasma-sdk` package).
  `plasmoidviewer -f vertical -a com.cbo.claudeusage` renders the in-panel form.

## Data source

- Endpoint: `https://api.anthropic.com/api/oauth/usage` (same as Claude Code's
  `/usage`). Auth: `Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20`.
- Token comes from `~/.claude/.credentials.json` -> `claudeAiOauth.accessToken`.
- Response fields used: `five_hour`, `seven_day`, `seven_day_opus`,
  `seven_day_sonnet`, each `{utilization, resets_at}`. The helper pre-converts
  `resets_at` to epoch ms (`resets_ms`) so the QML never parses dates.
- No standalone OAuth refresh — relies on Claude Code keeping the token fresh.

## Conventions

- Panel text: utilization `%` above, minutes-only countdown below (no seconds).
- Colour thresholds: >=90 negative (red), >=70 neutral (orange), else positive.
- Poll every 60s; internal clock ticks every 15s (minute-resolution display).
