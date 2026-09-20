#!/bin/sh
# Stash PiPan kiosk on panoscan Pi. Run on the Pi as airdamien.
set -eu

STASH="${HOME}/stash/pipan-$(date +%Y%m%d)"
mkdir -p "$STASH"

echo "==> stop PiPan"
for pid in $(pgrep -x runpan.sh 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
for pid in $(pgrep -f '[/]pipan[.]py' 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
sleep 1
if pgrep -x runpan.sh >/dev/null 2>&1 || pgrep -f '[/]pipan[.]py' >/dev/null 2>&1; then
    echo "PiPan still running" >&2
    pgrep -af runpan || true
    pgrep -af '[/]pipan[.]py' || true
    exit 1
fi

echo "==> disable systemd"
sudo systemctl stop pipan-usb-sync.timer pipan-gadget.service pipan-usb-sync.service 2>/dev/null || true
sudo systemctl disable pipan-usb-sync.timer pipan-gadget.service 2>/dev/null || true

echo "==> stash autostart"
if [ -f "${HOME}/.config/autostart/pipan.desktop" ]; then
    mv "${HOME}/.config/autostart/pipan.desktop" "$STASH/"
fi

echo "==> stash ~/pipan"
if [ -d "${HOME}/pipan" ]; then
    mv "${HOME}/pipan" "$STASH/pipan"
fi

cat > "$STASH/README.txt" <<EOF
PiPan kiosk stack stashed $(date -Is) for nikonduals migration.

Restore:
  mv $STASH/pipan ~/pipan
  mv $STASH/pipan.desktop ~/.config/autostart/
  sudo systemctl enable --now pipan-usb-sync.timer
  log out/in or reboot
EOF

echo "==> stashed to $STASH"
ls -la "$STASH"
