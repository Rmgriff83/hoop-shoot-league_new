#!/bin/zsh
# Capture one trailer v2 shot (docs/TRAILER.md → v2): tools/trailer/capture.sh with the
# appstore layout (1440x3120 = 2x the 720x1560 layout), the iPhone 16's insets
# (--qa-safe-top=108 --qa-safe-bottom=62, so the HUD lines up with Ross's recordings)
# and the clips under marketing/trailer/v2/clips/.
# Usage: tools/trailer/v2/capture.sh <shot name> [extra game args…]
set -eo pipefail
PROJ="$(cd "$(dirname "$0")/../../.." && pwd)"
SHOT="$PROJ/tools/trailer/v2/shots/$1.json"
[[ -f "$SHOT" ]] || { echo "usage: capture.sh <shot name> (tools/trailer/v2/shots/<name>.json)"; exit 1; }
shift
TRAILER_OUT="$PROJ/marketing/trailer/v2/clips" TRAILER_SAFE_TOP=108 TRAILER_SAFE_BOTTOM=62 \
  "$PROJ/tools/trailer/capture.sh" "$SHOT" appstore "$@"
