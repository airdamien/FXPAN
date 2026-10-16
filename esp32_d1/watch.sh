#!/usr/bin/env bash
# Fire the Mini D1 slowly so the shutter-board LEDs can be watched.
#
#   ./watch.sh
#   ./watch.sh 4000
#
# Cameras stay unplugged. Focus LEDs light, then the shutter LEDs join them.

set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
venv=$root/.venv
py=$venv/bin/python

if [[ ! -x "$py" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet bleak
fi

exec "$py" "$root/watch.py" "$@"
