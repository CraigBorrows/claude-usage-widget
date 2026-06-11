# Claude Usage — KDE Plasma 6 widget

A panel widget for KDE Plasma 6 that shows your current Claude session usage
and the reset timer, sourced from the **same official endpoint Claude Code's
`/usage` uses** (`https://api.anthropic.com/api/oauth/usage`).

- **In the panel:** session utilization `%` on top, time-to-reset (minutes) below,
  colour-coded green → orange → red at 70% / 90%.
- **Click → popup:** current 5-hour session plus **weekly limits** (all models,
  Opus, Sonnet) with bars and reset times.

## Layout

```
package/                       # the plasmoid (symlinked into Plasma's dir)
  metadata.json                # id com.cbo.claudeusage, version, icon
  contents/ui/main.qml         # UI + logic
bin/claude-usage-json          # Python helper: reads OAuth token, calls the
                               # usage endpoint, emits normalised JSON
install.sh                     # symlink install + cache clear + restart
```

## Install / refresh

```sh
./install.sh
```

This symlinks `package/` to `~/.local/share/plasma/plasmoids/com.cbo.claudeusage`
and `bin/claude-usage-json` to `~/.local/bin/`, so **editing files here edits the
live widget**. Add it to a panel via right-click → *Add Widgets* → "Claude Usage".

## How it gets the data

`bin/claude-usage-json` reads the OAuth access token from
`~/.claude/.credentials.json` and calls the usage endpoint. Claude Code keeps
that token fresh in normal use; if it expires (no Claude usage for a long
stretch) the call 401s and the widget shows "Sign in to Claude" until you next
run Claude Code. Standalone OAuth refresh is **not** implemented.

## Gotcha: the QML cache

Plasma serves a **compiled** copy of the QML from
`~/.cache/plasmashell/qmlcache/`. A plain plasmashell restart replays the cached
build, so source edits won't appear until that cache is cleared. `install.sh`
does this for you; if editing by hand, `rm -rf ~/.cache/plasmashell/qmlcache`
then restart plasmashell.
