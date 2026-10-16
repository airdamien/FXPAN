#!/usr/bin/env python3
"""Hold a FIRE long enough to see the shutter-board LEDs.

Focus LEDs come on first. A tenth of a second later the shutter LEDs join
them, and both stay lit for the hold. Cameras stay unplugged.

    ./watch.sh
    ./watch.sh 4000
"""

from __future__ import annotations

import argparse
import asyncio
import sys

from test_ble import exchange


def main() -> None:
    p = argparse.ArgumentParser(description="Light the shutter-board LEDs")
    p.add_argument("ms", nargs="?", type=int, default=3000, help="how long the shutter LEDs stay on")
    args = p.parse_args()
    if not 1 <= args.ms <= 120_000:
        p.error("hold must be 1..120000 ms")
    seconds = args.ms / 1000
    print("Cameras stay unplugged. Watch the shutter board.")
    print("Focus LEDs (D1 and D3) light first.")
    print(f"Shutter LEDs (D2 and D4) join them and stay on for {seconds:g} s.")
    print("Then all four go out.")
    reply = asyncio.run(exchange(f"FIRE {args.ms}"))
    print(f"< {reply}")
    raise SystemExit(0 if reply.startswith("OK") else 1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
