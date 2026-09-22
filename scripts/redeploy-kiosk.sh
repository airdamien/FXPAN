#!/usr/bin/env bash
# Push cam/ to the kiosk Pi and restart web.py + Chromium.
#   ./scripts/redeploy-kiosk.sh
#   ./scripts/redeploy-kiosk.sh airdamien@192.0.2.10
#   ./scripts/redeploy-kiosk.sh airdamien@192.0.2.10 --web-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-airdamien@192.0.2.10}"
shift || true

"$ROOT/scripts/deploy-kiosk.sh" "$TARGET" "$@"

MUX="${HOME}/.cache/nikonduals-deploy"
HOST="${TARGET#*@}"
CONTROL="${MUX}/control-${HOST}"
SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -o ControlMaster=auto
  -o "ControlPath=${CONTROL}"
  -o ControlPersist=300
)

t0=$SECONDS
echo "==> wait for http://127.0.0.1:8787/api/health"
ssh "${SSH_OPTS[@]}" "$TARGET" '
  ok=0
  i=0
  while [ "$i" -lt 40 ]; do
    if curl -sf -o /dev/null --connect-timeout 1 http://127.0.0.1:8787/api/health; then
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
ssh "${SSH_OPTS[@]}" -O exit "$TARGET" 2>/dev/null || true
echo "==> kiosk up (${SECONDS - t0}s wait)"
