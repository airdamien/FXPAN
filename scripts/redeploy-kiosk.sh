#!/usr/bin/env bash
# Push cam/ to the kiosk Pi and restart web.py + Chromium.
#   ./scripts/redeploy-kiosk.sh
#   ./scripts/redeploy-kiosk.sh user@pi
#   ./scripts/redeploy-kiosk.sh user@pi --web-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=pi-target.sh
source "$ROOT/scripts/pi-target.sh"
if [[ $# -gt 0 && "$1" != -* ]]; then
  TARGET="$1"
  shift
else
  TARGET="$(pi_target)"
fi

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
echo "==> wait for FXPAN OS :8790"
ssh "${SSH_OPTS[@]}" "$TARGET" '
  ok=0
  i=0
  while [ "$i" -lt 40 ]; do
    if curl -sf -o /dev/null --connect-timeout 1 http://127.0.0.1:8790/fxos/api/state; then
      ok=1
      break
    fi
    i=$((i + 1))
    sleep 0.25
  done
  if [ "$ok" -ne 1 ]; then
    echo "FXPAN OS did not come back on 8790" >&2
    exit 1
  fi
  if curl -sf -o /dev/null --connect-timeout 1 http://127.0.0.1:8787/api/health; then
    echo "web.py is listening on 8787" >&2
  else
    echo "web.py is not running"
  fi
  curl -sS http://127.0.0.1:8790/fxos/api/state | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(\"fxos\", (d.get(\"server\") or {}).get(\"mode\"), (d.get(\"server\") or {}).get(\"version\"))
"
'
ssh "${SSH_OPTS[@]}" -O exit "$TARGET" 2>/dev/null || true
echo "==> kiosk up ($((SECONDS - t0))s wait)"
