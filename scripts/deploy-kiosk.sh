#!/usr/bin/env bash
# Push cam/ to the Pi. If the kiosk loop is up, restart web.py + Chromium.
#   ./scripts/deploy-kiosk.sh
#   ./scripts/deploy-kiosk.sh airdamien@192.0.2.10
#   ./scripts/deploy-kiosk.sh airdamien@192.0.2.10 --web-only   # skip Chromium bounce
#   ./scripts/deploy-kiosk.sh airdamien@192.0.2.10 --no-restart
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-airdamien@192.0.2.10}"
shift || true
RESTART=1
BOUNCE=full
for arg in "$@"; do
  case "$arg" in
    --no-restart) RESTART=0 ;;
    --web-only) BOUNCE=web ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

MUX="${HOME}/.cache/nikonduals-deploy"
mkdir -p "$MUX"
HOST="${TARGET#*@}"
CONTROL="${MUX}/control-${HOST}"
SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
  -o ControlMaster=auto
  -o "ControlPath=${CONTROL}"
  -o ControlPersist=300
)
ssh_mux() { ssh "${SSH_OPTS[@]}" "$@"; }
RSYNC_RSH="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o ControlMaster=auto -o ControlPath=${CONTROL} -o ControlPersist=300"

t0=$SECONDS
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
echo "    rsync cam ${SECONDS - t0}s"

t1=$SECONDS
echo "==> rsync logos/fxpan.svg → $TARGET:~/nikonduals/logos/"
ssh_mux "$TARGET" 'mkdir -p ~/nikonduals/logos'
rsync -az -e "$RSYNC_RSH" \
  "$ROOT/logos/fxpan.svg" "$TARGET:~/nikonduals/logos/fxpan.svg"
echo "    logos ${SECONDS - t1}s"

if [[ $RESTART -eq 1 ]]; then
  t2=$SECONDS
  if [[ $BOUNCE == web ]]; then
    echo "==> bounce web.py only (Chromium stays up)"
    BOUNCE_SH=~/nikonduals/cam/kiosk/bounce-web.sh
  else
    echo "==> bounce web.py + Chromium"
    BOUNCE_SH=~/nikonduals/cam/kiosk/bounce.sh
  fi
  ssh_mux "$TARGET" "
    chmod +x ~/nikonduals/cam/kiosk/*.sh
    if pgrep -f '/cam/kiosk/run-kiosk.sh' >/dev/null; then
      bash $BOUNCE_SH
    else
      echo '(kiosk loop not running)'
    fi
  "
  echo "    bounce ${SECONDS - t2}s"
else
  echo "==> skipped restart (--no-restart)"
  ssh_mux "$TARGET" 'chmod +x ~/nikonduals/cam/kiosk/*.sh' || true
fi

ssh_mux -O exit "$TARGET" 2>/dev/null || true
echo "==> done in ${SECONDS - t0}s"
