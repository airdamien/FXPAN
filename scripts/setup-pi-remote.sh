#!/usr/bin/env bash
# From the Mac: rsync cam/ to a Pi and install the D12600 kiosk.
#   ./scripts/setup-pi-remote.sh user@pi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=pi-target.sh
source "$ROOT/scripts/pi-target.sh"
if [[ $# -gt 0 && "$1" != -* ]]; then
  TARGET="$1"
  shift
else
  TARGET="$(pi_target)"
fi
START=1
for arg in "$@"; do
  case "$arg" in
    --no-start) START=0 ;;
    -h|--help)
      sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

SSH=(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
RSYNC_RSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"

echo "==> rsync cam/ → $TARGET:~/nikonduals/cam/"
"${SSH[@]}" "$TARGET" 'mkdir -p ~/nikonduals/cam'
rsync -az \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude 'captures/' \
  --exclude '.venv/' \
  --exclude 'cameras.json' \
  --exclude 'gpio.json' \
  -e "$RSYNC_RSH" \
  "$ROOT/cam/" "$TARGET:~/nikonduals/cam/"

echo "==> apt gphoto2 + ImageMagick + Hugin"
"${SSH[@]}" "$TARGET" 'sudo DEBIAN_FRONTEND=noninteractive apt-get update -y && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gphoto2 imagemagick enblend'
echo "==> OpenStitching venv (PANO Open)"
"${SSH[@]}" "$TARGET" 'chmod +x ~/nikonduals/cam/kiosk/install-openstitching.sh && bash ~/nikonduals/cam/kiosk/install-openstitching.sh'

echo "==> install autostart + Desktop launcher"
"${SSH[@]}" "$TARGET" 'bash ~/nikonduals/cam/kiosk/install.sh'

if [[ $START -eq 1 ]]; then
  echo "==> start kiosk"
  "${SSH[@]}" "$TARGET" 'export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 DISPLAY=:0
    mkdir -p ~/.local/share/duals
    nohup ~/nikonduals/cam/kiosk/run-kiosk.sh >> ~/.local/share/duals/kiosk.log 2>&1 &'
fi

echo "==> done  $TARGET"
echo "    USB tab Desktop → labwc desktop"
echo "    D12600 on the Desktop → kiosk again"
echo "    login autostarts the kiosk"
