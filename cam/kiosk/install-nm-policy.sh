#!/bin/sh
# Install the NetworkManager polkit rule so the kiosk can scan, join, and
# start a hotspot. Needs sudo once.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="/etc/polkit-1/rules.d/50-fxpan-nm.rules"
if [ "$(id -u)" -eq 0 ]; then
    cp "$HERE/50-fxpan-nm.rules" "$DEST"
    chmod 644 "$DEST"
else
    sudo -n cp "$HERE/50-fxpan-nm.rules" "$DEST"
    sudo -n chmod 644 "$DEST"
fi
echo "polkit  $DEST"
