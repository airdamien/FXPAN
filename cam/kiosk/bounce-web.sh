#!/bin/sh
# Restart web.py + FXPAN OS — leave Chromium up (fast deploy for cam/*.py / fxos).
CAM="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="${HOME}/.local/share/duals"
WEB_PORT=8787
FXOS_PORT=8790
pkill -f -- "$CAM/web.py" || true
pkill -f -- "$CAM/fxos/serve.py" || true
pkill -x gphoto2 || true
sleep 0.2
if [ -x "$CAM/.venv/bin/python3" ]; then
    PY="$CAM/.venv/bin/python3"
else
    PY=python3
fi
mkdir -p "$LOGDIR"
DUALS_KIOSK=1 "$PY" "$CAM/web.py" >> "$LOGDIR/web.log" 2>&1 &
i=0
while [ "$i" -lt 40 ]; do
    if curl -sf -o /dev/null --connect-timeout 1 "http://127.0.0.1:${WEB_PORT}/api/health"; then
        break
    fi
    i=$((i + 1))
    sleep 0.25
done
if ! curl -sf -o /dev/null --connect-timeout 1 "http://127.0.0.1:${WEB_PORT}/api/health"; then
    echo "web.py did not listen on ${WEB_PORT}" >&2
    exit 1
fi
if curl -sf -o /dev/null --connect-timeout 1 "http://127.0.0.1:${FXOS_PORT}/fxos/api/state"; then
    echo bounced-web
    exit 0
fi
"$PY" "$CAM/fxos/serve.py" --host 0.0.0.0 --proxy "http://127.0.0.1:${WEB_PORT}" \
    >> "$LOGDIR/fxos.log" 2>&1 &
i=0
while [ "$i" -lt 40 ]; do
    if curl -sf -o /dev/null --connect-timeout 1 "http://127.0.0.1:${FXOS_PORT}/fxos/api/state"; then
        echo bounced-web
        exit 0
    fi
    i=$((i + 1))
    sleep 0.25
done
echo "fxos serve.py did not listen on ${FXOS_PORT}" >&2
exit 1
