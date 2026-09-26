#!/bin/zsh
# Convert a one-shot effect recording into assets/audio/fx/<name>.wav (16-bit
# PCM, mono, 44.1 kHz — the game's clip format), optionally trimmed with a
# short fade-out. Credit it in data/credits.json.
#   tools/import_fx_sfx.sh <name> <source.wav> [start_s] [duration_s]
#   tools/import_fx_sfx.sh fire_burst "~/Downloads/472688__silverillusionist__fire-burst.wav"
#   tools/import_fx_sfx.sh ice_form "~/Downloads/342546__timbreknight__ice-cracking.wav" 0.35 2.4
set -e
name="$1"; src="$2"; start="${3:-}"; dur="${4:-}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/audio/fx"
mkdir -p "$OUT"
if [ -n "$dur" ]; then
  fade_at=$(python3 -c "print(max(0.0, float('$dur') - 0.3))")
  /opt/homebrew/bin/ffmpeg -y -loglevel error -ss "${start:-0}" -t "$dur" -i "$src" -ac 1 -ar 44100 \
    -af "afade=t=out:st=$fade_at:d=0.3" -c:a pcm_s16le "$OUT/$name.wav"
else
  afconvert -f WAVE -d LEI16@44100 -c 1 "$src" "$OUT/$name.wav"
fi
ls -la "$OUT/$name.wav" | awk '{print "wrote", $9, $5, "bytes"}'
