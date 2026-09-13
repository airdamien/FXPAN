#!/bin/sh
# Wire autostart + Desktop launcher for the D12600 Chromium kiosk.
# Run on the Pi as the desktop user (airdamien).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run-kiosk.sh"
DESK="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
AUTO="$HOME/.config/autostart"
APPS="$HOME/.local/share/applications"
AUTO_NAME="duals-kiosk.desktop"
DESK_NAME="D12600.desktop"

chmod +x "$HERE/run-kiosk.sh" "$HERE/ensure-labwc-touch.sh" "$HERE/install.sh"
mkdir -p "$DESK" "$AUTO" "$APPS" "$HOME/.config/labwc"

write_desktop() {
    dest="$1"
    cat > "$dest" <<EOF
[Desktop Entry]
Type=Application
Name=D12600
Comment=D12600 field controls fullscreen
Exec=$RUN
Path=$HERE
Icon=camera-photo
Terminal=false
Categories=Photography;Utility;
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF
    chmod +x "$dest"
}

write_desktop "$AUTO/$AUTO_NAME"
write_desktop "$DESK/$DESK_NAME"
write_desktop "$APPS/$AUTO_NAME"
rm -f "$DESK/duals-kiosk.desktop" "$DESK/Duals Kiosk.desktop"

if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
    gio set "$DESK/$DESK_NAME" metadata::trusted true 2>/dev/null || true
fi

"$HERE/ensure-labwc-touch.sh" || true
sudo raspi-config nonint do_blanking 1 >/dev/null 2>&1 || true

echo "autostart  $AUTO/$AUTO_NAME"
echo "desktop    $DESK/$DESK_NAME"
echo "tap D12600 on the desktop to start; SET Desktop leaves it"
