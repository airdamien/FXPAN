#!/usr/bin/env bash
# Compile and flash the Mini D1. Pass the serial port, or let it pick one.
#
#   ./flash.sh
#   ./flash.sh /dev/cu.usbserial-10
#
# Needs arduino-cli and the esp32 core. The first run installs the core.
# If the upload stalls, hold BOOT, tap RST, release BOOT, and run it again.

set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
sketch=$root/firmware/fxpan_d1
port=${1:-}
# 921600 makes this Mac drop the port mid-write (termios errno 22).
# QIO is the core default, and this Mini D1's flash rejects it: the chip
# reboots forever at "flash_ret == ESP_OK" and never advertises.
speed=${UPLOAD_SPEED:-115200}
fqbn=${FQBN:-"esp32:esp32:esp32:FlashMode=dio,UploadSpeed=${speed}"}

if ! command -v arduino-cli >/dev/null; then
  echo "arduino-cli is not on PATH. Install it from https://arduino.github.io/arduino-cli/" >&2
  exit 1
fi

if ! arduino-cli core list | awk '{print $1}' | grep -qx 'esp32:esp32'; then
  arduino-cli core update-index
  arduino-cli core install esp32:esp32
fi

pick_port() {
  local line
  line=$(arduino-cli board list | awk '
    /usbserial|wchusbserial|SLAB_USBtoUART|usbmodem/ { print $1; exit }
  ')
  if [[ -z "$line" ]]; then
    echo "No ESP32 serial port found. Plug in the Mini D1 and pass the port." >&2
    arduino-cli board list >&2 || true
    exit 1
  fi
  printf '%s' "$line"
}

if [[ -z "$port" ]]; then
  port=$(pick_port)
fi

echo "compile $fqbn"
arduino-cli compile --fqbn "$fqbn" "$sketch"
echo "upload $port"
arduino-cli upload -p "$port" --fqbn "$fqbn" "$sketch"
echo "FXPAN-D1 is advertising. Focus is GPIO 32 (pin 38), shutter is GPIO 27 (pin 40), both idle low."
