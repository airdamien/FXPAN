#!/usr/bin/env python3
"""USB control for the two D7000s via gphoto2 (PTP).

The taking-lens iris lives on the enlarger, not the bodies. This matches
ISO / shutter / WB and fires both cameras. USB skew is tens of ms — use
the MC-DC2 Y-lead for anything that moves.

  python3 cam/dual.py detect
  python3 cam/dual.py pair --t SERIAL --r SERIAL
  python3 cam/dual.py status
  python3 cam/dual.py set --iso 400 --shutter 1/125
  python3 cam/dual.py shoot captures/
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

GPHOTO2 = os.environ.get("GPHOTO2", "gphoto2")
ROOT = Path(__file__).resolve().parent
PAIR_PATH = Path(os.environ.get("NIKONDUALS_PAIR", ROOT / "cameras.json"))
KEYS = (
    "serialnumber",
    "iso",
    "shutterspeed",
    "imagequality",
    "whitebalance",
    "expprogram",
    "capturetarget",
    "batterylevel",
)


class CamError(Exception):
    pass


def free_usb():
    if sys.platform == "darwin":
        subprocess.run(
            ["killall", "PTPCamera"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def gp(args, port=None, timeout=120):
    cmd = [GPHOTO2]
    if port:
        cmd += ["--port", port]
    cmd += list(args)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise CamError(f"{' '.join(cmd)}\n{err}")
    return proc.stdout


def parse_detect(text):
    rows = []
    for line in text.splitlines():
        line = line.rstrip()
        if not line or line.startswith("Model") or line.startswith("-"):
            continue
        if "usb:" not in line:
            continue
        model, port = line.rsplit(None, 1)
        rows.append({"model": model.strip(), "port": port.strip(), "serial": ""})
    return rows


def parse_current(text):
    for line in text.splitlines():
        if line.startswith("Current:"):
            return line.split(":", 1)[1].strip()
    return ""


def load_pair():
    if not PAIR_PATH.is_file():
        return {}
    data = json.loads(PAIR_PATH.read_text())
    return {k: str(v) for k, v in data.items() if k in ("T", "R") and v}


def save_pair(t_serial, r_serial):
    PAIR_PATH.write_text(json.dumps({"T": t_serial, "R": r_serial}, indent=2) + "\n")


def detect_bodies():
    free_usb()
    rows = parse_detect(gp(["--auto-detect"]))
    for row in rows:
        try:
            row["serial"] = parse_current(gp(["--get-config", "serialnumber"], port=row["port"]))
        except CamError:
            row["serial"] = ""
    pair = load_pair()
    serial_role = {serial: role for role, serial in pair.items()}
    for row in rows:
        row["role"] = serial_role.get(row["serial"], "")
    return rows


def require_paired(rows):
    have = {row["role"]: row for row in rows if row["role"] in ("T", "R")}
    if "T" in have and "R" in have:
        return have
    extras = [row for row in rows if not row["role"]]
    raise CamError(
        "need paired T and R on USB. "
        f"detect saw {len(rows)} body(ies); pair file is {PAIR_PATH}. "
        "Run: python3 cam/dual.py detect && python3 cam/dual.py pair --t SERIAL --r SERIAL"
        + (f"  unpaired={extras}" if extras else "")
    )


def cmd_detect(_args):
    rows = detect_bodies()
    if not rows:
        print("no cameras. D7000 Setup → USB → MTP/PTP, wake both, plug USB.")
        return
    print(f"{'role':<4} {'serial':<14} {'port':<14} model")
    for row in rows:
        print(
            f"{row['role'] or '-':<4} {row['serial'] or '?':<14} "
            f"{row['port']:<14} {row['model']}"
        )


def cmd_pair(args):
    save_pair(args.t, args.r)
    print(f"wrote {PAIR_PATH}  T={args.t}  R={args.r}")


def _status_one(row):
    vals = {"role": row["role"] or "-", "port": row["port"], "model": row["model"]}
    for key in KEYS:
        try:
            vals[key] = parse_current(gp(["--get-config", key], port=row["port"]))
        except CamError as exc:
            vals[key] = f"! {exc}"
    return vals


def cmd_status(_args):
    rows = detect_bodies()
    if not rows:
        raise CamError("no cameras")
    blocks = []
    with ThreadPoolExecutor(max_workers=len(rows)) as pool:
        for vals in pool.map(_status_one, rows):
            blocks.append(vals)
    keys = ["role", "model", "port", *KEYS]
    for key in keys:
        bits = "  ".join(f"{b.get(key, ''):<22}" for b in blocks)
        print(f"{key:<14} {bits}")


def _set_one(port, assignments):
    args = []
    for key, value in assignments:
        args += ["--set-config", f"{key}={value}"]
    gp(args, port=port)


def cmd_set(args):
    assignments = []
    if args.iso is not None:
        assignments.append(("iso", args.iso))
    if args.shutter is not None:
        assignments.append(("shutterspeed", args.shutter))
    if args.quality is not None:
        assignments.append(("imagequality", args.quality))
    if args.wb is not None:
        assignments.append(("whitebalance", args.wb))
    if args.program is not None:
        assignments.append(("expprogram", args.program))
    if not assignments:
        raise CamError("nothing to set (use --iso / --shutter / --quality / --wb / --program)")
    have = require_paired(detect_bodies())
    with ThreadPoolExecutor(max_workers=2) as pool:
        futs = [pool.submit(_set_one, have[role]["port"], assignments) for role in ("T", "R")]
        for fut in futs:
            fut.result()
    print("set " + " ".join(f"{k}={v}" for k, v in assignments) + " on T and R")


def _shoot_one(role, port, dest, stamp):
    dest.mkdir(parents=True, exist_ok=True)
    filename = str(dest / f"{role}_{stamp}.%C")
    t0 = time.perf_counter()
    gp(
        [
            "--set-config",
            "capturetarget=0",
            "--capture-image-and-download",
            "--force-overwrite",
            f"--filename={filename}",
        ],
        port=port,
        timeout=180,
    )
    return role, time.perf_counter() - t0


def _shoot_card(role, port):
    t0 = time.perf_counter()
    gp(
        ["--set-config", "capturetarget=1", "--capture-image"],
        port=port,
        timeout=90,
    )
    return role, time.perf_counter() - t0


def cmd_shoot(args):
    have = require_paired(detect_bodies())
    dest = Path(args.dest)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    print(f"shoot {stamp}  T={have['T']['port']}  R={have['R']['port']}  → {dest}/")
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=2) as pool:
        futs = [
            pool.submit(_shoot_one, role, have[role]["port"], dest, stamp)
            for role in ("T", "R")
        ]
        for fut in futs:
            role, elapsed = fut.result()
            print(f"  {role}  {elapsed:.2f}s")
    print(f"done {time.perf_counter() - t0:.2f}s  (USB skew is tens of ms; wired remote for action)")


def build_parser():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("detect", help="list USB bodies and pair roles")
    pair = sub.add_parser("pair", help="remember which serial is T vs R")
    pair.add_argument("--t", required=True, help="transmit / back (+Y) serial")
    pair.add_argument("--r", required=True, help="reflect / side (+X) serial")
    sub.add_parser("status", help="ISO, shutter, quality on each body")
    s = sub.add_parser("set", help="write the same exposure to both")
    s.add_argument("--iso")
    s.add_argument("--shutter")
    s.add_argument("--quality")
    s.add_argument("--wb")
    s.add_argument("--program", default=None, help="usually M")
    sh = sub.add_parser("shoot", help="fire both and download")
    sh.add_argument("dest", nargs="?", default="captures")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        {"detect": cmd_detect, "pair": cmd_pair, "status": cmd_status, "set": cmd_set, "shoot": cmd_shoot}[
            args.cmd
        ](args)
    except CamError as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
