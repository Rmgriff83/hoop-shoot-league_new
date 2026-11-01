#!/usr/bin/env bash
# Fetch the RevenueCat plugin's binaries (docs/BUILD.md → The store plugin):
# godot-x/revenuecat, one pinned release, checked against its SHA-256, into
# ~/.config/hoop_shoot/revenuecat where tools/build.sh stages them from.
# Godot has no package manager, so this is the lockfile: bump VERSION and
# SHA256 together when moving to a new release (and re-check the plugin's
# API in game/net/revenuecat_backend.gd).
#
#   tools/fetch_store_plugin.sh          # install (a no-op when the version is already there)
#   tools/fetch_store_plugin.sh --force  # fetch again
set -euo pipefail

VERSION="2.6.0"
SHA256="b0845ad905479a778b8cc3b573c8cf2b527340ee03e31402d6d0c1b7b41d49d6"
URL="https://github.com/godot-x/revenuecat/releases/download/$VERSION/godotx_revenue_cat.zip"
DEST="$HOME/.config/hoop_shoot/revenuecat"

if [[ "${1:-}" != "--force" && -f "$DEST/VERSION" && "$(cat "$DEST/VERSION")" == "$VERSION" ]]; then
  echo "RevenueCat plugin $VERSION already at $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "fetching godot-x/revenuecat $VERSION (~240 MB)…"
curl -sSfL -o "$WORK/plugin.zip" "$URL"
echo "$SHA256  $WORK/plugin.zip" | shasum -a 256 -c - >/dev/null || { echo "SHA-256 mismatch: the download is not the pinned $VERSION release"; exit 1; }
unzip -q "$WORK/plugin.zip" -d "$WORK/unpacked"
SRC="$WORK/unpacked/godotx_revenue_cat"
[[ -d "$SRC/android/revenue_cat" && -d "$SRC/ios/plugins/revenue_cat" ]] || { echo "the zip's layout changed (expected android/revenue_cat and ios/plugins/revenue_cat)"; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST/android" "$DEST/ios/plugins"
cp -R "$SRC/android/revenue_cat" "$DEST/android/revenue_cat"
cp -R "$SRC/ios/plugins/revenue_cat" "$DEST/ios/plugins/revenue_cat"
echo "$VERSION" > "$DEST/VERSION"
echo "installed to $DEST (android/revenue_cat, ios/plugins/revenue_cat)"
