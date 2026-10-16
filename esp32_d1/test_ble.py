#!/usr/bin/env python3
"""Talk to a flashed Mini D1 over BLE Nordic UART.

    ./test.sh            PING, pins stay low
    ./test.sh fire       FIRE, focus 100 ms then shutter 300 ms
    ./test.sh fire 1200  shutter held 1200 ms
    ./test.sh scan       list nearby advertisements

The Mac needs Bluetooth permission for the terminal running this.
"""

from __future__ import annotations

import argparse
import asyncio
import sys

NAME = "FXPAN-D1"
SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
RX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"


def command_line(args: argparse.Namespace) -> str:
    if args.action == "ping":
        return "PING"
    if args.ms is None:
        return "FIRE"
    return f"FIRE {args.ms}"


def wait_s(line: str) -> float:
    if not line.startswith("FIRE"):
        return 5
    parts = line.split()
    shutter = 300 if len(parts) == 1 else int(parts[1])
    return shutter / 1000 + 8


async def scan() -> int:
    from bleak import BleakScanner

    print("scanning 6 s...")
    found = await BleakScanner.discover(timeout=6.0, return_adv=True)
    if not found:
        print("no advertisements")
        return 1
    for device, adv in found.values():
        name = device.name or adv.local_name or ""
        mark = "  <-- FXPAN-D1" if name == NAME or SERVICE in [u.lower() for u in (adv.service_uuids or [])] else ""
        print(f"{device.address}  {name or '(no name)'}{mark}")
    return 0


async def exchange(line: str) -> str:
    from bleak import BleakClient, BleakScanner

    device = await BleakScanner.find_device_by_filter(
        lambda d, adv: (d.name or adv.local_name) == NAME
        or SERVICE in [u.lower() for u in (adv.service_uuids or [])],
        timeout=8.0,
    )
    if device is None:
        raise SystemExit(f"no {NAME} in range. Is it powered, and is this a BLE scan?")

    loop = asyncio.get_running_loop()
    inbox: asyncio.Queue[str] = asyncio.Queue()
    buf = bytearray()

    def on_notify(_handle: int, data: bytearray) -> None:
        buf.extend(data)
        while True:
            nl = buf.find(b"\n")
            if nl < 0:
                return
            text = bytes(buf[:nl]).decode("utf-8", "replace").strip()
            del buf[: nl + 1]
            if text:
                loop.call_soon_threadsafe(inbox.put_nowait, text)

    print(f"connecting {device.address} {device.name or NAME}")
    async with BleakClient(device) as client:
        await client.start_notify(TX, on_notify)
        payload = (line + "\n").encode()
        print(f"> {line}")
        await client.write_gatt_char(RX, payload, response=False)
        try:
            reply = await asyncio.wait_for(inbox.get(), wait_s(line))
        except asyncio.TimeoutError:
            raise SystemExit("no reply") from None
        print(f"< {reply}")
        return reply


def main() -> None:
    p = argparse.ArgumentParser(description="PING or FIRE the Mini D1 over BLE")
    sub = p.add_subparsers(dest="action")
    sub.add_parser("ping", help="ask for OK, do not pulse (default)")
    fire = sub.add_parser("fire", help="pulse focus then shutter")
    fire.add_argument("ms", nargs="?", type=int, help="shutter hold in milliseconds")
    sub.add_parser("scan", help="list BLE devices")
    args = p.parse_args()
    if args.action is None:
        args.action = "ping"
        args.ms = None
    if args.action == "fire" and args.ms is not None and not 1 <= args.ms <= 120_000:
        p.error("shutter must be 1..120000 ms")
    if args.action == "scan":
        raise SystemExit(asyncio.run(scan()))
    reply = asyncio.run(exchange(command_line(args)))
    raise SystemExit(0 if reply.startswith("OK") else 1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
