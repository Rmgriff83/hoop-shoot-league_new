#!/bin/zsh
# Encode a music loop as Ogg Vorbis into assets/music/<name>.ogg (same settings
# as tools/import_ambience.sh). Gain lives where the track is used (App.TITLE_MUSIC).
#   tools/import_music.sh title_moog "~/Downloads/856449__fonoskop__moog_sem-110bpm.wav"
set -e
name="$1"; src="$2"
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/music"
mkdir -p "$OUT"
/opt/homebrew/bin/ffmpeg -y -loglevel error -i "$src" -vn -ac 2 -ar 44100 -c:a vorbis -strict -2 -q:a 3 "$OUT/$name.ogg"
ls -la "$OUT/$name.ogg" | awk '{print "wrote", $9, $5, "bytes"}'
