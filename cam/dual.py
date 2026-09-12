#!/usr/bin/env python3
"""USB control for the two D7000s via gphoto2 (PTP).

The taking-lens iris lives on the enlarger, not the bodies. This matches
ISO / shutter / WB and fires every paired body on USB (one is enough).
USB skew is tens of ms — use the MC-DC2 Y-lead for anything that moves.

  python3 cam/dual.py detect
  python3 cam/dual.py pair --t SERIAL
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
import threading
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
    "exposurecompensation",
    "capturetarget",
    "batterylevel",
)
EXTRA_KEYS = (
    "focusmode2", "focusmode", "meteringmode", "availableshots",
    "500e", "scenemode",
)

# D7000 mode dial. gphoto2 names 32790 "Night Landscape" — that is the
# leftover SCENE submenu (scenemode), not the dial.
D7000_DIAL = {
    "1": "M",
    "2": "P",
    "3": "A",
    "4": "S",
    "32784": "Auto",
    "32790": "SCENE",
    "32792": "Auto (no flash)",
    "32848": "U1",
    "32849": "U2",
}


class CamError(Exception):
    pass


def _kill_ptp():
    if sys.platform != "darwin":
        return
    subprocess.run(
        ["killall", "-9", "ptpcamerad", "PTPCamera"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def ptp_disable():
    """Stop macOS from grabbing PTP cameras so gphoto2 can claim them."""
    if sys.platform != "darwin":
        return
    subprocess.run(
        ["launchctl", "disable", f"gui/{os.getuid()}/com.apple.ptpcamerad"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    _kill_ptp()


def ptp_enable():
    if sys.platform != "darwin":
        return
    subprocess.run(
        ["launchctl", "enable", f"gui/{os.getuid()}/com.apple.ptpcamerad"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


_hold_stop = None
_hold_th = None


def ptp_hold(on=True):
    """Keep ptpcamerad dead for the life of the web UI / a long run."""
    global _hold_stop, _hold_th
    if sys.platform != "darwin":
        return
    if not on:
        if _hold_stop:
            _hold_stop.set()
        _hold_stop = None
        _hold_th = None
        return
    ptp_disable()
    if _hold_th and _hold_th.is_alive():
        return
    _hold_stop = threading.Event()

    def loop():
        while not _hold_stop.wait(0.08):
            _kill_ptp()

    _hold_th = threading.Thread(target=loop, name="ptp-hold", daemon=True)
    _hold_th.start()


def free_usb():
    _kill_ptp()


def _claim_fail(err):
    err = err or ""
    return "Could not claim the USB device" in err or "Error (-53" in err


def _gp_err(err):
    if _claim_fail(err):
        return "USB busy (macOS ptpcamerad). Hit Status again."
    lines = [ln.strip() for ln in (err or "").splitlines() if ln.strip()]
    for ln in reversed(lines):
        if ln.startswith("***") or ln.startswith("gphoto2"):
            continue
        return ln[:200]
    return (err or "gphoto2 failed")[-200:]


def gp(args, port=None, timeout=120, _retried=False):
    free_usb()
    if _retried:
        time.sleep(0.35)
    cmd = [GPHOTO2]
    if port:
        cmd += ["--port", port]
    cmd += list(args)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        if not _retried and _claim_fail(err):
            return gp(args, port=port, timeout=timeout, _retried=True)
        raise CamError(_gp_err(err))
    return proc.stdout


def parse_currents(text):
    return [
        line.split(":", 1)[1].strip()
        for line in text.splitlines()
        if line.startswith("Current:")
    ]


def parse_widget_currents(text):
    """One Current per Label block. Extra Current: lines cannot shift keys."""
    vals = []
    current = ""
    saw = False
    for line in text.splitlines():
        if line.startswith("Label:"):
            if saw:
                vals.append(current)
            current = ""
            saw = True
        elif line.startswith("Current:"):
            current = line.split(":", 1)[1].strip()
    if saw:
        vals.append(current)
    return vals


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


def format_shutter(s):
    raw = (s or "").strip()
    if not raw:
        return raw
    t = raw.lower().replace(" ", "")
    if t.endswith("s") and "/" not in t:
        t = t[:-1]
    try:
        sec = float(t)
    except ValueError:
        return raw
    if sec <= 0:
        return raw
    if sec >= 1:
        if abs(sec - round(sec)) < 0.05:
            return str(int(round(sec)))
        return f"{sec:.1f}".rstrip("0").rstrip(".")
    inv = 1.0 / sec
    n = int(round(inv))
    if n >= 2 and abs(inv - n) < 0.08 * n:
        return f"1/{n}"
    return raw


def decode_program(vals):
    code = str(vals.get("500e") or "").strip()
    name = D7000_DIAL.get(code)
    if not name:
        raw = (vals.get("expprogram") or "").strip()
        if raw.lower() == "night landscape":
            name = "SCENE"
        else:
            name = raw
    if name == "SCENE":
        scene = (vals.get("scenemode") or "").strip()
        if scene:
            return f"SCENE · {scene}"
    return name


def load_pair():
    if not PAIR_PATH.is_file():
        return {}
    data = json.loads(PAIR_PATH.read_text())
    return {k: str(v) for k, v in data.items() if k in ("T", "R") and v}


def save_pair(t_serial=None, r_serial=None, replace=False):
    data = {} if replace else dict(load_pair())
    if t_serial is not None:
        t_serial = str(t_serial).strip()
    if r_serial is not None:
        r_serial = str(r_serial).strip()
    if t_serial and r_serial and t_serial == r_serial:
        raise CamError("T and R cannot be the same serial")
    if t_serial is not None:
        if t_serial:
            data["T"] = t_serial
            if data.get("R") == t_serial:
                data.pop("R", None)
        else:
            data.pop("T", None)
    if r_serial is not None:
        if r_serial:
            data["R"] = r_serial
            if data.get("T") == r_serial:
                data.pop("T", None)
        else:
            data.pop("R", None)
    PAIR_PATH.write_text(json.dumps(data, indent=2) + "\n")
    return data


def swap_pair():
    old = load_pair()
    if not old:
        raise CamError("nothing to swap")
    return save_pair(old.get("R") or "", old.get("T") or "", replace=True)


def detect_bodies():
    ptp_disable()
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


def require_online(rows):
    """Paired bodies on USB. One is enough. A lone unpaired body is T (or R
    if T is already stored for a different serial)."""
    have = {row["role"]: row for row in rows if row["role"] in ("T", "R")}
    if have:
        return have
    if len(rows) == 1:
        row = dict(rows[0])
        stored = load_pair()
        if stored.keys() == {"T"}:
            role = "R"
        elif stored.keys() == {"R"}:
            role = "T"
        else:
            role = "T"
        row["role"] = role
        return {role: row}
    if not rows:
        raise CamError("no cameras. D7000 Setup → USB → MTP/PTP, wake, plug USB.")
    extras = [row for row in rows if not row["role"]]
    raise CamError(
        "no paired body on USB. "
        f"detect saw {len(rows)} body(ies); pair file is {PAIR_PATH}. "
        "Tap T or R on a body on the USB tab, or: python3 cam/dual.py pair --t SERIAL"
        + (f"  unpaired={extras}" if extras else "")
    )


def cmd_detect(_args):
    rows = detect_bodies()
    if not rows:
        print("no cameras. D7000 Setup → USB → MTP/PTP, wake, plug USB.")
        return
    print(f"{'role':<4} {'serial':<14} {'port':<14} model")
    for row in rows:
        print(
            f"{row['role'] or '-':<4} {row['serial'] or '?':<14} "
            f"{row['port']:<14} {row['model']}"
        )


def cmd_pair(args):
    if not args.t and not args.r:
        raise CamError("need --t and/or --r")
    data = save_pair(args.t, args.r)
    bits = "  ".join(f"{k}={v}" for k, v in data.items()) or "(empty)"
    print(f"wrote {PAIR_PATH}  {bits}")


def _get_config(port, key):
    try:
        return parse_current(gp(["--get-config", key], port=port))
    except CamError:
        return ""


def _status_one(row):
    vals = {"role": row["role"] or "-", "port": row["port"], "model": row["model"]}
    args = []
    for key in KEYS:
        args += ["--get-config", key]
    try:
        raw = gp(args, port=row["port"])
        currents = parse_widget_currents(raw)
        if len(currents) != len(KEYS):
            currents = parse_currents(raw)
        if len(currents) == len(KEYS):
            for key, val in zip(KEYS, currents):
                vals[key] = val
        else:
            for key in KEYS:
                vals[key] = _get_config(row["port"], key)
    except CamError:
        for key in KEYS:
            vals[key] = _get_config(row["port"], key)
    for key in EXTRA_KEYS:
        val = _get_config(row["port"], key)
        if val:
            vals[key] = val
    if not vals.get("focusmode"):
        vals["focusmode"] = vals.get("focusmode2") or ""
    if vals.get("shutterspeed"):
        vals["shutterspeed"] = format_shutter(vals["shutterspeed"])
    if (vals.get("whitebalance") or "").lower() == "automatic":
        vals["whitebalance"] = "Auto"
    prog = decode_program(vals)
    if prog:
        vals["expprogram"] = prog
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
    """Set each widget on its own. expprogram is the mode dial and often readonly."""
    errors = []
    for key, value in assignments:
        try:
            gp(["--set-config", f"{key}={value}"], port=port)
        except CamError as exc:
            errors.append(f"{key}={value}: {exc}")
    if errors and len(errors) == len(assignments):
        raise CamError("; ".join(errors))
    return errors


def cmd_set(args):
    assignments = []
    if args.program is not None:
        assignments.append(("expprogram", args.program))
    if args.iso is not None:
        assignments.append(("iso", args.iso))
    if args.shutter is not None:
        assignments.append(("shutterspeed", args.shutter))
    if args.quality is not None:
        assignments.append(("imagequality", args.quality))
    if args.wb is not None:
        assignments.append(("whitebalance", args.wb))
    if not assignments:
        raise CamError("nothing to set (use --iso / --shutter / --quality / --wb / --program)")
    have = require_online(detect_bodies())
    notes = []
    with ThreadPoolExecutor(max_workers=len(have)) as pool:
        futs = [pool.submit(_set_one, row["port"], assignments) for row in have.values()]
        for fut in futs:
            notes.extend(fut.result() or [])
    roles = " and ".join(sorted(have))
    print("set " + " ".join(f"{k}={v}" for k, v in assignments) + f" on {roles}")
    for note in notes:
        print(note)


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
    have = require_online(detect_bodies())
    dest = Path(args.dest)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    ports = "  ".join(f"{role}={have[role]['port']}" for role in sorted(have))
    print(f"shoot {stamp}  {ports}  → {dest}/")
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=len(have)) as pool:
        futs = [
            pool.submit(_shoot_one, role, have[role]["port"], dest, stamp)
            for role in have
        ]
        for fut in futs:
            role, elapsed = fut.result()
            print(f"  {role}  {elapsed:.2f}s")
    print(f"done {time.perf_counter() - t0:.2f}s  (USB skew is tens of ms; wired remote for action)")


def build_parser():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("detect", help="list USB bodies and pair roles")
    pair = sub.add_parser("pair", help="remember which serial is T and/or R")
    pair.add_argument("--t", help="transmit / back (+Y) serial")
    pair.add_argument("--r", help="reflect / side (+X) serial")
    sub.add_parser("status", help="ISO, shutter, quality on each body")
    s = sub.add_parser("set", help="write the same exposure to both")
    s.add_argument("--iso")
    s.add_argument("--shutter")
    s.add_argument("--quality")
    s.add_argument("--wb")
    s.add_argument("--program", default=None, help="usually M")
    sh = sub.add_parser("shoot", help="fire both and download")
    sh.add_argument("dest", nargs="?", default="captures")
    sub.add_parser("ptp-off", help="disable macOS ptpcamerad so gphoto2 can claim USB")
    sub.add_parser("ptp-on", help="re-enable macOS ptpcamerad")
    return p


def cmd_ptp_off(_args):
    ptp_disable()
    print("ptpcamerad disabled. Photos / Image Capture will not grab the D7000s.")


def cmd_ptp_on(_args):
    ptp_hold(False)
    ptp_enable()
    print("ptpcamerad re-enabled.")


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        {
            "detect": cmd_detect,
            "pair": cmd_pair,
            "status": cmd_status,
            "set": cmd_set,
            "shoot": cmd_shoot,
            "ptp-off": cmd_ptp_off,
            "ptp-on": cmd_ptp_on,
        }[args.cmd](args)
    except CamError as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
