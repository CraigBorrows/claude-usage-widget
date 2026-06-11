#!/usr/bin/env bash
# Build a distributable .plasmoid (a zip of package/ with metadata.json at the
# root). Install it anywhere with:
#   kpackagetool6 -t Plasma/Applet -i dist/claude-usage.plasmoid
# or upload to store.kde.org -> appears under Add Widgets -> Get New Widgets.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/dist/claude-usage.plasmoid"
VER=$(python3 -c "import json;print(json.load(open('$HERE/package/metadata.json'))['KPlugin']['Version'])")

mkdir -p "$HERE/dist"
rm -f "$OUT"
( cd "$HERE/package" && zip -rq "$OUT" . -x '*.qmlc' -x '__pycache__/*' )

echo "Built $OUT (v$VER)"
unzip -l "$OUT"
