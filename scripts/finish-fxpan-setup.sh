#!/usr/bin/env bash
# Run on fxpan (needs sudo once): bash ~/nikonduals/scripts/finish-fxpan-setup.sh
set -euo pipefail
CAM="$HOME/nikonduals/cam"

echo "==> apt packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  gphoto2 imagemagick enblend \
  python3-venv python3-pip python3-numpy python3-opencv

echo "==> OpenStitching venv"
bash "$CAM/kiosk/install-openstitching.sh"

echo "==> kiosk autostart + desktop"
bash "$CAM/kiosk/install.sh"

echo "==> start kiosk"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DISPLAY="${DISPLAY:-:0}"
mkdir -p "$HOME/.local/share/duals"
if ! pgrep -x run-kiosk.sh >/dev/null 2>&1; then
  nohup "$CAM/kiosk/run-kiosk.sh" >> "$HOME/.local/share/duals/kiosk.log" 2>&1 &
fi

echo "==> captures"
python3 -c "import sys; sys.path.insert(0,'$CAM'); import pano; print(len(pano.list_pairs()), 'pairs')"

echo "==> done  http://$(hostname -I | awk '{print $1}'):8787/"
