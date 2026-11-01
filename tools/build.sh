#!/bin/zsh
# The unified build (docs/BUILD.md, 2026-10-24): every store artefact from one
# command, like the bball sim's `npm run release` — minus the web build.
#
#   tools/build.sh [android|ios|all] [--release|--debug] [--deploy] [--open]
#
#   all (default)   the Play AAB (release, gradle, the upload keystore from
#                   ~/.config/hoop_shoot/release.env) and the iOS Xcode project
#   android         the AAB (--release, default) or the fast debug APK (--debug)
#   ios             build/ios/hoop_shoot.xcodeproj — Ross archives and uploads in Xcode
#   --deploy        android --debug, then install the APK on the phone
#   --open          ios, then open the Xcode project
#
# The version (X.Y.Z) is project.godot's application/config/version; the build
# number is the git commit count, written into export_presets.cfg's version
# lines (the only thing this script changes in the repo — the diff is meant to
# be committed). A release build refuses a dirty tree. Never run with the
# editor open: the headless export must be the only Godot on this Mac.
set -eo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="/Applications/Godot_mono.app/Contents/MacOS/Godot"
RELEASE_ENV="$HOME/.config/hoop_shoot/release.env"
TEMPLATE_VERSION="4.7.1.stable.mono"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
NOISE='EditorSettings not instantiated|^Godot Engine|^$'

TARGET="all"
MODE="release"
DEPLOY=0
OPEN=0
for a in "$@"; do
  case "$a" in
    android|ios|all) TARGET="$a" ;;
    --release) MODE="release" ;;
    --debug) MODE="debug" ;;
    --deploy) DEPLOY=1; TARGET="android"; MODE="debug" ;;
    --open) OPEN=1; TARGET="ios" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $a (see --help)"; exit 2 ;;
  esac
done

cd "$PROJ"
if pgrep -f "Godot_mono.app/Contents/MacOS/Godot" >/dev/null; then
  echo "a Godot instance is running — close the editor first (the export runs alone)"
  exit 1
fi

VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
BUILD="$(git rev-list --count HEAD)"
[[ -n "$VERSION" ]] || { echo "project.godot has no application/config/version"; exit 1; }

if [[ "$MODE" == "release" ]]; then
  DIRTY="$(git status --porcelain --untracked-files=no -- . ':!export_presets.cfg')"
  if [[ -n "$DIRTY" ]]; then
    echo "a release build wants a clean tree; commit or stash:"
    echo "$DIRTY"
    exit 1
  fi
fi

# The build number into every preset: version/code (Android) and application/version (iOS).
sed -i '' -E "s|^version/code=.*|version/code=$BUILD|; s|^application/version=.*|application/version=\"$BUILD\"|" export_presets.cfg
echo "Hoop Shoot League $VERSION build $BUILD ($MODE)"

# The RevenueCat plugin's binaries (docs/BUILD.md → The store plugin) live
# outside the repo like the keystore; copy them in for the exports that can
# carry them (the Play gradle build, iOS). Missing: a warning, the export
# goes on and the game runs its null store backend (today's stub store).
STORE_PLUGIN="$HOME/.config/hoop_shoot/revenuecat"
stage_store_plugin() {
  if [[ -d "$STORE_PLUGIN/android/revenue_cat" && -d "$STORE_PLUGIN/ios/plugins/revenue_cat" ]]; then
    rm -rf android/revenue_cat ios/plugins/revenue_cat
    mkdir -p android ios/plugins
    cp -R "$STORE_PLUGIN/android/revenue_cat" android/revenue_cat
    cp -R "$STORE_PLUGIN/ios/plugins/revenue_cat" ios/plugins/revenue_cat
    # .gdignore keeps the editor's resource scan out of the frameworks (their
    # 137 MB of Swift ABI .json would otherwise be packed into the pck, and
    # their jpgs imported); the exports find the .gdip / .aar through the
    # filesystem, so they still ship.
    touch android/revenue_cat/.gdignore ios/plugins/revenue_cat/.gdignore
    echo "staged the RevenueCat plugin from $STORE_PLUGIN"
  else
    echo "no RevenueCat plugin at $STORE_PLUGIN (tools/fetch_store_plugin.sh installs it): the store runs its stub"
  fi
  [[ -f store_keys.json ]] || echo "no store_keys.json (see store_keys.example.json): the store runs its stub"
}
stage_store_plugin

godot_export() {  # preset path
  local flag="--export-$MODE"
  "$GODOT" --headless --path "$PROJ" "${INSTALL[@]}" "$flag" "$1" "$2" 2>&1 | tee build/export.log | grep -vE "$NOISE"
  # The plugin's own files must never end up in the pck (see stage_store_plugin).
  if grep -q 'Storing File: res://ios/plugins/\|Storing File: res://android/revenue_cat/' build/export.log; then
    echo "the export packed the store plugin's files into the pck (the .gdignore is missing?)"
    exit 1
  fi
}

ARTEFACTS=()
if [[ "$TARGET" == "android" || "$TARGET" == "all" ]]; then
  INSTALL=()
  if [[ "$MODE" == "release" || "$TARGET" == "all" ]]; then
    if [[ ! -f "$RELEASE_ENV" ]]; then
      echo "no $RELEASE_ENV — the Play build signs with the upload keystore; one-time setup in docs/BUILD.md:"
      echo "  mkdir -p ~/.config/hoop_shoot && \"\$JAVA_HOME/bin/keytool\" -genkeypair -v -keystore ~/.config/hoop_shoot/upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000"
      echo "  then write release.env with GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD"
      exit 1
    fi
    source "$RELEASE_ENV"
    [[ -f "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]] || { echo "GODOT_ANDROID_KEYSTORE_RELEASE_PATH does not point at a keystore"; exit 1; }
    export GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    # The gradle build template (android/build) once per Godot version.
    if [[ ! -f android/.build_version || "$(cat android/.build_version)" != "$TEMPLATE_VERSION" ]]; then
      INSTALL=(--install-android-build-template)
      echo "installing the Android build template ($TEMPLATE_VERSION)"
    fi
    mkdir -p build
    godot_export "Android Play" "build/hoop_shoot.aab"
    [[ -f build/hoop_shoot.aab ]] || { echo "no AAB came out"; exit 1; }
    ARTEFACTS+=("build/hoop_shoot.aab  → Play Console → Testing → Internal testing → upload")
  else
    mkdir -p build
    godot_export "Android" "build/hoop_shoot.apk"
    [[ -f build/hoop_shoot.apk ]] || { echo "no APK came out"; exit 1; }
    ARTEFACTS+=("build/hoop_shoot.apk  (debug: every area open, the dev settings rows)")
  fi
fi

if [[ "$TARGET" == "ios" || "$TARGET" == "all" ]]; then
  INSTALL=()
  mkdir -p build/ios
  godot_export "iOS" "build/ios/hoop_shoot.ipa"
  [[ -d build/ios/hoop_shoot.xcodeproj ]] || { echo "no Xcode project came out"; exit 1; }
  ARTEFACTS+=("build/ios/hoop_shoot.xcodeproj  → Xcode: Any iOS Device → Product → Archive → Distribute App → App Store Connect")
fi

echo
echo "built $VERSION ($BUILD):"
for a in "${ARTEFACTS[@]}"; do echo "  $a"; done
if (( DEPLOY )); then
  echo
  "$PROJ/tools/android_deploy.sh" --no-export
fi
if (( OPEN )); then
  open "$PROJ/build/ios/hoop_shoot.xcodeproj"
fi
