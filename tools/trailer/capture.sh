#!/bin/zsh
# Capture one trailer shot with Godot's Movie Maker (docs/TRAILER.md → Capture).
# Usage: tools/trailer/capture.sh <shot.json> <appstore|social> [extra game args…]
#   appstore → 1440x3120 frames (2x the 720x1560 layout; the cut downscales to 886x1920)
#   social   → 1440x2560 frames (2x the 720x1280 layout; the cut downscales to 1080x1920)
# Writes marketing/trailer/clips/<layout>/<shot>.mov (+ .wav of the game's SFX)
# and deletes the PNG frames. Never run two Godot instances at once.
#
# Movie Maker records at the project's window-size override, and the frame is
# only crisp when the window really is that size. The window is taller than
# this Mac's screen, so a temporary override.cfg asks for a borderless
# oversize window; it is removed on the way out, whatever happens
# (tools/build.sh and the test suite both refuse a leftover one).
set -eo pipefail
PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="/Applications/Godot_mono.app/Contents/MacOS/Godot"
FFMPEG="/opt/homebrew/bin/ffmpeg"
SHOT="$1"; LAYOUT="$2"
[[ -f "$SHOT" && -n "$LAYOUT" ]] || { echo "usage: capture.sh <shot.json> <appstore|social> [args…]"; exit 1; }
shift 2
case "$LAYOUT" in
  appstore) W=1440; H=3120 ;;
  social)   W=1440; H=2560 ;;
  *) echo "layout is appstore or social"; exit 1 ;;
esac
# TRAILER_W / TRAILER_H override the frame size (the crispness comparison renders one shot at the final size).
W="${TRAILER_W:-$W}"; H="${TRAILER_H:-$H}"
NAME="$(basename "$SHOT" .json)${TRAILER_SUFFIX:-}"
OUT="$PROJ/marketing/trailer/clips/$LAYOUT"
FRAMES="$PROJ/marketing/trailer/frames/$LAYOUT/$NAME"
rm -rf "$FRAMES"; mkdir -p "$FRAMES" "$OUT"
cd "$PROJ"
[[ ! -f override.cfg ]] || { echo "override.cfg already exists; remove it first"; exit 1; }
trap 'rm -f "$PROJ/override.cfg"' EXIT INT TERM
printf '[display]\n\nwindow/size/window_width_override=%d\nwindow/size/window_height_override=%d\nwindow/size/borderless=true\n' $W $H > override.cfg
SHOT_ABS="$(cd "$(dirname "$SHOT")" && pwd)/$(basename "$SHOT")"
"$PROJ/tools/trailer/profile.sh" restore   # every shot starts from the same save
case "$LAYOUT" in appstore) SAFE=(--qa-safe-top=118 --qa-safe-bottom=62) ;; *) SAFE=() ;; esac   # an iPhone's notch and home bar
caffeinate -dimsu perl -e 'alarm 900; exec @ARGV' "$GODOT" --path "$PROJ" --write-movie "$FRAMES/frame.png" --fixed-fps 60 -- \
  --qa-trailer="$SHOT_ABS" --qa-trailer-layout="$LAYOUT" --qa-trailer-out="$OUT" --save-dir=trailer_save --no-net "${SAFE[@]}" "$@" > "$FRAMES/godot.log" 2>&1 || { echo "✗ godot failed; see $FRAMES/godot.log"; exit 1; }
rm -f override.cfg
if grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error|null instance|previously freed" "$FRAMES/godot.log"; then
  echo "✗ errors in $FRAMES/godot.log:"; grep -nE "SCRIPT ERROR|SHADER ERROR|Parse Error|null instance|previously freed" -A3 "$FRAMES/godot.log" | head -20; exit 1
fi
N=$(ls "$FRAMES"/frame*.png 2>/dev/null | wc -l | tr -d ' ')
[[ "$N" -gt 0 ]] || { echo "✗ no frames written"; exit 1; }
# Keep only the shot (half a second either side of its in and out marks): the
# staging before it is long and the intermediates are large. The marks are
# rewritten to count from the kept clip's first frame.
MARKS="$OUT/$(basename "$SHOT" .json).marks.json"
[[ -f "$MARKS" ]] || { echo "✗ no marks written for $NAME"; exit 1; }
read START COUNT < <(python3 -I - "$MARKS" "$N" <<'PY'
import json, sys
path, n = sys.argv[1], int(sys.argv[2])
doc = json.load(open(path))
m = doc["marks"]
start = max(0, int(m.get("in", 0)) - 30)
end = min(n, int(m.get("out", m.get("end", n))) + 30)
doc["marks"] = {k: int(v) - start for k, v in m.items()}
doc["trimmed_from"] = start
json.dump(doc, open(path, "w"), indent=1)
print(start, max(1, end - start))
PY
)
# A visually lossless all-intra intermediate; the cut is built from these.
"$FFMPEG" -y -loglevel error -framerate 60 -start_number "$START" -i "$FRAMES/frame%08d.png" -frames:v "$COUNT" -c:v libx264 -preset fast -crf 10 -g 1 -pix_fmt yuv420p "$OUT/$NAME.mov"
"$FFMPEG" -y -loglevel error -ss "$(python3 -I -c "print($START/60)")" -t "$(python3 -I -c "print($COUNT/60)")" -i "$FRAMES/frame.wav" "$OUT/$NAME.wav"
cp "$FRAMES/godot.log" "$OUT/$NAME.log"
rm -rf "$FRAMES"
echo "✓ $NAME ($LAYOUT): $N frames → $OUT/$NAME.mov"
