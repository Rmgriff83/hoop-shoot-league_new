#!/bin/zsh
# Convert Ross's recorded ball bounces into the classic ball's sfx folder,
# matching the hoop clips (16-bit PCM, mono, 44.1 kHz). Re-run after new
# recordings; the originals stay where they are. Folders may contain spaces.
#   tools/import_ball_sfx.sh "/path/to/files (4)" "/path/to/files (3)"
set -e
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/balls/classic/sfx"
mkdir -p "$OUT"
n=0
for dir in "$@"; do
  for f in "$dir"/ball_*.wav(n); do        # (n): numeric sort → ball_1, ball_2, … ball_10
    n=$((n + 1))
    afconvert -f WAVE -d LEI16@44100 -c 1 "$f" "$OUT/$(printf 'bounce_%02d.wav' $n)"
  done
done
echo "converted $n clips into $OUT"
