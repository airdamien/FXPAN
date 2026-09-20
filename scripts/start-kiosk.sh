#!/bin/sh
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DISPLAY="${DISPLAY:-:0}"
LOGDIR="${HOME}/.local/share/duals"
RUN="${HOME}/nikonduals/cam/kiosk/run-kiosk.sh"
mkdir -p "$LOGDIR"
if pgrep -x run-kiosk.sh >/dev/null 2>&1; then
    echo "kiosk loop already running"
    exit 0
fi
nohup "$RUN" >> "$LOGDIR/kiosk.log" 2>&1 &
echo "started kiosk pid=$!"
