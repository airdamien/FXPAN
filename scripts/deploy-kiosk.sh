#!/usr/bin/env bash
# Push cam/ to the Pi. If the kiosk loop is up, restart web.py + Chromium.
#   ./scripts/deploy-kiosk.sh
#   ./scripts/deploy-kiosk.sh airdamien@192.0.2.10 --no-restart
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-airdamien@192.0.2.10}"
shift || true
RESTART=1
for arg in "$@"; do
  case "$arg" in
    --no-restart) RESTART=0 ;;
    -h|--help)
      sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
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
rsync -az \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude 'captures/' \
  --exclude '.venv/' \
  --exclude 'cameras.json' \
  --exclude 'gpio.json' \
  --exclude 'settings.json' \
  --exclude 'wifi.json' \
  -e "$RSYNC_RSH" \
  "$ROOT/cam/" "$TARGET:~/nikonduals/cam/"

"${SSH[@]}" "$TARGET" 'chmod +x ~/nikonduals/cam/kiosk/*.sh'

if [[ $RESTART -eq 1 ]]; then
  echo "==> bounce web.py + Chromium if the kiosk loop is running"
  "${SSH[@]}" "$TARGET" \
    'if pgrep -f "/cam/kiosk/run-kiosk.sh" >/dev/null; then bash ~/nikonduals/cam/kiosk/bounce.sh; else echo "(kiosk loop not running)"; fi'
else
  echo "==> skipped restart (--no-restart)"
fi

echo "==> done"
