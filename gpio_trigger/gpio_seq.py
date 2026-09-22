#!/usr/bin/env python3
"""Focus-then-shutter sequence for Pi + dual synced TRS (Instructables-style).

Hardware: four 4N35 (two per TRS jack), BCM 20 = focus, BCM 21 = shutter.
See README.md and gpio_trigger/bom.md.

Standalone — does not import cam.gpio.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

FOCUS_PIN = 20
SHUTTER_PIN = 21
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
            self._req.close()
        if self._lgpio is not None:
            h, lgpio = self._lgpio
            lgpio.gpiochip_close(h)
        if self._rpi:
            import RPi.GPIO as GPIO

            GPIO.cleanup(self._pins)

    def set(self, pin: int, high: bool) -> None:
        if self._backend == "gpiod":
            val = self._Value.ACTIVE if high else self._Value.INACTIVE
            self._req.set_value(pin, val)
        elif self._backend == "lgpio":
            h, lgpio = self._lgpio
            lgpio.gpio_write(h, pin, 1 if high else 0)
        else:
            import RPi.GPIO as GPIO

            GPIO.output(pin, GPIO.HIGH if high else GPIO.LOW)


def fire(
    focus_lead_s: float = FOCUS_LEAD_S,
    shutter_pulse_s: float = SHUTTER_PULSE_S,
    focus_pin: int = FOCUS_PIN,
    shutter_pin: int = SHUTTER_PIN,
) -> None:
    with _Lines((focus_pin, shutter_pin)) as lines:
        lines.set(shutter_pin, False)
        lines.set(focus_pin, True)
        time.sleep(focus_lead_s)
        lines.set(shutter_pin, True)
        time.sleep(shutter_pulse_s)
        lines.set(shutter_pin, False)
        lines.set(focus_pin, False)


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
    if args.hold_focus:
        with _Lines((args.focus_pin, args.shutter_pin)) as lines:
            lines.set(args.shutter_pin, False)
            lines.set(args.focus_pin, True)
            print(f"focus BCM {args.focus_pin} HIGH — Ctrl+C to release")
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                lines.set(args.focus_pin, False)
        return
    fire(args.focus, args.shutter, args.focus_pin, args.shutter_pin)
    print(
        f"fired focus={args.focus_pin} lead={args.focus}s "
        f"shutter={args.shutter_pin} pulse={args.shutter}s"
    )


if __name__ == "__main__":
    main()
