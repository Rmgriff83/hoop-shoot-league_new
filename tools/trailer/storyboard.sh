#!/bin/zsh
# The storyboard for Checkpoint A (docs/TRAILER.md → Storyboard): one frame
# per shot, rendered by the game at each shot's `poster` step, plus a
# contact sheet per layout. No Movie Maker: a normal window, half size.
# Usage: tools/trailer/storyboard.sh <appstore|social> [shot names…]   (default: every shot)
set -eo pipefail
PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="/Applications/Godot_mono.app/Contents/MacOS/Godot"
FFMPEG="/opt/homebrew/bin/ffmpeg"
LAYOUT="${1:-appstore}"; shift || true
case "$LAYOUT" in
  appstore) RES=720x1560; SAFE=(--qa-safe-top=118 --qa-safe-bottom=62) ;;   # an iPhone's notch and home bar
  social)   RES=720x1280; SAFE=() ;;
  *) echo "layout is appstore or social"; exit 1 ;;
esac
OUT="$PROJ/marketing/trailer/checkpoint_a/frames/$LAYOUT"
mkdir -p "$OUT"
cd "$PROJ"
if [[ $# -gt 0 ]]; then SHOTS=("$@"); else SHOTS=($(ls tools/trailer/shots/*.json | xargs -n1 basename | sed 's/\.json$//')); fi
FAILED=()
for s in "${SHOTS[@]}"; do
  rm -f "$OUT/$s.png"
  "$PROJ/tools/trailer/profile.sh" restore
  caffeinate -dimsu perl -e 'alarm 150; exec @ARGV' "$GODOT" --path "$PROJ" --resolution $RES -- \
    --qa-trailer="$PROJ/tools/trailer/shots/$s.json" --qa-trailer-layout="$LAYOUT" --qa-trailer-still \
    --save-dir=trailer_save --no-net "${SAFE[@]}" > "$OUT/$s.log" 2>&1 || true
  if [[ ! -f "$OUT/$s.png" ]] || grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error|TRAILER PROBLEM" "$OUT/$s.log"; then
    FAILED+=("$s"); echo "✗ $s"; grep -nE "SCRIPT ERROR|SHADER ERROR|Parse Error|TRAILER PROBLEM" -A2 "$OUT/$s.log" | cut -c1-200 | head -8
  else
    echo "✓ $s  $(grep -o 'flicks=.*problems' "$OUT/$s.log" | head -1)"
  fi
done
echo "failed: ${FAILED[*]:-none}"
