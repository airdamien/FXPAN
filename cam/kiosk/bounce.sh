#!/bin/sh
# Kill only the kiosk Chromium. run-kiosk.sh respawns it.
pkill -f -- --class=duals-kiosk-chromium || true
echo bounced
