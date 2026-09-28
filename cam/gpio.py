#!/usr/bin/env python3
"""10-pin release: focus held, then shutter, on both camera jacks.

BCM 20 and 26 are focus (J1, and J2 when JP1 is bridged 2–3).
BCM 21 and 19 are shutter the same way. Live view has to be down
first: a D800 ignores the 10-pin remote while USB is claimed.
"""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

import dual

PIN = 21
PULSE_S = 0.3
FOCUS_LEAD_S = 0.1
# J1 is always 20/21. J2 follows those while the solder jumpers are
# bridged 1–2, and these when they are cut and bridged 2–3.
FOCUS_PINS = (20, 26)
SHUTTER_PINS = (21, 19)
CONSUMER = "nikonduals"
SIM_PATH = Path(__file__).resolve().parent / "gpio.json"


def board_model(path=None):
    paths = (path,) if path is not None else (
        Path("/proc/device-tree/model"),
        Path("/sys/firmware/devicetree/base/model"),
    )
    for item in paths:
        item = Path(item)
        if not item.is_file():
            continue
        return item.read_bytes().split(b"\x00", 1)[0].decode("utf-8", "replace").strip()
    return ""


def on_pi(path=None):
    return "raspberry pi" in board_model(path).lower()


def sim_on():
    if not SIM_PATH.is_file():
        return False
    try:
        return bool(json.loads(SIM_PATH.read_text()).get("sim"))
    except (OSError, json.JSONDecodeError):
        return False


def set_sim(on):
    SIM_PATH.write_text(json.dumps({"sim": bool(on)}) + "\n")
    return snapshot()


def snapshot():
    sim = sim_on()
    pi = on_pi()
    return {
        "available": pi or sim,
        "sim": sim,
        "pi": pi,
        "pin": PIN,
        "pulse_ms": int(round(PULSE_S * 1000)),
        "focus_ms": int(round(FOCUS_LEAD_S * 1000)),
        "focus": list(FOCUS_PINS),
        "shutter": list(SHUTTER_PINS),
    }


def find_chip(devices=Path("/sys/bus/gpio/devices")):
    """RP1 on Pi 5 is gpiochip4; gpiochip0 is the legacy header on many images."""
    ranked = []
    root = Path(devices)
    if root.is_dir():
        for sys in root.glob("gpiochip*"):
            label = ""
            lab = sys / "label"
            if lab.is_file():
                try:
                    label = lab.read_text().strip().lower()
                except OSError:
                    label = ""
            score = 0
            if "pinctrl" in label or "rp1" in label:
                score = 3
            elif label.startswith("bcm") or "brcm" in label:
                score = 2
            num = int(sys.name.replace("gpiochip", "") or "0")
            # Unlabeled Pi 5 images expose many gpiochips; only 4 and 0 carry
            # the 40-pin header. Do not pick the highest chip number by default.
            pref = {4: 2, 0: 1}.get(num, 0)
            ranked.append((score, pref, num, sys.name))
        ranked.sort(reverse=True)
        if ranked:
            return f"/dev/{ranked[0][3]}"
    return "/dev/gpiochip0"


def _pulse(set_level, pulse_s):
    set_level(1)
    try:
        time.sleep(pulse_s)
    finally:
        set_level(0)


def _drive_gpiod(pin, pulse_s):
    import gpiod

    chip = find_chip()
    if hasattr(gpiod, "request_lines"):
        from gpiod.line import Direction, Value

        with gpiod.request_lines(
            chip,
            consumer=CONSUMER,
            config={
                pin: gpiod.LineSettings(
                    direction=Direction.OUTPUT, output_value=Value.INACTIVE
                )
            },
        ) as req:
            _pulse(
                lambda v: req.set_value(pin, Value.ACTIVE if v else Value.INACTIVE),
                pulse_s,
            )
        return "gpiod"

    name = chip[5:] if chip.startswith("/dev/") else chip
    line_chip = gpiod.Chip(name)
    try:
        line = line_chip.get_line(pin)
        line.request(consumer=CONSUMER, type=gpiod.LINE_REQ_DIR_OUT, default_val=0)
        try:
            _pulse(line.set_value, pulse_s)
        finally:
            line.release()
    finally:
        line_chip.close()
    return "gpiod"


def _drive_lgpio(pin, pulse_s):
    import lgpio

    chip = find_chip()
    num = int(Path(chip).name.replace("gpiochip", "") or "0")
    handle = lgpio.gpiochip_open(num)
    try:
        lgpio.gpio_claim_output(handle, pin, 0)
        _pulse(lambda v: lgpio.gpio_write(handle, pin, v), pulse_s)
    finally:
        lgpio.gpiochip_close(handle)
    return "lgpio"


def _drive_rpi(pin, pulse_s):
    import RPi.GPIO as GPIO

    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
    _pulse(lambda v: GPIO.output(pin, bool(v)), pulse_s)
    return "RPi.GPIO"


def _drive_cli(pin, pulse_s):
    chip = find_chip()
    ms = max(1, int(round(pulse_s * 1000)))
    modern = subprocess.run(
        ["gpioset", "-c", chip, "-t", f"{ms}ms", f"{pin}=1"],
        capture_output=True,
        text=True,
    )
    if modern.returncode == 0:
        return "gpioset"
    name = chip[5:] if chip.startswith("/dev/") else chip
    usec = max(1, int(round(pulse_s * 1_000_000)))
    legacy = subprocess.run(
        ["gpioset", "--mode=time", f"--usec={usec}", name, f"{pin}=1"],
        capture_output=True,
        text=True,
    )
    if legacy.returncode == 0:
        return "gpioset"
    err = (modern.stderr or legacy.stderr or modern.stdout or legacy.stdout or "").strip()
    raise OSError(err or "gpioset failed")


def _hold(set_many, focus_s, shutter_s):
    set_many(SHUTTER_PINS, False)
    set_many(FOCUS_PINS, True)
    time.sleep(focus_s)
    set_many(SHUTTER_PINS, True)
    try:
        time.sleep(shutter_s)
    finally:
        set_many(SHUTTER_PINS, False)
        set_many(FOCUS_PINS, False)


def _sequence_gpiod(focus_s, shutter_s):
    import gpiod
    from gpiod.line import Direction, Value

    pins = tuple(dict.fromkeys((*FOCUS_PINS, *SHUTTER_PINS)))
    inactive = {
        pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE)
        for pin in pins
    }
    with gpiod.request_lines(find_chip(), consumer=CONSUMER, config=inactive) as req:
        def set_many(group, high):
            val = Value.ACTIVE if high else Value.INACTIVE
            req.set_values({pin: val for pin in group})

        _hold(set_many, focus_s, shutter_s)
    return "gpiod"


def _sequence_lgpio(focus_s, shutter_s):
    import lgpio

    chip = find_chip()
    num = int(Path(chip).name.replace("gpiochip", "") or "0")
    handle = lgpio.gpiochip_open(num)
    pins = tuple(dict.fromkeys((*FOCUS_PINS, *SHUTTER_PINS)))
    try:
        for pin in pins:
            lgpio.gpio_claim_output(handle, pin, 0)

        def set_many(group, high):
            level = 1 if high else 0
            for pin in group:
                lgpio.gpio_write(handle, pin, level)

        _hold(set_many, focus_s, shutter_s)
    finally:
        lgpio.gpiochip_close(handle)
    return "lgpio"


def _sequence_rpi(focus_s, shutter_s):
    import RPi.GPIO as GPIO

    pins = tuple(dict.fromkeys((*FOCUS_PINS, *SHUTTER_PINS)))
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    for pin in pins:
        GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)

    def set_many(group, high):
        level = GPIO.HIGH if high else GPIO.LOW
        for pin in group:
            GPIO.output(pin, level)

    _hold(set_many, focus_s, shutter_s)
    return "RPi.GPIO"


def _sequence(focus_s, shutter_s):
    errors = []
    for fn in (_sequence_gpiod, _sequence_lgpio, _sequence_rpi):
        try:
            return fn(focus_s, shutter_s)
        except ImportError:
            continue
        except (FileNotFoundError, OSError, ValueError, PermissionError) as exc:
            errors.append(str(exc))
    hint = "; ".join(errors[:2])
    raise dual.CamError(
        "cannot drive GPIO shutter"
        " — install python3-libgpiod or python3-rpi-lgpio, join the gpio group"
        + (f" ({hint})" if hint else "")
    )


def _drive(pin, pulse_s):
    errors = []
    for fn in (_drive_gpiod, _drive_lgpio, _drive_rpi, _drive_cli):
        try:
            return fn(pin, pulse_s)
        except ImportError:
            continue
        except (FileNotFoundError, OSError, ValueError, PermissionError) as exc:
            errors.append(str(exc))
    hint = "; ".join(errors[:2])
    raise dual.CamError(
        "cannot drive GPIO "
        + str(pin)
        + " — install python3-libgpiod or python3-rpi-lgpio, join the gpio group"
        + (f" ({hint})" if hint else "")
    )


def _result(pulse_s, focus_s, backend, elapsed):
    return {
        "pin": PIN,
        "focus": list(FOCUS_PINS),
        "shutter": list(SHUTTER_PINS),
        "ms": int(round(pulse_s * 1000)),
        "focus_ms": int(round(focus_s * 1000)),
        "backend": backend or "gpio",
        "elapsed": elapsed,
    }


def fire(pulse_s=None, pin=None, drive=None, focus_s=None, sequence=None):
    pulse_s = PULSE_S if pulse_s is None else float(pulse_s)
    focus_s = FOCUS_LEAD_S if focus_s is None else float(focus_s)
    if pulse_s <= 0 or focus_s < 0:
        raise dual.CamError("GPIO pulse must be > 0")
    if sequence is None:
        if drive is not None:
            sequence = lambda fs, ss: drive(PIN if pin is None else int(pin), ss)
        elif on_pi():
            sequence = _sequence
        elif sim_on():
            return _result(pulse_s, focus_s, "sim", 0.0)
        else:
            raise dual.CamError("GPIO shutter is only on a Raspberry Pi")
    t0 = time.perf_counter()
    backend = sequence(focus_s, pulse_s)
    return _result(pulse_s, focus_s, backend, time.perf_counter() - t0)
