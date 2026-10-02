#!/usr/bin/env python3
"""Listen on the USB gadget and pulse the Nikon 10-pin jacks.

Protocol, one line in, one line out:

    PING
    FIRE
    FIRE <milliseconds>

FIRE holds focus (BCM 20 and 26) for 100 ms, then shutter (BCM 21 and 19)
for 300 ms, or for the given millisecond count. Pins drop before OK.
"""

from __future__ import annotations

import socket
import time

HOST = "10.55.0.1"
PORT = 2323
CHIP = "/dev/gpiochip0"
FOCUS_PINS = (20, 26)
SHUTTER_PINS = (21, 19)
PINS = (20, 26, 21, 19)
FOCUS_MS = 100
DEFAULT_SHUTTER_MS = 300
MAX_SHUTTER_MS = 120_000


def pulse(shutter_ms: int) -> None:
    import gpiod
    from gpiod.line import Direction, Value

    inactive = {
        pin: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE)
        for pin in PINS
    }
    with gpiod.request_lines(CHIP, consumer="fxpan-gpio", config=inactive) as req:
        def set_many(group: tuple[int, ...], high: bool) -> None:
            val = Value.ACTIVE if high else Value.INACTIVE
            req.set_values({pin: val for pin in group})

        set_many(SHUTTER_PINS, False)
        set_many(FOCUS_PINS, True)
        time.sleep(FOCUS_MS / 1000)
        set_many(SHUTTER_PINS, True)
        try:
            time.sleep(shutter_ms / 1000)
        finally:
            set_many(SHUTTER_PINS, False)
            set_many(FOCUS_PINS, False)


def command(line: str) -> str:
    parts = line.strip().split()
    if not parts:
        return ""
    cmd = parts[0].upper()
    if cmd == "PING" and len(parts) == 1:
        return "OK"
    if cmd != "FIRE" or len(parts) > 2:
        return "ERR use PING or FIRE [milliseconds]"
    if len(parts) == 1:
        shutter_ms = DEFAULT_SHUTTER_MS
    elif parts[1].isdigit():
        shutter_ms = int(parts[1])
    else:
        return "ERR use PING or FIRE [milliseconds]"
    if shutter_ms < 1 or shutter_ms > MAX_SHUTTER_MS:
        return f"ERR shutter must be 1..{MAX_SHUTTER_MS} ms"
    pulse(shutter_ms)
    return f"OK focus_ms={FOCUS_MS} shutter_ms={shutter_ms}"


def serve() -> None:
    while True:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((HOST, PORT))
            sock.listen(1)
            break
        except OSError:
            time.sleep(1)
    while True:
        conn, _addr = sock.accept()
        with conn:
            buf = b""
            while True:
                chunk = conn.recv(256)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    try:
                        reply = command(raw.decode("utf-8", "replace"))
                    except Exception as exc:
                        reply = f"ERR {exc}"
                    if reply:
                        conn.sendall((reply + "\n").encode())


if __name__ == "__main__":
    serve()
