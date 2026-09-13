#!/usr/bin/env bash
# Push cam/ to the kiosk Pi and restart web.py + Chromium.
#   ./scripts/redeploy-kiosk.sh
#   ./scripts/redeploy-kiosk.sh airdamien@192.0.2.10
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-airdamien@192.0.2.10}"

"$ROOT/scripts/deploy-kiosk.sh" "$TARGET"

echo "==> wait for http://127.0.0.1:8787/api/meta"
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "$TARGET" '
  ok=0
  i=0
  while [ "$i" -lt 40 ]; do
    if curl -sf -o /dev/null --connect-timeout 1 http://127.0.0.1:8787/api/meta; then
      ok=1
      break
    fi
    i=$((i + 1))
    sleep 0.25
  done
  if [ "$ok" -ne 1 ]; then
    echo "web.py did not come back on 8787" >&2
    exit 1
  fi
  curl -sS http://127.0.0.1:8787/api/meta | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(\"kiosk\", d.get(\"kiosk\"), \"gpio\", (d.get(\"gpio\") or {}).get(\"available\"))
"
'

echo "==> kiosk up"
