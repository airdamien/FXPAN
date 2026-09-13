#!/bin/sh
set -eu
DESK="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
UNDO="$DESK/undo-ptp-quiet.sh"
if [ ! -x "$UNDO" ]; then
    echo "no desktop undo script at $UNDO" >&2
    exit 1
fi
exec "$UNDO"
