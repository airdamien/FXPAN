#!/bin/sh
# Same restore as the desktop undo script.
set -eu
DESK="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
UNDO="$DESK/undo-wifi-lock.sh"
if [ ! -x "$UNDO" ]; then
    echo "no desktop undo script at $UNDO" >&2
    exit 1
fi
exec "$UNDO"
