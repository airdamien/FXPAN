# Mini D1 BLE trigger

A Mini D1 ESP32 stands in for a second Pi Zero. It cannot be the USB ethernet gadget the phone uses for the first rig. It advertises a BLE serial port and pulses a trigger board with the same `PING` / `FIRE` lines the Zero answers on `10.55.0.1:2323`.

The iOS change is specified in [IOS.md](IOS.md). This directory does not modify the app.

## Wire

[wiring.svg](wiring.svg). Three jumpers into the trigger board's 2×20 socket:

| Mini D1 | Trigger socket | Net |
|---------|----------------|-----|
| GPIO 32 | pin 38 | Focus, active high |
| GPIO 27 | pin 40 | Shutter, active high |
| GND | pin 39 | Opto LED return |

Pin 1 is the square pad. Pins 39 and 40 are the pair at the far end. Pin 38 is beside pin 40. Leave the board jumpers on the 1–2 bridge so both jacks follow these two pins. Do not connect the ESP32 ground to a TRS sleeve, and do not feed the socket from the Mini D1 5 V pin. The Mini D1's own USB cable powers it.

GPIO 32 and 27 are the numbers in the firmware. Clones disagree on the D labels, so count from the GPIO number.

## Flash

```bash
cd esp32_d1
./flash.sh
./flash.sh /dev/cu.usbserial-10
```

`flash.sh` uses `arduino-cli` and the `esp32:esp32:esp32` core. The first run installs that core. If the upload never starts, hold BOOT, tap RST, release BOOT, and run it again.

After a successful flash the board advertises as **FXPAN-D1**. Both pins sit low until a `FIRE` line arrives.

## Test from this machine

```bash
cd esp32_d1
./test.sh            # PING, pins stay low
./test.sh scan       # who is advertising
./test.sh fire       # focus 100 ms, shutter 300 ms
./test.sh fire 1200  # shutter held 1200 ms
```

The first run creates `.venv` and installs bleak. macOS has to allow Bluetooth for the terminal. A good ping prints `OK`. `fire` moves the pins, so leave the camera unplugged until the ping works.

## Watch the LEDs

`./test.sh fire` is too short to see. This holds the shutter LEDs on for 3 seconds. Cameras stay unplugged.

```bash
./watch.sh
./watch.sh 4000
```

Focus LEDs D1 and D3 light first. A tenth of a second later shutter LEDs D2 and D4 join them. All four go out when the hold ends. The script prints `OK` when the Mini D1 finishes the pulse.

## Lines

Nordic UART. The phone writes to the RX characteristic and subscribes to TX notifications.

| UUID | Role |
|------|------|
| `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | Service |
| `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | RX, phone to board |
| `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | TX, board to phone, notify |

Each command ends in `\n`. The reply ends in `\n`.

| In | Out | Pins |
|----|-----|------|
| `PING` | `OK` | unchanged |
| `FIRE` | `OK focus_ms=100 shutter_ms=300` | focus 100 ms, shutter 300 ms |
| `FIRE 1200` | `OK focus_ms=100 shutter_ms=1200` | focus 100 ms, shutter 1200 ms |

Anything else returns `ERR ...`. Shutter time has to be 1 through 120000 ms. Focus goes high first, shutter joins it, then both drop, and only then does `OK` go out. That matches `pi0w/fxpan-gpio.py`.
