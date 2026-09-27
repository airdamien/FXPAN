#!/bin/sh
# Restart web.py (new APIs) and Chromium. run-kiosk.sh respawns both.
CAM="$(cd "$(dirname "$0")/.." && pwd)"
pkill -f -- "$CAM/web.py" || true
pkill -f -- "$CAM/fxos/serve.py" || true
pkill -x gphoto2 || true
pkill -f -- --class=duals-kiosk-chromium || true
pkill -f -- --user-data-dir="${HOME}/.config/duals-kiosk-chromium" || true
echo bounced
