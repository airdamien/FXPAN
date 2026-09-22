#!/bin/sh
# Restart web.py only — leave Chromium up (fast deploy for cam/*.py / *.html).
CAM="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="${HOME}/.local/share/duals"
pkill -f -- "$CAM/web.py" || true
pkill -x gphoto2 || true
sleep 0.2
if curl -sf -o /dev/null --connect-timeout 1 http://127.0.0.1:8787/api/health; then
    echo bounced-web
    exit 0
fi
if [ -x "$CAM/.venv/bin/python3" ]; then
    PY="$CAM/.venv/bin/python3"
else
    PY=python3
fi
mkdir -p "$LOGDIR"
DUALS_KIOSK=1 "$PY" "$CAM/web.py" >> "$LOGDIR/web.log" 2>&1 &
i=0
while [ "$i" -lt 40 ]; do
    if curl -sf -o /dev/null --connect-timeout 1 http://127.0.0.1:8787/api/health; then
        echo bounced-web
        exit 0
    fi
    i=$((i + 1))
    sleep 0.25
done
echo "web.py did not listen on 8787" >&2
exit 1
