#!/usr/bin/env python3
"""Focus-then-shutter sequence for Pi + dual synced TRS (Instructables-style).

Hardware: four 4N35 (two per TRS jack). BCM 20/21 are J1, and J2 while
JP1/JP2 pads 1–2 are bridged. BCM 26/19 are J2 after those jumpers
are cut and pads 2–3 are bridged. Both pairs are pulsed together.
See README.md and gpio_trigger/bom.md.

Standalone — does not import cam.gpio.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

FOCUS_PIN = 20
SHUTTER_PIN = 21
# Camera B when JP1/JP2 are cut and bridged 2–3. Idle if the default
# 1–2 bridge is still in place.
FOCUS_PINS = (20, 26)
SHUTTER_PINS = (21, 19)
FOCUS_LEAD_S = 0.1
SHUTTER_PULSE_S = 0.3


def _chip_path() -> str:
    for candidate in ("/dev/gpiochip4", "/dev/gpiochip0"):
        if Path(candidate).exists():
            return candidate
    return "/dev/gpiochip0"


class _Lines:
    """Hold GPIO outputs for a multi-step Nikon release sequence."""

    def __init__(self, pins: tuple[int, ...]) -> None:
        self._pins = pins
        self._backend = None
        self._req = None
        self._lgpio = None
        self._rpi = False

    def __enter__(self) -> _Lines:
        try:
            import gpiod
            from gpiod.line import Direction, Value

            cfg = {
                pin: gpiod.LineSettings(
                    direction=Direction.OUTPUT, output_value=Value.INACTIVE
                )
                for pin in self._pins
            }
            self._req = gpiod.request_lines(
                _chip_path(), consumer="gpio_trigger", config=cfg
            )
            self._backend = "gpiod"
            self._Value = Value
            return self
        except ImportError:
            pass
        try:
            import lgpio

            num = int(Path(_chip_path()).name.replace("gpiochip", "") or "0")
            self._lgpio = (lgpio.gpiochip_open(num), lgpio)
            for pin in self._pins:
                lgpio.gpio_claim_output(self._lgpio[0], pin, 0)
            self._backend = "lgpio"
            return self
        except ImportError:
            pass
        import RPi.GPIO as GPIO

        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        for pin in self._pins:
            GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
        self._backend = "rpi"
        self._rpi = True
        return self

    def __exit__(self, *exc) -> None:
        if self._req is not None:
            try:
                for pin in self._pins:
                    self.set(pin, False)
            except Exception:
                pass
            # libgpiod 2 LineRequest releases with release(), not close().
            release = getattr(self._req, "release", None)
            if callable(release):
                release()
            self._req = None
        if self._lgpio is not None:
            h, lgpio = self._lgpio
            lgpio.gpiochip_close(h)
        if self._rpi:
            import RPi.GPIO as GPIO

            GPIO.cleanup(self._pins)

    def set(self, pin: int, high: bool) -> None:
        self.set_many((pin,), high)

    def set_many(self, pins: tuple[int, ...], high: bool) -> None:
        if self._backend == "gpiod":
            val = self._Value.ACTIVE if high else self._Value.INACTIVE
            self._req.set_values({pin: val for pin in pins})
        elif self._backend == "lgpio":
            h, lgpio = self._lgpio
            level = 1 if high else 0
            for pin in pins:
                lgpio.gpio_write(h, pin, level)
        else:
            import RPi.GPIO as GPIO

            level = GPIO.HIGH if high else GPIO.LOW
            for pin in pins:
                GPIO.output(pin, level)


def fire(
    focus_lead_s: float = FOCUS_LEAD_S,
    shutter_pulse_s: float = SHUTTER_PULSE_S,
    focus_pin: int = FOCUS_PIN,
    shutter_pin: int = SHUTTER_PIN,
    focus_pins: tuple[int, ...] = FOCUS_PINS,
    shutter_pins: tuple[int, ...] = SHUTTER_PINS,
) -> None:
    focus = tuple(dict.fromkeys((focus_pin, *focus_pins)))
    shutter = tuple(dict.fromkeys((shutter_pin, *shutter_pins)))
    with _Lines((*focus, *shutter)) as lines:
        lines.set_many(shutter, False)
        lines.set_many(focus, True)
        time.sleep(focus_lead_s)
        lines.set_many(shutter, True)
        time.sleep(shutter_pulse_s)
        lines.set_many(shutter, False)
        lines.set_many(focus, False)


def main() -> None:
    p = argparse.ArgumentParser(description="Nikon focus-then-shutter GPIO sequence")
    p.add_argument("--focus-pin", type=int, default=FOCUS_PIN)
    p.add_argument("--shutter-pin", type=int, default=SHUTTER_PIN)
    p.add_argument("--focus", type=float, default=FOCUS_LEAD_S, help="seconds focus held before shutter")
    p.add_argument("--shutter", type=float, default=SHUTTER_PULSE_S, help="seconds shutter held high")
    p.add_argument(
        "--hold-focus",
        action="store_true",
        help="assert focus only (leave high until Ctrl+C)",
    )
    args = p.parse_args()
    focus = tuple(dict.fromkeys((args.focus_pin, *FOCUS_PINS)))
    shutter = tuple(dict.fromkeys((args.shutter_pin, *SHUTTER_PINS)))
    if args.hold_focus:
        with _Lines((*focus, *shutter)) as lines:
            lines.set_many(shutter, False)
            lines.set_many(focus, True)
            print(f"focus BCM {focus} HIGH — Ctrl+C to release")
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                lines.set_many(focus, False)
        return
    fire(args.focus, args.shutter, args.focus_pin, args.shutter_pin)
    print(
        f"fired focus={focus} lead={args.focus}s "
        f"shutter={shutter} pulse={args.shutter}s"
    )


if __name__ == "__main__":
    main()
