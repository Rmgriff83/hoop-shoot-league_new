#!/bin/zsh
# Capture every shot a cut uses (docs/TRAILER.md → Capture).
# Usage: tools/trailer/capture_all.sh <appstore|social> [--force]
# Skips a shot whose clip is newer than its shot file unless --force.
set -o pipefail
PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
LAYOUT="${1:-appstore}"; FORCE="$2"
cd "$PROJ"
CLIPS=($(python3 -I -c "
import json
e=json.load(open('tools/trailer/edit.json'))
seen=[]
for c in e['cuts'].values():
    if c['layout']=='$LAYOUT':
        for t in c['timeline']:
            if t.get('clip') and t['clip'] not in seen: seen.append(t['clip'])
print(' '.join(seen))"))
FAILED=()
for s in "${CLIPS[@]}"; do
  MOV="marketing/trailer/clips/$LAYOUT/$s.mov"
  if [[ "$FORCE" != "--force" && -f "$MOV" && "$MOV" -nt "tools/trailer/shots/$s.json" ]]; then echo "· $s (captured)"; continue; fi
  tools/trailer/capture.sh "tools/trailer/shots/$s.json" "$LAYOUT" 2>&1 | tail -3 || FAILED+=("$s")
  [[ -f "$MOV" ]] || FAILED+=("$s")
done
echo "failed: ${FAILED[*]:-none}"
