#!/usr/bin/env bash
# Build the Windows export and (optionally) push it to itch.io via butler.
# Mirror of release.sh — same setup, different preset/channel.
#
# Usage:
#   ./release-win.sh           # build + push
#   ./release-win.sh --local   # build only, skip butler
set -euo pipefail

GODOT="${GODOT:-/c/Users/Johanna/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe}"
ITCH_TARGET="${ITCH_TARGET:-granstrom/mech-game:windows}"
OUT_DIR="build/win"
OUT_FILE="$OUT_DIR/MechGame.exe"

cd "$(dirname "$0")"

if [ ! -x "$GODOT" ] && [ ! -f "$GODOT" ]; then
  echo "Godot not found at: $GODOT"
  echo "Override with: GODOT=/path/to/godot.exe ./release-win.sh"
  exit 1
fi

# Wipe and recreate so stale leftovers don't get pushed.
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
echo "→ Exporting Windows build to $OUT_FILE"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT_FILE"

if [ "${1:-}" = "--local" ]; then
  echo "✓ Build done. Skipping butler (--local). Output in $OUT_DIR"
  exit 0
fi

if ! command -v butler >/dev/null 2>&1; then
  echo "butler not on PATH — skipping push. Install from https://itch.io/docs/butler/ and re-run."
  exit 0
fi

echo "→ Pushing to $ITCH_TARGET"
butler push "$OUT_DIR" "$ITCH_TARGET"
echo "✓ Done."
