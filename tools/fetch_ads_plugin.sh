#!/usr/bin/env bash
# Fetch the AdMob plugin (docs/BUILD.md → The ads plugin): godot-sdk-integrations/
# godot-admob, one pinned release, checked against its SHA-256. The addon's
# GDScript is vendored in the repo (addons/AdmobPlugin, addons/GMPShared);
# this installs the BINARIES — the Android .aar pair and the iOS
# xcframeworks + .gdip — into ~/.config/hoop_shoot/admob, where
# tools/build.sh stages them from. Bump VERSION and SHA256 together when
# moving to a new release (and re-vendor the addon: see --vendor).
#
#   tools/fetch_ads_plugin.sh            # install (a no-op when the version is already there)
#   tools/fetch_ads_plugin.sh --force    # fetch again
#   tools/fetch_ads_plugin.sh --vendor   # also copy the addon's GDScript into addons/ (a new release)
set -euo pipefail

VERSION="v7.0"
SHA256="d96e1734b889434c0a77f0bafe2f09f4cdb9e5b518b9d6809757b251a17cf8a2"
URL="https://github.com/godot-sdk-integrations/godot-admob/releases/download/$VERSION/AdmobPlugin-Multi-$VERSION.zip"
DEST="$HOME/.config/hoop_shoot/admob"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"

FORCE=0; VENDOR=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --vendor) VENDOR=1 ;;
    *) echo "unknown argument: $a"; exit 2 ;;
  esac
done

if [[ $FORCE -eq 0 && $VENDOR -eq 0 && -f "$DEST/VERSION" && "$(cat "$DEST/VERSION")" == "$VERSION" ]]; then
  echo "AdMob plugin $VERSION already at $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "fetching godot-admob $VERSION (~1 MB; the Google Mobile Ads SDK itself comes by gradle / Swift Package Manager at build time)…"
curl -sSfL -o "$WORK/plugin.zip" "$URL"
echo "$SHA256  $WORK/plugin.zip" | shasum -a 256 -c - >/dev/null || { echo "SHA-256 mismatch: the download is not the pinned $VERSION release"; exit 1; }
unzip -q "$WORK/plugin.zip" -d "$WORK/unpacked"
SRC="$WORK/unpacked/res"
[[ -d "$SRC/addons/AdmobPlugin/bin" && -f "$SRC/ios/plugins/AdmobPlugin.gdip" && -d "$SRC/ios/plugins/AdmobPlugin.release.xcframework" ]] || { echo "the zip's layout changed (expected addons/AdmobPlugin/bin and ios/plugins/AdmobPlugin.*)"; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST/android" "$DEST/ios/plugins"
cp -R "$SRC/addons/AdmobPlugin/bin" "$DEST/android/bin"
cp "$SRC/ios/plugins/AdmobPlugin.gdip" "$DEST/ios/plugins/"
cp -R "$SRC/ios/plugins/AdmobPlugin.debug.xcframework" "$SRC/ios/plugins/AdmobPlugin.release.xcframework" "$DEST/ios/plugins/"
echo "$VERSION" > "$DEST/VERSION"
echo "installed to $DEST (android/bin, ios/plugins)"

if [[ $VENDOR -eq 1 ]]; then
  # The addon's GDScript (MIT) into the repo, minus the binaries.
  rm -rf "$PROJ/addons/AdmobPlugin" "$PROJ/addons/GMPShared"
  cp -R "$SRC/addons/AdmobPlugin" "$PROJ/addons/AdmobPlugin"
  rm -rf "$PROJ/addons/AdmobPlugin/bin"
  cp -R "$SRC/addons/GMPShared" "$PROJ/addons/GMPShared"
  echo "vendored addons/AdmobPlugin and addons/GMPShared (check the diff, then commit)"
fi
