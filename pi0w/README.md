# Pi Zero W GPIO trigger

The trigger board plugs onto the Zero W. The iPad is the USB host and powers the Zero through the data port. The Zero appears as a USB ethernet gadget. FXPAN will send one line to `10.55.0.1` port `2323`, and the Zero pulses the 10-pin jacks.

A D800 ignores the 10-pin remote while USB is claimed. The iPad has to end live view and close both camera sessions, wait, send `FIRE`, wait for `OK`, then open the sessions again and download.

This directory is the Zero side only. The iPad app does not send `FIRE` yet.

## Hardware

The Zero W pinout matches the trigger board.

| BCM | Physical pin | Net |
|-----|--------------|-----|
| 20 | 38 | Focus, J1 and J2 while JP1 pads 1–2 are bridged |
| 21 | 40 | Shutter, J1 and J2 while JP2 pads 1–2 are bridged |
| 26 | 37 | J2 focus, only after JP1 is cut and pads 2–3 are bridged |
| 19 | 35 | J2 shutter, only after JP2 is cut and pads 2–3 are bridged |

If the Zero shows bare holes, solder a 2×20 male header with the pins pointing up. The board’s socket plugs onto that header. The board is Pi 4 sized, so it overhangs the Zero and the four screw holes do not line up. Leave it on the header. Do not force those screws.

Use the micro-USB port labeled **USB**, the data port next to the HDMI jack. The port marked **PWR** is power only. The iPad supplies power on the data port. Cable is USB-C to micro-USB, and it has to carry data.

## Flash

Use Raspberry Pi Imager and **Raspberry Pi OS Lite, 32-bit**. The Zero W is ARMv6. A 64-bit image will not boot.

In Imager’s settings, set the hostname to `fxpan-gpio`, create the user, and enable SSH. Join Wi-Fi for this setup only. Wi-Fi comes off after the gadget is working.

Boot, SSH in, and copy this directory onto the Zero:

```bash
scp -r pi0w fxpan-gpio.local:
ssh fxpan-gpio.local
cd pi0w
sudo ./install.sh
sudo reboot
```

`install.sh` adds `dtoverlay=dwc2,dr_mode=peripheral` and `modules-load=dwc2`, installs the gadget and the shutter service, and turns Wi-Fi off.

## After reboot

The USB data port is now a network gadget, address `10.55.0.1/24`. The Zero hands the host `10.55.0.10`–`10.55.0.20` by DHCP. Plug it into a Mac first and check:

```bash
ping 10.55.0.1
nc 10.55.0.1 2323
```

Then type:

```text
PING
FIRE
FIRE 1000
```

`PING` answers `OK`. `FIRE` is the normal release: focus for 100 ms, then shutter for 300 ms. `FIRE 1000` holds the shutter for 1000 ms, which is the bulb path. The hold is capped at 120 seconds. Pins drop before the reply, including when the client hangs up mid-pulse.

```text
OK
OK focus_ms=100 shutter_ms=300
OK focus_ms=100 shutter_ms=1000
```

Then move the same cable to the iPad. The iPad should get a `10.55.0.x` address from the Zero. The command to send, once the app does it, is the same line to `10.55.0.1:2323`.

## What got installed

| On the Zero | Source |
|-------------|--------|
| `/usr/local/sbin/fxpan-gadget` | `fxpan-gadget.sh` |
| `/usr/local/sbin/fxpan-gpio` | `fxpan-gpio.py` |
| `/etc/systemd/system/fxpan-gadget.service` | `fxpan-gadget.service` |
| `/etc/systemd/system/fxpan-dhcp.service` | `fxpan-dhcp.service` |
| `/etc/systemd/system/fxpan-gpio.service` | `fxpan-gpio.service` |
| `/etc/fxpan/dnsmasq.conf` | `dnsmasq.conf` |
| `/etc/NetworkManager/conf.d/fxpan-usb.conf` | `nm-unmanaged.conf` |
| `dtoverlay=dwc2,dr_mode=peripheral` | appended to `config.txt` |
| `modules-load=dwc2` | appended to `cmdline.txt` |

Logs: `journalctl -u fxpan-gadget -u fxpan-dhcp -u fxpan-gpio`

The socket listens on `10.55.0.1` only, so it is not open on Wi-Fi. There is no password. The link is the USB cable.
