#!/usr/bin/env bash
# Ping the Mini D1, or fire it.
#
#   ./test.sh
#   ./test.sh scan
#   ./test.sh fire
#   ./test.sh fire 1200
#
# The first run makes esp32_d1/.venv and installs bleak.

set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
venv=$root/.venv
py=$venv/bin/python

if [[ ! -x "$py" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet bleak
fi

exec "$py" "$root/test_ble.py" "$@"
