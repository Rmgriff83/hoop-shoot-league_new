#!/usr/bin/env bash
# Fetch the Play Games Services plugin's binaries (docs/BUILD.md → The Play
# Games plugin): godot-sdk-integrations/godot-play-game-services, one pinned
# release, checked against its SHA-256, into ~/.config/hoop_shoot/playgames
# where tools/build.sh stages them from. Only the two .aar files, the licence
# and the ProGuard rules are kept: the addon's GDScript wrappers (autoloads
# around the Android singleton) are not used — game/net/play_games_backend.gd
# talks to the singleton directly, as the Game Center backend does — and its
# export plugin (which wants the game id in export_presets.cfg) is replaced by
# addons/PlayGamesPlugin, which reads data/play_games.json.
# Godot has no package manager, so this is the lockfile: bump VERSION and
# SHA256 together when moving to a new release (and re-check the plugin's
# method and signal names in game/net/play_games_backend.gd).
#
#   tools/fetch_play_games_plugin.sh          # install (a no-op when the version is already there)
#   tools/fetch_play_games_plugin.sh --force  # fetch again
set -euo pipefail

VERSION="v3.4.0"
SHA256="3a1af78f5b9cbf13253b6bffb7795f0c1a9e7d1495052cd456bb6cfb1c265edd"
URL="https://github.com/godot-sdk-integrations/godot-play-game-services/releases/download/$VERSION/addons.zip"
DEST="$HOME/.config/hoop_shoot/playgames"

if [[ "${1:-}" != "--force" && -f "$DEST/VERSION" && "$(cat "$DEST/VERSION")" == "$VERSION" ]]; then
  echo "Play Games plugin $VERSION already at $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "fetching godot-play-game-services $VERSION (~200 KB)…"
curl -sSfL -o "$WORK/plugin.zip" "$URL"
echo "$SHA256  $WORK/plugin.zip" | shasum -a 256 -c - >/dev/null || { echo "SHA-256 mismatch: the download is not the pinned $VERSION release"; exit 1; }
unzip -q "$WORK/plugin.zip" -d "$WORK/unpacked"
SRC="$WORK/unpacked/addons/GodotPlayGameServices"
[[ -f "$SRC/bin/debug/GodotPlayGameServices-debug.aar" && -f "$SRC/bin/release/GodotPlayGameServices-release.aar" ]] || { echo "the zip's layout changed (expected addons/GodotPlayGameServices/bin/{debug,release}/*.aar)"; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST/android"
cp "$SRC/bin/debug/GodotPlayGameServices-debug.aar" "$DEST/android/play_games.debug.aar"
cp "$SRC/bin/release/GodotPlayGameServices-release.aar" "$DEST/android/play_games.release.aar"
cp "$SRC/LICENSE" "$DEST/LICENSE"
echo "$VERSION" > "$DEST/VERSION"
echo "installed to $DEST (android/play_games.{debug,release}.aar)"
