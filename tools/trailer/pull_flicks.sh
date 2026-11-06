#!/bin/zsh
# Copy the flick recordings off the Android phone (docs/TRAILER.md → Recording flicks).
# The game writes them to user://trailer/flicks.jsonl while Settings → DEV →
# RECORD FLICKS is on (debug builds only).
# Usage: tools/trailer/pull_flicks.sh           copy to marketing/trailer/flicks/flicks_<time>.jsonl
#        tools/trailer/pull_flicks.sh --clear   …and start the phone's file again
set -e
PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
PKG="com.rossgriffus.hoopshoot"
OUT_DIR="$PROJ/marketing/trailer/flicks"
DEV=$("$ADB" devices | awk -F'\t' 'NR>1 && $2=="device" {print $1; exit}')
if [[ -z "$DEV" ]]; then
  echo "✗ no Android device in 'device' state."
  "$ADB" devices
  exit 1
fi
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/flicks_$(date +%Y%m%d_%H%M%S).jsonl"
"$ADB" -s "$DEV" shell run-as "$PKG" cat files/trailer/flicks.jsonl > "$OUT" 2>/dev/null || true
N=$(grep -c '"trace"' "$OUT" 2>/dev/null || true)
if [[ -z "$N" || "$N" == "0" ]]; then
  rm -f "$OUT"
  echo "✗ nothing recorded yet (is RECORD FLICKS on, and has a shot been taken?)"
  exit 1
fi
echo "✓ $N flicks → $OUT"
if [[ "$1" == "--clear" ]]; then
  "$ADB" -s "$DEV" shell run-as "$PKG" rm -f files/trailer/flicks.jsonl
  echo "✓ the phone's file is cleared"
fi
