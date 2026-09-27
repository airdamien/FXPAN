#!/bin/sh
# Wait for labwc, keep the field page in Chromium kiosk. SET Desktop
# writes the stop file and kills Chromium; this loop then exits.
CAM="$(cd "$(dirname "$0")/.." && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DISPLAY="${DISPLAY:-:0}"
export GDK_BACKEND=wayland
STOP="${XDG_RUNTIME_DIR}/duals-kiosk.stop"
LOCK="${XDG_RUNTIME_DIR}/duals-kiosk.lock"
PROFILE="${HOME}/.config/duals-kiosk-chromium"
WEB_PORT=8787
FXOS_PORT=8790
URL="http://127.0.0.1:${FXOS_PORT}/?kiosk=1"
LOGDIR="${HOME}/.local/share/duals"

ONCE=0
for arg in "$@"; do
    if [ "$arg" = "--once" ]; then
        ONCE=1
    fi
done

exec 9>"$LOCK"
if ! flock -n 9; then
    echo "duals kiosk already running" >&2
    exit 0
fi

rm -f "$STOP"

i=0
while [ "$i" -lt 40 ]; do
    for d in wayland-0 wayland-1; do
        if [ -S "$XDG_RUNTIME_DIR/$d" ]; then
            export WAYLAND_DISPLAY="$d"
            break 2
        fi
    done
    if xset q >/dev/null 2>&1; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

xset s off >/dev/null 2>&1
xset s noblank >/dev/null 2>&1
xset -dpms >/dev/null 2>&1

if [ -x "$CAM/.venv/bin/python3" ]; then
    PY="$CAM/.venv/bin/python3"
else
    PY=python3
fi

if command -v chromium >/dev/null 2>&1; then
    CHROME=chromium
elif command -v chromium-browser >/dev/null 2>&1; then
    CHROME=chromium-browser
else
    echo "chromium not found" >&2
    exit 1
fi

web_ok() {
    curl -sf -o /dev/null --connect-timeout 1 "http://127.0.0.1:${WEB_PORT}/api/health"
}

fxos_ok() {
    curl -sf -o /dev/null --connect-timeout 1 "http://127.0.0.1:${FXOS_PORT}/fxos/api/state"
}

ensure_web() {
    mkdir -p "$LOGDIR"
    if ! web_ok; then
        DUALS_KIOSK=1 "$PY" "$CAM/web.py" >> "$LOGDIR/web.log" 2>&1 9>&- &
        j=0
        while [ "$j" -lt 50 ]; do
            if web_ok; then
                break
            fi
            j=$((j + 1))
            sleep 0.2
        done
        if ! web_ok; then
            echo "web.py did not listen on ${WEB_PORT}" >&2
            return 1
        fi
    fi
    if ! fxos_ok; then
        "$PY" "$CAM/fxos/serve.py" --host 0.0.0.0 --proxy "http://127.0.0.1:${WEB_PORT}" \
            >> "$LOGDIR/fxos.log" 2>&1 9>&- &
        j=0
        while [ "$j" -lt 50 ]; do
            if fxos_ok; then
                return 0
            fi
            j=$((j + 1))
            sleep 0.2
        done
        echo "fxos serve.py did not listen on ${FXOS_PORT}" >&2
        return 1
    fi
    return 0
}

# Main window only. The Debian chromium wrapper exits while the browser
# stays up ("Opening in existing browser session"); do not relaunch then.
chrome_main() {
    pgrep -f -- --class=duals-kiosk-chromium
}

start_chrome() {
    mkdir -p "$PROFILE"
    "$CHROME" \
        --user-data-dir="$PROFILE" \
        --class=duals-kiosk-chromium \
        --kiosk \
        --ozone-platform=wayland \
        --noerrdialogs \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --hide-crash-restore-bubble \
        --no-first-run \
        --disable-translate \
        --disable-pinch \
        --overscroll-history-navigation=0 \
        --password-store=basic \
        --check-for-update-interval=31536000 \
        --autoplay-policy=no-user-gesture-required \
        --disable-features=OverlayScrollbar \
        --renderer-process-limit=4 \
        "$URL" 9>&- &
    j=0
    while [ "$j" -lt 40 ]; do
        if chrome_main >/dev/null; then
            return 0
        fi
        j=$((j + 1))
        sleep 0.25
    done
    echo "chromium did not stay up" >&2
    return 1
}

while true; do
    if [ -f "$STOP" ]; then
        exit 0
    fi
    ensure_web || exit 1
    if ! chrome_main >/dev/null; then
        start_chrome || exit 1
    fi
    while chrome_main >/dev/null; do
        if [ -f "$STOP" ]; then
            exit 0
        fi
        sleep 1
    done
    [ "$ONCE" = 1 ] && exit 0
    sleep 1
done
