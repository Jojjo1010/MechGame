#!/usr/bin/env bash
# Build the Web export and (optionally) push it to itch.io via butler.
#
# One-time setup before this script will work:
#   1. Open Godot → Editor → Manage Export Templates → install 4.6.2 templates.
#   2. Project → Export → add a "Web" preset named exactly "Web".
#      Set "Export Path" to: build/web/index.html
#      Tick: Variant → Thread Support
#      Tick: Progressive Web App → Ensure Cross-Origin Isolation Headers
#   3. Install butler:  https://itch.io/docs/butler/installing.html
#   4. Run once:  butler login
#   5. Create the itch.io page (Restricted / password-gated), note the slug.
#   6. Set ITCH_TARGET below (or export it) — format: <user>/<game>:<channel>
#
# Usage:
#   ./release.sh           # build + push
#   ./release.sh --local   # build only, skip butler
set -euo pipefail

GODOT="${GODOT:-/c/Users/Johanna/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe}"
ITCH_TARGET="${ITCH_TARGET:-granstrom/mech-game:web}"
OUT_DIR="build/web"
OUT_FILE="$OUT_DIR/index.html"

cd "$(dirname "$0")"

if [ ! -x "$GODOT" ] && [ ! -f "$GODOT" ]; then
  echo "Godot not found at: $GODOT"
  echo "Override with: GODOT=/path/to/godot.exe ./release.sh"
  exit 1
fi

mkdir -p "$OUT_DIR"
echo "→ Exporting Web build to $OUT_FILE"
"$GODOT" --headless --path . --export-release "Web" "$OUT_FILE"

if [ "${1:-}" = "--local" ]; then
  echo "✓ Build done. Skipping butler (--local). Open $OUT_FILE via a server with COOP/COEP headers."
  exit 0
fi

if ! command -v butler >/dev/null 2>&1; then
  echo "butler not on PATH — skipping push. Install from https://itch.io/docs/butler/ and re-run."
  exit 0
fi

echo "→ Pushing to $ITCH_TARGET"
butler push "$OUT_DIR" "$ITCH_TARGET"
echo "✓ Done. Latest build live at https://${ITCH_TARGET%%/*}.itch.io/${ITCH_TARGET#*/}" | sed 's/:.*//'
