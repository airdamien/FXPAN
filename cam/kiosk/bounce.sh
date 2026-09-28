#!/bin/sh
# Stop web.py, FXPAN OS, and Chromium. The kiosk loop brings FXPAN OS back.
# It does not start web.py.
CAM="$(cd "$(dirname "$0")/.." && pwd)"
pkill -f -- "$CAM/web.py" || true
pkill -f -- "$CAM/fxos/serve.py" || true
pkill -x gphoto2 || true
pkill -f -- --class=duals-kiosk-chromium || true
pkill -f -- --user-data-dir="${HOME}/.config/duals-kiosk-chromium" || true
echo bounced
