#!/bin/zsh
# Render trailer v2's text cards with the game (docs/TRAILER.md → v2; card_scene.gd
# render_v2): one PNG sequence with alpha per part under marketing/trailer/v2/cards/partNN/
# (1440x3120, from the part's "text card in" hit to its last frame) and a still of each
# in marketing/trailer/v2/cards/stills/.
# Usage: tools/trailer/v2/cards.sh <part numbers, comma-separated>   (a part's card takes minutes: 2 s a frame)
set -eo pipefail
PROJ="$(cd "$(dirname "$0")/../../.." && pwd)"
PARTS="${1:?usage: cards.sh <parts: 1 or 1,2>}"
LOG="$PROJ/marketing/trailer/v2/cards/render.log"
mkdir -p "$PROJ/marketing/trailer/v2/cards"
caffeinate -dimsu perl -e 'alarm 1800; exec @ARGV' /Applications/Godot_mono.app/Contents/MacOS/Godot --path "$PROJ" --resolution 360x640 -- \
  --qa-trailer-cards="v2:$PARTS" --save-dir=trailer_save --no-net > "$LOG" 2>&1 || { echo "✗ cards failed; see $LOG"; grep -nE "SCRIPT ERROR|Parse Error" -A3 "$LOG" | head; exit 1; }
if grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error" "$LOG"; then grep -nE "SCRIPT ERROR|SHADER ERROR|Parse Error" -A3 "$LOG" | head -12; exit 1; fi
grep "TRAILER card" "$LOG"
