#!/bin/bash
# Run on the Zero W, from this directory: sudo ./install.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "run as root: sudo ./install.sh" >&2
    exit 1
fi

here="$(cd "$(dirname "$0")" && pwd)"
boot=""
for candidate in /boot/firmware /boot; do
    if [[ -f "$candidate/cmdline.txt" && -f "$candidate/config.txt" ]]; then
        boot="$candidate"
        break
    fi
done
if [[ -z "$boot" ]]; then
    echo "cannot find config.txt and cmdline.txt" >&2
    exit 1
fi

if ! grep -q '^dtoverlay=dwc2' "$boot/config.txt"; then
    printf '\n# FXPAN USB gadget\ndtoverlay=dwc2,dr_mode=peripheral\n' >> "$boot/config.txt"
fi

if ! grep -q 'modules-load=dwc2' "$boot/cmdline.txt"; then
    # cmdline.txt is one line. Keep it that way.
    sed -i 's/[[:space:]]*$/ modules-load=dwc2/' "$boot/cmdline.txt"
fi

apt-get update
apt-get install -y python3-libgpiod dnsmasq
systemctl disable --now dnsmasq.service 2>/dev/null || true

install -d /etc/fxpan /usr/local/sbin /etc/NetworkManager/conf.d
install -m 0755 "$here/fxpan-gadget.sh" /usr/local/sbin/fxpan-gadget
install -m 0755 "$here/fxpan-gpio.py" /usr/local/sbin/fxpan-gpio
install -m 0644 "$here/dnsmasq.conf" /etc/fxpan/dnsmasq.conf
install -m 0644 "$here/nm-unmanaged.conf" /etc/NetworkManager/conf.d/fxpan-usb.conf
install -m 0644 "$here/fxpan-gadget.service" /etc/systemd/system/fxpan-gadget.service
install -m 0644 "$here/fxpan-dhcp.service" /etc/systemd/system/fxpan-dhcp.service
install -m 0644 "$here/fxpan-gpio.service" /etc/systemd/system/fxpan-gpio.service

if command -v rfkill >/dev/null; then
    rfkill block wifi || true
fi

systemctl daemon-reload
systemctl enable fxpan-gadget.service fxpan-dhcp.service fxpan-gpio.service
if systemctl is-active --quiet NetworkManager; then
    systemctl reload NetworkManager || true
fi

echo "installed. reboot so the USB port comes up as the gadget: sudo reboot"
