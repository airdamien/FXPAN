#!/bin/bash
# USB CDC-NCM gadget. The iPad is the host. usb0 is 10.55.0.1/24.
set -euo pipefail

G=/sys/kernel/config/usb_gadget/fxpan

stop_gadget() {
    if [[ -d "$G" ]]; then
        if [[ -f "$G/UDC" ]]; then
            echo "" > "$G/UDC" || true
        fi
        rm -f "$G/configs/c.1/ncm.usb0"
        rmdir "$G/configs/c.1/strings/0x409" 2>/dev/null || true
        rmdir "$G/configs/c.1" 2>/dev/null || true
        rmdir "$G/functions/ncm.usb0" 2>/dev/null || true
        rmdir "$G/strings/0x409" 2>/dev/null || true
        rmdir "$G" 2>/dev/null || true
    fi
    if ip link show usb0 >/dev/null 2>&1; then
        ip link set usb0 down || true
        ip addr flush dev usb0 || true
    fi
}

start_gadget() {
    modprobe libcomposite
    stop_gadget
    mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/ncm.usb0"
    echo 0x1d6b > "$G/idVendor"
    echo 0x0105 > "$G/idProduct"
    echo 0x0200 > "$G/bcdUSB"
    echo 0x0100 > "$G/bcdDevice"
    echo 0x02 > "$G/bDeviceClass"
    echo 0x00 > "$G/bDeviceSubClass"
    echo 0x00 > "$G/bDeviceProtocol"
    echo "fxpan-gpio" > "$G/strings/0x409/serialnumber"
    echo "FXPAN" > "$G/strings/0x409/manufacturer"
    echo "GPIO trigger" > "$G/strings/0x409/product"
    echo "NCM" > "$G/configs/c.1/strings/0x409/configuration"
    echo 250 > "$G/configs/c.1/MaxPower"
    ln -s "$G/functions/ncm.usb0" "$G/configs/c.1/"
    udc="$(ls /sys/class/udc | head -n 1)"
    if [[ -z "$udc" ]]; then
        echo "no UDC — dtoverlay=dwc2 is missing or this is not the USB data port" >&2
        exit 1
    fi
    echo "$udc" > "$G/UDC"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ip link show usb0 >/dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done
    ip link show usb0 >/dev/null
    ip addr flush dev usb0
    ip addr add 10.55.0.1/24 dev usb0
    ip link set usb0 up
}

case "${1:-start}" in
    start) start_gadget ;;
    stop) stop_gadget ;;
    *) echo "usage: fxpan-gadget start|stop" >&2; exit 1 ;;
esac
