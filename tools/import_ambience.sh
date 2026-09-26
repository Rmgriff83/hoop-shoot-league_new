#!/bin/zsh
# Encode an ambient recording for an arena as Ogg Vorbis (stereo, 44.1 kHz,
# quality 3 ≈ 110 kbps) into assets/arena/<arena>/ambience/<name>.ogg. Per-layer
# gain lives on the arena set (ambient_gains_db), so loudness is left alone.
#   tools/import_ambience.sh beach seagulls "~/Downloads/864817__rthijs__nieuwpoort-seagulls-02.wav"
set -e
arena="$1"; name="$2"; src="$3"
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/arena/$arena/ambience"
mkdir -p "$OUT"
/opt/homebrew/bin/ffmpeg -y -loglevel error -i "$src" -vn -ac 2 -ar 44100 -c:a vorbis -strict -2 -q:a 3 "$OUT/$name.ogg"
ls -la "$OUT/$name.ogg" | awk '{print "wrote", $9, $5, "bytes"}'
