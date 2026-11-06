#!/bin/zsh
# Render a cut's text cards with the game (docs/TRAILER.md → Text cards):
# PNG sequences with alpha in marketing/trailer/cards/<layout>/<id>/, and a
# still of each in marketing/trailer/checkpoint_a/cards/<layout>/.
# Usage: tools/trailer/cards.sh <appstore|social>
set -eo pipefail
PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
LAYOUT="${1:-appstore}"
LOG="$PROJ/marketing/trailer/cards/$LAYOUT.log"
mkdir -p "$PROJ/marketing/trailer/cards"
caffeinate -dimsu perl -e 'alarm 600; exec @ARGV' /Applications/Godot_mono.app/Contents/MacOS/Godot --path "$PROJ" --resolution 360x640 -- \
  --qa-trailer-cards="$LAYOUT" --save-dir=trailer_save --no-net > "$LOG" 2>&1 || { echo "✗ cards failed; see $LOG"; grep -nE "SCRIPT ERROR|Parse Error" -A3 "$LOG" | head; exit 1; }
if grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error" "$LOG"; then grep -nE "SCRIPT ERROR|SHADER ERROR|Parse Error" -A3 "$LOG" | head -12; exit 1; fi
grep "TRAILER card" "$LOG"
