#!/bin/zsh
# Run a QA mode ON THE PHONE and pull what it wrote (docs/PERFORMANCE.md).
# The APK carries QaDriver (an autoload) but takes no command line, so the
# args go through a one-shot file the driver reads and deletes at launch.
# Usage: tools/android_qa.sh --qa-perf [--qa-perf=beach,city] [--qa-perf-seconds=24]
#        ANDROID_SERIAL=<serial> tools/android_qa.sh --qa-perf
# Needs the build installed (tools/android_deploy.sh). Output lands in
# build/qa/<device>/ (perf.json + the run's snaps); build/qa is git-ignored.
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
PKG="com.rossgriffus.hoopshoot"
ARGS="$*"
[[ -n "$ARGS" ]] || { echo "usage: tools/android_qa.sh --qa-<mode> [...]"; exit 1; }
DEV=${ANDROID_SERIAL:-$("$ADB" devices | awk -F'\t' 'NR>1 && $2=="device" {print $1; exit}')}
[[ -n "$DEV" ]] || { echo "✗ no Android device in 'device' state"; "$ADB" devices; exit 1; }
RA() { "$ADB" -s "$DEV" shell run-as "$PKG" "$@"; }
# A whole shell line in the app's sandbox (adb re-splits quotes: hand it one string).
RASH() { "$ADB" -s "$DEV" shell "run-as $PKG sh -c \"$1\""; }
MODEL=$("$ADB" -s "$DEV" shell getprop ro.product.model | tr -d '\r' | tr ' ' '_')
OUT="$PROJ/build/qa/${MODEL:-phone}"
mkdir -p "$OUT"
echo "▶ $MODEL: $ARGS"
"$ADB" -s "$DEV" shell am force-stop "$PKG"
# A dozing phone cannot open a Vulkan surface ("Failed to create vulkan window"): wake it, swipe the
# lock away and wait until it reports Awake (one second was not enough: the launch raced the wake).
"$ADB" -s "$DEV" shell "input keyevent KEYCODE_WAKEUP; sleep 2; input swipe 360 1400 360 500 200; sleep 1" >/dev/null
for i in 1 2 3 4 5 6; do
  "$ADB" -s "$DEV" shell dumpsys power | grep -q "mWakefulness=Awake" && break
  sleep 2
done
if "$ADB" -s "$DEV" shell dumpsys trust | grep -q "deviceLocked=1"; then
  echo "✗ the phone is locked with its credential: unlock it, then run again"; exit 1
fi
RASH "mkdir -p files/qa; rm -f files/qa/perf.json; echo '$ARGS' > files/qa_args.txt"
launch() { "$ADB" -s "$DEV" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null; }
launch
echo "▶ running… (logcat: $ADB -s '$DEV' logcat -s godot)"
WAITED=0; RELAUNCHED=0
until RA test -f files/qa/perf.json 2>/dev/null; do
  sleep 5; WAITED=$((WAITED+5))
  if (( WAITED > 2700 )); then echo "✗ no perf.json after 45 min"; exit 1; fi
  if (( WAITED > 20 )) && [[ -z "$("$ADB" -s "$DEV" shell "ps -A | grep $PKG" | tr -d '\r')" ]]; then
    # the QA mode quits the app once it has written the dump: look once more before calling it a crash
    sleep 2; RA test -f files/qa/perf.json 2>/dev/null && break
    # a launch that lost the Vulkan surface dies in its first seconds (the args file is still there): once more
    if (( RELAUNCHED == 0 )) && RA test -f files/qa_args.txt 2>/dev/null; then
      echo "… the first launch died (no surface?); launching again"; RELAUNCHED=1; sleep 3; launch; WAITED=0; continue
    fi
    echo "✗ the app is not running (crashed?); check logcat"; exit 1
  fi
done
sleep 2
RA cat files/qa/perf.json > "$OUT/perf.json"
for f in $(RA ls files/qa 2>/dev/null | tr -d '\r' | grep '^perf_.*\.png$'); do RA cat "files/qa/$f" > "$OUT/$f"; done
echo "✓ pulled to $OUT"
ls "$OUT"
