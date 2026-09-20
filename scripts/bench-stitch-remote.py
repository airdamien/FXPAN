#!/usr/bin/env python3
"""Run on a Pi: timed stitch_stamp for bench-captures/."""
from __future__ import annotations

import platform
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path.home() / "nikonduals/cam"))
import pano  # noqa: E402

ROOT = Path.home() / "nikonduals/bench-captures"
STAMPS = ("20260915_182637", "20260918_151348")
MODES = ("match", "open")


def _model() -> str:
    try:
        return Path("/proc/device-tree/model").read_text().strip("\0")
    except OSError:
        return platform.machine()


def main() -> int:
    print(f"host={platform.node()}")
    print(f"model={_model()}")
    print(f"cpus={pano._cpu_count()}")
    if not ROOT.is_dir():
        print(f"missing {ROOT}", file=sys.stderr)
        return 1
    rows = []
    for stamp in STAMPS:
        t_path = ROOT / f"T_{stamp}.jpg"
        if not t_path.is_file():
            print(f"missing {t_path}", file=sys.stderr)
            return 1
        tw, th = pano._size(t_path)
        print(f"\n=== {stamp}  {tw}x{th} ===")
        for mode in MODES:
            dest = ROOT / f"P_{stamp}_{mode}.jpg"
            side = ROOT / f"P_{stamp}_{mode}.json"
            for path in (dest, side):
                if path.is_file():
                    path.unlink()
            t0 = time.perf_counter()
            try:
                info = pano.stitch_stamp(
                    stamp,
                    mode=mode,
                    root=ROOT,
                    balance=True,
                    deghost=False,
                    on_log=lambda _msg: None,
                )
                elapsed = time.perf_counter() - t0
                engine = info.get("engine", mode)
                out = f"{info.get('width')}x{info.get('height')}"
                print(f"  {mode:5s}  {elapsed:7.2f}s  {out}  engine={engine}")
                rows.append((stamp, mode, elapsed, out, engine, ""))
            except Exception as exc:
                elapsed = time.perf_counter() - t0
                print(f"  {mode:5s}  {elapsed:7.2f}s  FAILED  {exc}")
                rows.append((stamp, mode, elapsed, "", "", str(exc)))
    print("\n--- summary ---")
    for stamp, mode, elapsed, out, engine, err in rows:
        tag = err or f"{out} {engine}"
        print(f"{stamp}  {mode:5s}  {elapsed:7.2f}s  {tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
