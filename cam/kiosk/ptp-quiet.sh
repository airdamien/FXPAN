#!/bin/sh
# Keep GVFS/MTP from claiming PTP cameras so gphoto2 can own the USB ports.
# Writes a desktop undo that restores the previous masks / udev rule.
set -eu

DESK="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
UNDO="$DESK/undo-ptp-quiet.sh"
DESKTOP="$DESK/Undo-PTP-quiet.desktop"
UDEV="/etc/udev/rules.d/68-duals-ptp.rules"
UNITS="gvfs-gphoto2-volume-monitor.service gvfs-mtp-volume-monitor.service"

mkdir -p "$DESK" "$HOME/.config/systemd/user"

cat > "$UNDO" <<EOF
#!/bin/sh
# Restore GVFS camera monitors and remove the PTP udev pin.
set -eu
for u in $UNITS; do
    systemctl --user unmask "\$u" || true
    systemctl --user start "\$u" || true
done
if [ -f $UDEV ]; then
    sudo -n rm -f $UDEV
    sudo -n udevadm control --reload || true
fi
echo "GVFS/MTP camera monitors are back."
EOF
chmod +x "$UNDO"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Undo PTP quiet
Comment=Let the file manager mount cameras again
Exec=$UNDO
Path=$DESK
Icon=camera-photo
Terminal=true
Categories=Photography;Utility;
StartupNotify=false
EOF
chmod +x "$DESKTOP"

if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
    gio set "$DESKTOP" metadata::trusted true 2>/dev/null || true
    gio set "$UNDO" metadata::trusted true 2>/dev/null || true
fi

for u in $UNITS; do
    systemctl --user mask --now "$u" || true
done
pkill -x -9 gvfsd-gphoto2 gvfsd-mtp 2>/dev/null || true

if sudo -n true 2>/dev/null; then
    sudo -n tee "$UDEV" >/dev/null <<'RULE'
# D12600: PTP still-image USB is for gphoto2, not GVFS / mtp-probe / udisks.
ACTION=="add|bind", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:060101:*", ENV{MTP_NO_PROBE}="1", ENV{ID_GPHOTO}="1", ENV{UDISKS_IGNORE}="1"
ACTION=="add|bind", SUBSYSTEM=="usb", ATTR{idVendor}=="04b0", ENV{MTP_NO_PROBE}="1", ENV{ID_GPHOTO}="1", ENV{UDISKS_IGNORE}="1"
RULE
    sudo -n udevadm control --reload || true
fi

echo "masked $UNITS"
echo "undo    $UNDO"
