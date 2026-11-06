#!/bin/zsh
# The trailer's save (docs/TRAILER.md → The profile).
# Usage: tools/trailer/profile.sh build     write the profile and keep a pristine copy of it
#        tools/trailer/profile.sh restore   put the pristine copy back (every shot starts from it)
set -eo pipefail
PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="/Applications/Godot_mono.app/Contents/MacOS/Godot"
USERDIR="$HOME/Library/Application Support/Godot/app_userdata/Hoop Shoot League"
SAVE="$USERDIR/trailer_save"; BASE="$USERDIR/trailer_save_base"
case "$1" in
  build)
    caffeinate -dimsu perl -e 'alarm 120; exec @ARGV' "$GODOT" --path "$PROJ" --resolution 360x780 -- --qa-trailer-profile --save-dir=trailer_save --no-net 2>&1 | grep "TRAILER" || { echo "✗ the profile did not build"; exit 1; }
    rm -rf "$BASE"; cp -R "$SAVE" "$BASE"; echo "✓ profile built and snapshotted" ;;
  restore)
    [[ -d "$BASE" ]] || { echo "✗ no snapshot: run tools/trailer/profile.sh build"; exit 1; }
    rm -rf "$SAVE"; cp -R "$BASE" "$SAVE" ;;
  *) echo "usage: profile.sh build|restore"; exit 1 ;;
esac
