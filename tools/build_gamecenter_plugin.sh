#!/bin/zsh
# Build the Game Center iOS plugin (docs/BUILD.md → The Game Center plugin):
# the vendored godot-ios-plugins source in tools/ios_plugins/gamecenter,
# compiled against Godot's own headers (the engine source at GODOT_TAG,
# fetched once) into ~/.config/hoop_shoot/gamecenter/ios/plugins, where
# tools/build.sh stages it from. The godot-ios-plugins repo publishes no 4.x
# binaries, so this is the fetch scripts' stand-in: the output is stamped
# with the vendored source's hash and the engine tag and rebuilt only when
# either changes (or --force). Needs Xcode's command line tools and scons
# (brew install scons) — scons only writes the engine's few generated
# headers, never a full engine build.
#
#   tools/build_gamecenter_plugin.sh          # build (a no-op when the stamp matches)
#   tools/build_gamecenter_plugin.sh --force  # build again
set -eo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJ/tools/ios_plugins/gamecenter"
DEST="$HOME/.config/hoop_shoot/gamecenter"
GODOT_TAG="4.7.1-stable"               # the editor/export templates' version (tools/build.sh TEMPLATE_VERSION)
GODOT_SHA256="eb2378d76964b25d5ecb61e16c934b59ae4f605c42cdb1a2a49eb7bf6d33dcf0"
GODOT_URL="https://github.com/godotengine/godot/archive/refs/tags/$GODOT_TAG.tar.gz"
MIN_IOS="15.0"                         # export_presets.cfg application/min_ios_version
# The engine's generated headers the plugin's includes reach (version.h,
# object.h, class_db.h); scons makes exactly these when named as targets.
GEN_HEADERS=(core/version_generated.gen.h core/extension/gdextension_interface.gen.h core/disabled_classes.gen.h)

SOURCES=("$SRC"/game_center_module.cpp "$SRC"/game_center.mm "$SRC"/game_center_delegate.mm)
STAMP="$(cat "$SRC"/*.h "$SRC"/*.mm "$SRC"/*.cpp "$SRC"/gamecenter.gdip | shasum -a 256 | cut -c1-16) $GODOT_TAG ios$MIN_IOS"
if [[ "${1:-}" != "--force" && -f "$DEST/VERSION" && "$(cat "$DEST/VERSION")" == "$STAMP" ]]; then
  echo "Game Center plugin already built at $DEST ($STAMP)"
  exit 0
fi

command -v xcrun >/dev/null || { echo "no xcrun: install Xcode's command line tools"; exit 1; }
command -v scons >/dev/null || { echo "no scons (brew install scons): it writes the engine's generated headers"; exit 1; }

# The engine source, once (its headers; nothing of it is compiled).
mkdir -p "$DEST/src"
if [[ ! -f "$DEST/src/godot/version.py" || "$(cat "$DEST/src/GODOT_TAG" 2>/dev/null)" != "$GODOT_TAG" ]]; then
  TAR="$DEST/src/godot-$GODOT_TAG.tar.gz"
  if [[ ! -f "$TAR" ]] || ! echo "$GODOT_SHA256  $TAR" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "fetching the Godot $GODOT_TAG source (~70 MB)…"
    curl -sSfL -o "$TAR" "$GODOT_URL"
    echo "$GODOT_SHA256  $TAR" | shasum -a 256 -c - >/dev/null || { echo "SHA-256 mismatch: the download is not the pinned $GODOT_TAG source"; exit 1; }
  fi
  rm -rf "$DEST/src/godot" "$DEST/src/godot-$GODOT_TAG"
  tar xzf "$TAR" -C "$DEST/src"
  mv "$DEST/src/godot-$GODOT_TAG" "$DEST/src/godot"
  echo "$GODOT_TAG" > "$DEST/src/GODOT_TAG"
fi
GODOT="$DEST/src/godot"

for h in "${GEN_HEADERS[@]}"; do
  if [[ ! -f "$GODOT/$h" ]]; then
    echo "generating $h"
    (cd "$GODOT" && scons platform=ios arch=arm64 target=template_release verbose=no "$h" >/dev/null)
    [[ -f "$GODOT/$h" ]] || { echo "scons did not write $h"; exit 1; }
  fi
done

BUILD="$DEST/build"
rm -rf "$BUILD" "$DEST/ios"
mkdir -p "$DEST/ios/plugins"
COMMON=(-arch arm64 "-miphoneos-version-min=$MIN_IOS" -std=gnu++17 -fobjc-arc -DIOS_ENABLED -DUNIX_ENABLED -DVULKAN_ENABLED -DNEED_LONG_INT -DPTRCALL_ENABLED -I "$GODOT" -I "$GODOT/platform/ios" -Wno-deprecated-declarations)
for target in release debug; do
  OUT="$BUILD/$target"
  mkdir -p "$OUT"
  if [[ "$target" == "release" ]]; then FLAGS=(-O2); else FLAGS=(-O0 -g -D_DEBUG -DDEBUG=1 -DDEBUG_ENABLED); fi
  OBJS=()
  for s in "${SOURCES[@]}"; do
    o="$OUT/$(basename "${s%.*}").o"
    xcrun -sdk iphoneos clang++ "${COMMON[@]}" "${FLAGS[@]}" -c "$s" -o "$o"
    OBJS+=("$o")
  done
  xcrun libtool -static -o "$OUT/libgamecenter.a" "${OBJS[@]}"
  xcodebuild -create-xcframework -library "$OUT/libgamecenter.a" -output "$DEST/ios/plugins/gamecenter.$target.xcframework" >/dev/null
  echo "built gamecenter.$target.xcframework"
done
cp "$SRC/gamecenter.gdip" "$DEST/ios/plugins/gamecenter.gdip"
echo "$STAMP" > "$DEST/VERSION"
echo "installed to $DEST/ios/plugins (gamecenter.gdip, gamecenter.release.xcframework, gamecenter.debug.xcframework)"
