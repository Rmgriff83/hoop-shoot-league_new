#!/bin/zsh
# Export a debug APK, install it on the connected Android device, and launch it.
# Usage: tools/android_deploy.sh            (from anywhere)
#        tools/android_deploy.sh --no-export  (just reinstall + launch the last build)
#
# Needs: USB debugging enabled on the device and the "Allow USB debugging?"
# prompt accepted once. Check with:  ~/Library/Android/sdk/platform-tools/adb devices
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="/Applications/Godot_mono.app/Contents/MacOS/Godot"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
APK="$PROJ/build/hoop_shoot.apk"
PKG="com.rossgriffus.hoopshoot"

if [[ "$1" != "--no-export" ]]; then
  echo "▶ exporting debug APK…"
  "$GODOT" --headless --path "$PROJ" --export-debug "Android" "$APK" 2>&1 \
    | grep -vE "EditorSettings not instantiated|^Godot Engine|^$" || true
fi
[[ -f "$APK" ]] || { echo "no APK at $APK"; exit 1; }

# `adb devices` is TAB-delimited, and a wireless serial can contain a space
# (adb appends " (2)" when the same device is also reachable another way), so
# splitting on whitespace loses the device entirely.
DEV=$("$ADB" devices | awk -F'\t' 'NR>1 && $2=="device" {print $1; exit}')
if [[ -z "$DEV" ]]; then
  echo "✗ no Android device in 'device' state. Plug it in, enable USB debugging, accept the prompt."
  "$ADB" devices
  exit 1
fi
echo "▶ installing on $DEV…"
"$ADB" -s "$DEV" install -r "$APK"
echo "▶ launching…"
"$ADB" -s "$DEV" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "✓ running. Logs:  $ADB logcat -s godot"
