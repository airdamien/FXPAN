#!/bin/sh
# Pin the active Wi-Fi profile to the AP we are on so NetworkManager
# stops hopping between radios that share the SSID. Writes an undo
# script on the desktop that restores the previous profile.
set -eu

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/duals"
STATE="$STATE_DIR/wifi-lock.state"
DESK="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
UNDO="$DESK/undo-wifi-lock.sh"
DESKTOP="$DESK/Undo-WiFi-lock.desktop"

dev=$(nmcli -t -e no -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')
if [ -z "$dev" ]; then
    echo "no wifi device" >&2
    exit 1
fi

con=$(nmcli -g GENERAL.CONNECTION device show "$dev")
if [ -z "$con" ] || [ "$con" = "--" ]; then
    echo "wifi is not connected" >&2
    exit 1
fi

uuid=$(nmcli -g connection.uuid connection show "$con")
ssid=$(nmcli -g 802-11-wireless.ssid connection show "$con")
old_bssid=$(nmcli -g 802-11-wireless.bssid connection show "$con" || true)
old_ps=$(nmcli -g 802-11-wireless.powersave connection show "$con" || true)
old_band=$(nmcli -g 802-11-wireless.band connection show "$con" || true)
case "$old_ps" in
    ""|default|--) old_ps=0 ;;
esac
case "$old_bssid" in
    --) old_bssid= ;;
esac
case "$old_band" in
    --) old_band= ;;
esac

bssid=$(nmcli -e no -t -f IN-USE,SSID,BSSID device wifi list | awk -F: -v s="$ssid" '
    $1=="*" && $2==s {
        sub("^\\*:" s ":", "")
        print
        exit
    }')
if [ -z "$bssid" ]; then
    echo "could not read current BSSID for $ssid" >&2
    exit 1
fi

mkdir -p "$STATE_DIR" "$DESK"
if [ ! -f "$STATE" ]; then
    cat > "$STATE" <<EOF
UUID=$uuid
CON=$con
DEV=$dev
OLD_BSSID=$old_bssid
OLD_POWERSAVE=$old_ps
OLD_BAND=$old_band
LOCKED_BSSID=$bssid
EOF
else
    grep -v '^LOCKED_BSSID=' "$STATE" > "$STATE.tmp"
    echo "LOCKED_BSSID=$bssid" >> "$STATE.tmp"
    mv "$STATE.tmp" "$STATE"
fi

# First lock wins for undo values so a second run cannot overwrite the original.
# shellcheck disable=SC1090
. "$STATE"

cat > "$UNDO" <<EOF
#!/bin/sh
# Restore $CON to how it was before pinning $ssid to $LOCKED_BSSID.
set -eu
if ! sudo -n nmcli connection modify uuid "$UUID" \\
    802-11-wireless.bssid '$OLD_BSSID' \\
    802-11-wireless.powersave ${OLD_POWERSAVE:-0} \\
    802-11-wireless.band '$OLD_BAND'
then
    echo "need passwordless sudo for nmcli" >&2
    exit 1
fi
if ! sudo -n nmcli device reapply "$DEV"; then
    sudo -n nmcli connection up uuid "$UUID"
fi
rm -f "$STATE"
echo "Wi-Fi roaming restored for $CON (pre-lock settings)."
EOF
chmod +x "$UNDO"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Undo Wi-Fi lock
Comment=Let $ssid roam between APs again
Exec=$UNDO
Path=$DESK
Icon=network-wireless
Terminal=true
Categories=Network;Utility;
StartupNotify=false
EOF
chmod +x "$DESKTOP"

if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
    gio set "$DESKTOP" metadata::trusted true 2>/dev/null || true
    gio set "$UNDO" metadata::trusted true 2>/dev/null || true
fi

sudo -n nmcli connection modify uuid "$uuid" \
    802-11-wireless.bssid "$bssid" \
    802-11-wireless.powersave 2
if ! sudo -n nmcli device reapply "$dev"; then
    sudo -n nmcli connection up uuid "$uuid"
fi

echo "locked $con ($ssid) to $bssid, powersave off"
echo "undo    $UNDO"
