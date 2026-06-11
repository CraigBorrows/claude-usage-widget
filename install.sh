#!/usr/bin/env bash
# Install / refresh the Claude Usage plasmoid from this project.
# Symlinks the package into Plasma's plasmoid dir and the helper into
# ~/.local/bin, clears the compiled QML cache, and restarts plasmashell so
# edits to package/ actually show up.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/com.cbo.claudeusage"
BIN_LINK="$HOME/.local/bin/claude-usage-json"

mkdir -p "$(dirname "$PLASMOID_DIR")" "$HOME/.local/bin"

# package/ -> plasmoids/com.cbo.claudeusage  (live = source)
rm -rf "$PLASMOID_DIR"
ln -s "$HERE/package" "$PLASMOID_DIR"

# helper -> ~/.local/bin  (main.qml calls this absolute path)
ln -sf "$HERE/bin/claude-usage-json" "$BIN_LINK"
chmod +x "$HERE/bin/claude-usage-json"

# Plasma caches *compiled* QML; without this, source edits won't load.
rm -rf "$HOME/.cache/plasmashell/qmlcache"

# Restart the shell to pick everything up.
if systemctl --user list-units --type=service 2>/dev/null | grep -q plasma-plasmashell; then
    systemctl --user restart plasma-plasmashell.service
else
    kquitapp6 plasmashell 2>/dev/null || true
    sleep 1
    (kstart plasmashell >/dev/null 2>&1 &)
fi

echo "Installed via symlink. Live install -> $HERE/package"
echo "If it's not on a panel yet: right-click panel -> Add Widgets -> 'Claude Usage'."
