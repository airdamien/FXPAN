#!/usr/bin/env python3
"""USB control for the two D7000s via gphoto2 (PTP).

ISO / shutter / f-number / WB on every paired body (one is enough).
The enlarger iris is the taking-lens ring; a CPU F-mount can take PTP f/.
USB skew is tens of ms — use the MC-DC2 Y-lead for anything that moves.

  python3 cam/dual.py detect
  python3 cam/dual.py pair --t SERIAL
  python3 cam/dual.py pair --t SERIAL --r SERIAL
  python3 cam/dual.py status
  python3 cam/dual.py set --iso 400 --shutter 1/125 --fstop 5.6
  python3 cam/dual.py shoot captures/
"""

from __future__ import annotations

import argparse
import json
import os
import re
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
    "f-number",
    "imagequality",
    "whitebalance",
    "expprogram",
    "exposurecompensation",
    "capturetarget",
    "batterylevel",
    "isoauto",
    "autoiso",
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


_linux_ptp_clear = False
_last_detect = []


def _free_linux_ptp(force=False):
    """Stop GVFS from owning the D7000s so gphoto2 can claim them."""
    global _linux_ptp_clear
    if sys.platform == "darwin":
        return
    if _linux_ptp_clear and not force:
        return
    units = (
        "gvfs-gphoto2-volume-monitor.service",
        "gvfs-mtp-volume-monitor.service",
    )
    action = ["mask", "--now"] if os.environ.get("DUALS_KIOSK") == "1" else ["stop"]
    for unit in units:
        subprocess.run(
            ["systemctl", "--user", *action, unit],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    subprocess.run(
        ["pkill", "-x", "-9", "gvfsd-gphoto2", "gvfsd-mtp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    _linux_ptp_clear = True
    time.sleep(0.12)


def free_usb():
    _kill_ptp()
    _free_linux_ptp()


def _claim_fail(err):
    err = err or ""
    return "Could not claim the USB device" in err or "Error (-53" in err


def _gp_err(err):
    if _claim_fail(err):
        return "USB busy (gvfs or ptpcamerad). Hit Detect again."
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
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise CamError("gphoto2 timed out") from exc
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        if not _retried and _claim_fail(err):
            _free_linux_ptp(force=True)
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


def format_aperture(s):
    raw = (s or "").strip()
    if not raw:
        return raw
    t = raw.lower().replace(" ", "").replace("f/", "").replace("f", "")
    try:
        n = float(t)
    except ValueError:
        return raw
    if n <= 0:
        return raw
    if abs(n - round(n)) < 0.05:
        pretty = str(int(round(n)))
    else:
        pretty = f"{n:.1f}".rstrip("0").rstrip(".")
    return f"f/{pretty}"


def fstop_tries(value):
    fmt = format_aperture(value)
    n = fmt.replace("f/", "").replace("f", "").strip()
    out = []
    for val in (fmt, f"f/{n}" if n else "", n, str(value or "").strip()):
        if val and val not in out:
            out.append(val)
    return out or [str(value or "").strip()]


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


def _read_serial(row):
    try:
        return parse_current(gp(["--get-config", "serialnumber"], port=row["port"]))
    except CamError:
        return ""


def _apply_roles(rows):
    pair = load_pair()
    serial_role = {serial: role for role, serial in pair.items()}
    for row in rows:
        row["role"] = serial_role.get(row.get("serial") or "", "")
    return rows


def seat_open_roles(rows, persist=False):
    """If exactly one unpaired body and one empty T/R slot, that body is the slot."""
    rows = list(rows or [])
    pair = load_pair()
    taken = {row.get("role") for row in rows if row.get("role") in ("T", "R")}
    extras = [
        row for row in rows
        if row.get("serial") and row.get("role") not in ("T", "R")
    ]
    open_roles = [role for role in ("T", "R") if not pair.get(role) and role not in taken]
    if len(extras) != 1 or len(open_roles) != 1:
        return rows
    role = open_roles[0]
    extras[0]["role"] = role
    if persist:
        if role == "T":
            save_pair(extras[0]["serial"], None)
        else:
            save_pair(None, extras[0]["serial"])
    return rows


def probe_port(port, timeout=8):
    """Serial + role for one USB port. Does not --auto-detect (won't kick live)."""
    row = {"model": "", "port": port, "serial": "", "role": ""}
    row["serial"] = _read_serial(row)
    _apply_roles([row])
    seat_open_roles([row], persist=True)
    return row


def orphan_ports(ports, have):
    """Nikon ports on the bus that no T/R row currently owns."""
    used = { (row or {}).get("port") for row in (have or {}).values() }
    return [p for p in (ports or []) if p and p not in used]


def detect_bodies(timeout=120):
    global _last_detect
    ptp_disable()
    free_usb()
    rows = parse_detect(gp(["--auto-detect"], timeout=timeout))
    if len(rows) > 1:
        with ThreadPoolExecutor(max_workers=len(rows)) as pool:
            serials = list(pool.map(_read_serial, rows))
        for row, serial in zip(rows, serials):
            row["serial"] = serial
    elif rows:
        rows[0]["serial"] = _read_serial(rows[0])
    _apply_roles(rows)
    seat_open_roles(rows, persist=True)
    attach_usb_speed(rows)
    _last_detect = rows
    return rows


NIKON_USB_VID = "04b0"
USB_SYS = Path("/sys/bus/usb/devices")


def format_usb_speed(raw):
    """Human USB link from sysfs `speed` (Mb/s)."""
    try:
        mbps = float(str(raw).strip())
    except (TypeError, ValueError):
        return ""
    if mbps <= 0:
        return ""
    if mbps >= 1000:
        gb = mbps / 1000.0
        gb_s = str(int(gb)) if abs(gb - int(gb)) < 0.05 else f"{gb:g}"
        if mbps >= 20000:
            tag = "USB3.2"
        elif mbps >= 10000:
            tag = "USB3.1"
        else:
            tag = "USB3"
        return f"{tag} {gb_s} Gb/s"
    if mbps >= 480:
        return "USB2 480 Mb/s"
    if mbps >= 12:
        return "USB1.1 12 Mb/s"
    return f"USB {mbps:g} Mb/s"


def nikon_usb_info(root=None):
    """Nikon PTP devices: gphoto port → {speed, speed_mbps}. None if no sysfs."""
    base = Path(root) if root is not None else USB_SYS
    if not base.is_dir():
        return None
    out = {}
    for node in base.iterdir():
        try:
            vid = (node / "idVendor").read_text().strip().lower()
            if vid != NIKON_USB_VID:
                continue
            bus = int((node / "busnum").read_text().strip())
            dev = int((node / "devnum").read_text().strip())
            speed_raw = ""
            sp = node / "speed"
            if sp.is_file():
                speed_raw = sp.read_text().strip()
        except (OSError, ValueError):
            continue
        port = f"usb:{bus:03d},{dev:03d}"
        mbps = None
        try:
            mbps = float(speed_raw) if speed_raw else None
        except ValueError:
            mbps = None
        out[port] = {"speed": format_usb_speed(speed_raw), "speed_mbps": mbps}
    return out


def attach_usb_speed(rows, root=None):
    info = nikon_usb_info(root)
    if not info:
        return rows
    for row in rows or []:
        meta = info.get(row.get("port") or "")
        if not meta:
            continue
        row["usb_speed"] = meta["speed"]
        row["usb_mbps"] = meta["speed_mbps"]
    return rows


def parse_lsusb(text):
    """gphoto port names from `lsusb` lines for Nikon PTP bodies."""
    ports = []
    for line in (text or "").splitlines():
        m = re.match(
            r"Bus\s+(\d+)\s+Device\s+(\d+):\s+ID\s+04b0:",
            line,
            re.I,
        )
        if m:
            ports.append(f"usb:{int(m.group(1)):03d},{int(m.group(2)):03d}")
    return sorted(set(ports))


def nikon_usb_ports(root=None):
    """Nikon devices on the bus, as gphoto `usb:BBB,DDD` ports.

    Returns a list when the bus can be read without gphoto (sysfs or lsusb).
    Returns None when this host cannot list USB without touching PTP.
    """
    base = Path(root) if root is not None else USB_SYS
    info = nikon_usb_info(base if root is not None else None)
    if info is not None:
        return sorted(info)
    try:
        out = subprocess.check_output(["lsusb"], timeout=2, text=True)
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError):
        return None
    return parse_lsusb(out)


def detect_bodies_cached(timeout=120):
    """Skip serial reads when the same USB ports are still on the bus."""
    ptp_disable()
    free_usb()
    fresh = parse_detect(gp(["--auto-detect"], timeout=timeout))
    prev = {row["port"]: row for row in _last_detect if row.get("serial")}
    if (
        fresh
        and len(fresh) == len(prev)
        and all(row["port"] in prev for row in fresh)
        and all(prev[row["port"]].get("serial") for row in fresh)
    ):
        rows = []
        for row in fresh:
            item = dict(row)
            item["serial"] = prev[row["port"]]["serial"]
            rows.append(item)
        _apply_roles(rows)
        seat_open_roles(rows, persist=True)
        attach_usb_speed(rows)
        return rows
    return detect_bodies(timeout=timeout)


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
    serial = (row.get("serial") or "").strip()
    vals = {
        "role": row.get("role") or "-",
        "port": row["port"],
        "model": row["model"],
        "serial": serial,
    }
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
    if not vals.get("focusmode"):
        vals["focusmode"] = vals.get("focusmode2") or ""
    if vals.get("shutterspeed"):
        vals["shutterspeed"] = format_shutter(vals["shutterspeed"])
    if vals.get("f-number"):
        vals["f-number"] = format_aperture(vals["f-number"])
    if (vals.get("whitebalance") or "").lower() == "automatic":
        vals["whitebalance"] = "Auto"
    prog = decode_program(vals)
    if prog:
        vals["expprogram"] = prog
    cam_sn = (vals.get("serialnumber") or "").strip()
    if cam_sn:
        vals["serial"] = cam_sn
    elif serial:
        vals["serialnumber"] = serial
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


def onoff_tries(value):
    s = str(value or "").strip()
    low = s.lower()
    if low in ("off", "0", "false", "no"):
        return ["Off", "0"]
    if low in ("on", "1", "true", "yes"):
        return ["On", "1"]
    return [s] or ["Off"]


def iso_tries(value):
    """Nikon PTP iso is sometimes '400' and sometimes 'ISO 400'."""
    raw = str(value or "").strip()
    n = raw.replace("ISO", "").replace("iso", "").strip()
    out = []
    for val in (raw, n, f"ISO {n}" if n.isdigit() else ""):
        if val and val not in out:
            out.append(val)
    return out or [raw]


def iso_variants(assignments):
    """Same widgets, each ISO spelling Nikon might accept."""
    assignments = list(assignments or [])
    idx = [i for i, (key, _) in enumerate(assignments) if key == "iso"]
    if not idx:
        return [assignments]
    variants = []
    seen = set()
    for val in iso_tries(assignments[idx[-1]][1]):
        row = list(assignments)
        for i in idx:
            row[i] = ("iso", val)
        key = tuple(row)
        if key not in seen:
            seen.add(key)
            variants.append(row)
    return variants or [assignments]


def config_args(assignments):
    args = []
    for key, value in assignments or []:
        args += ["--set-config", f"{key}={value}"]
    return args


def pack_assignments(assignments):
    """One PTP session: drop duplicate autoiso, pin ISO spelling."""
    packed = []
    seen = set()
    has_isoauto = any(k == "isoauto" for k, _ in (assignments or []))
    for key, value in assignments or []:
        if key == "autoiso" and has_isoauto:
            continue
        if key == "iso":
            tries = iso_tries(value)
            value = next((t for t in tries if t.isdigit()), tries[0])
        elif key in ("isoauto", "autoiso"):
            value = onoff_tries(value)[0]
        elif key == "f-number":
            value = fstop_tries(value)[0]
        if key in seen:
            continue
        seen.add(key)
        packed.append((key, value))
    return packed


def shot_config(assignments):
    """ISO lock must ride with capture or Auto ISO meters again at the shutter."""
    keep = {
        "isoauto", "autoiso", "iso", "shutterspeed", "exposurecompensation",
        "whitebalance", "imagequality",
    }
    return [(k, v) for k, v in pack_assignments(assignments) if k in keep]


def _set_one(port, assignments, timeout=120):
    """Push every widget in one gphoto2 command. Split only if that fails."""
    packed = pack_assignments(assignments)
    if not packed:
        return []
    try:
        gp(config_args(packed), port=port, timeout=timeout)
        return []
    except CamError as exc:
        return _set_widgets(port, packed, last=exc, timeout=timeout)


def _set_widgets(port, assignments, last=None, timeout=120):
    errors = []
    for key, value in assignments:
        if key == "iso":
            tries = iso_tries(value)
        elif key in ("isoauto", "autoiso"):
            tries = onoff_tries(value)
        elif key == "f-number":
            tries = fstop_tries(value)
        else:
            tries = [value]
        err = last
        ok = False
        for val in tries:
            try:
                gp(["--set-config", f"{key}={val}"], port=port, timeout=timeout)
                ok = True
                break
            except CamError as exc:
                err = exc
        if not ok and key == "f-number" and timeout > 30:
            for val in tries:
                try:
                    gp(["--set-config", f"aperture={val}"], port=port, timeout=timeout)
                    ok = True
                    break
                except CamError as exc:
                    err = exc
        if not ok:
            errors.append(f"{key}={value}: {err}")
    if errors and len(errors) == len(assignments):
        raise CamError("; ".join(errors))
    return errors


def assignments_from_status(vals):
    """ISO / shutter / WB / quality / EC from a body's status. No flash."""
    vals = vals or {}
    out = []
    auto = (
        str(vals.get("isoauto") or "").lower() == "on"
        or str(vals.get("autoiso") or "").lower() == "on"
    )
    iso = str(vals.get("iso") or "").replace("ISO", "").strip()
    if auto or iso.lower() == "auto":
        out.append(("isoauto", "On"))
        out.append(("autoiso", "On"))
    elif iso:
        out.append(("isoauto", "Off"))
        out.append(("autoiso", "Off"))
        out.append(("iso", iso_tries(iso)[0] if iso.isdigit() else iso))
    shut = str(vals.get("shutterspeed") or "").strip()
    if shut:
        out.append(("shutterspeed", format_shutter(shut)))
    fnum = str(vals.get("f-number") or vals.get("aperture") or "").strip()
    if fnum and fnum.lower() != "auto":
        out.append(("f-number", format_aperture(fnum)))
    for key in ("imagequality", "whitebalance", "exposurecompensation"):
        val = str(vals.get(key) or "").strip()
        if val:
            out.append((key, val))
    prog = str(vals.get("expprogram") or "").strip()
    if prog in ("M", "A", "S", "P"):
        out.append(("expprogram", prog))
    return out


def copy_from_master(have, master="T"):
    """Push master's exposure onto the other body. Leaves flash alone on the slave."""
    master = "R" if str(master or "").upper() == "R" else "T"
    slave = "R" if master == "T" else "T"
    if master not in have:
        raise CamError(f"master {master} is not on USB")
    if slave not in have:
        raise CamError(f"slave {slave} is not on USB")
    assignments = assignments_from_status(_status_one(have[master]))
    if not assignments:
        raise CamError("master has no settings to copy")
    notes = _set_one(have[slave]["port"], assignments) or []
    copied = " ".join(f"{k}={v}" for k, v in assignments)
    return {
        "master": master,
        "slave": slave,
        "assignments": assignments,
        "notes": notes,
        "message": f"{master} → {slave}  {copied}",
    }


def prepare_shot(port):
    """AF/meter nudge so get-config sees the taking exposure, not LV leftovers."""
    try:
        gp(["--set-config", "autofocusdrive=1"], port=port, timeout=8)
    except CamError:
        pass


def locked_assignments(vals):
    """Freeze metered ISO/shutter as numbers. Copy EV/WB/quality. Skip body f/."""
    out = []
    iso = str(vals.get("iso") or "").replace("ISO", "").replace("iso", "").strip()
    if iso and iso.lower() not in ("auto", "unknown", ""):
        out.append(("isoauto", "Off"))
        out.append(("autoiso", "Off"))
        out.append(("iso", iso_tries(iso)[0] if iso.replace(" ", "").isdigit() else iso))
    shut = str(vals.get("shutterspeed") or "").strip()
    if shut and shut.lower() not in ("auto", "bulb", "unknown", ""):
        out.append(("shutterspeed", format_shutter(shut)))
    for key in ("exposurecompensation", "imagequality", "whitebalance"):
        val = str(vals.get(key) or "").strip()
        if val:
            out.append((key, val))
    return out


def _iso_num(val):
    return str(val or "").replace("ISO", "").replace("iso", "").replace(" ", "").strip()


def apply_locked(port, assignments, timeout=20):
    """Two packed gphoto2 commands: Auto ISO off, then ISO+shutter+EV+WB+quality."""
    packed = pack_assignments(assignments)
    auto = [(k, v) for k, v in packed if k in ("isoauto", "autoiso")]
    rest = [(k, v) for k, v in packed if k not in ("isoauto", "autoiso")]
    notes = []
    if auto:
        notes.extend(_set_one(port, auto, timeout=timeout) or [])
    if rest:
        notes.extend(_set_one(port, rest, timeout=timeout) or [])
    return notes


def freeze_iso(port, iso):
    """Packed Auto ISO off + ISO number. Widget-by-widget set-config is too slow."""
    iso = _iso_num(iso)
    rows = [("isoauto", "Off"), ("autoiso", "Off")]
    if iso:
        rows.append(("iso", iso))
    return apply_locked(port, rows, timeout=20)


def lock_from_master(have, master="T"):
    """Meter on master, then write those numbers onto both bodies in parallel."""
    master = "R" if str(master or "").upper() == "R" else "T"
    if master not in have:
        raise CamError(f"master {master} is not on USB")
    prepare_shot(have[master]["port"])
    assignments = locked_assignments(_status_one(have[master]))
    if not assignments:
        raise CamError("master has no exposure to lock")
    notes = []
    iso = next((v for k, v in assignments if k == "iso"), "")
    with ThreadPoolExecutor(max_workers=len(have)) as pool:
        futs = [
            pool.submit(apply_locked, have[role]["port"], assignments)
            for role in have
        ]
        for fut in futs:
            notes.extend(fut.result() or [])
    slave = "R" if master == "T" else "T"
    if iso and slave in have:
        got = _status_one(have[slave])
        auto = (
            str(got.get("isoauto") or "").lower() == "on"
            or str(got.get("autoiso") or "").lower() == "on"
        )
        if auto or _iso_num(got.get("iso")) != _iso_num(iso):
            notes.extend(apply_locked(have[slave]["port"], assignments) or [])
    copied = " ".join(f"{k}={v}" for k, v in assignments)
    return {
        "master": master,
        "assignments": assignments,
        "notes": notes,
        "message": f"lock {master} → {','.join(sorted(have))}  {copied}",
    }


def parse_cam_time(text):
    """gphoto2 Current: unix seconds or YYYY:MM:DD HH:MM:SS."""
    s = str(text or "").strip()
    if not s:
        return None
    if s.isdigit():
        n = int(s)
        if n > 10_000_000_000:
            n //= 1000
        try:
            return datetime.fromtimestamp(n)
        except (OSError, OverflowError, ValueError):
            return None
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y:%m:%dT%H:%M:%S"):
        try:
            return datetime.strptime(s[:19], fmt)
        except ValueError:
            continue
    return None


def plausible_time(dt):
    return bool(dt) and 2020 <= dt.year <= 2036


def pick_clock(times):
    """Newest plausible RTC among pi / T / R. 2010 Nikon defaults lose."""
    cands = []
    for src, dt in (times or {}).items():
        if plausible_time(dt):
            cands.append((src, dt))
    if cands:
        return max(cands, key=lambda row: row[1])
    pi = (times or {}).get("pi")
    return "pi", pi


def get_cam_time(port):
    last = ""
    for key in ("datetime", "dateandtime"):
        try:
            raw = gp(["--get-config", key], port=port, timeout=8)
        except CamError:
            continue
        last = parse_current(raw) or ""
        dt = parse_cam_time(last)
        if dt:
            return dt
    raise CamError(f"no camera clock ({last or 'empty'})")


def set_cam_time(port, dt):
    stamp = dt.strftime("%Y-%m-%d %H:%M:%S")
    last = None
    for args in (
        ["--set-config", "datetime=now"],
        ["--set-config", f"datetime={stamp}"],
        ["--set-config", f"dateandtime={stamp}"],
    ):
        try:
            gp(args, port=port, timeout=12)
            return
        except CamError as exc:
            last = exc
    raise last or CamError("cannot set camera clock")


def set_host_time(dt):
    stamp = dt.strftime("%Y-%m-%d %H:%M:%S")
    for cmd in (
        ["timedatectl", "set-time", stamp],
        ["sudo", "-n", "timedatectl", "set-time", stamp],
        ["sudo", "-n", "date", "-s", stamp],
    ):
        try:
            proc = subprocess.run(cmd, capture_output=True, timeout=8)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if proc.returncode == 0:
            return True
    return False


def sync_clocks(have):
    """Point Pi and both bodies at the newest plausible clock."""
    times = {"pi": datetime.now()}
    for role, row in (have or {}).items():
        try:
            times[role] = get_cam_time(row["port"])
        except CamError:
            times[role] = None
    src, when = pick_clock(times)
    if when is None:
        return {"source": src, "message": "clock unknown"}
    notes = []
    target = when
    if src != "pi":
        if set_host_time(when):
            notes.append(f"pi←{src}")
            target = datetime.now()
        else:
            notes.append("pi skipped")
    for role, row in (have or {}).items():
        cam = times.get(role)
        if cam is not None and abs((cam - target).total_seconds()) <= 2:
            continue
        try:
            set_cam_time(row["port"], target)
            notes.append(f"{role}←{src}")
        except CamError as exc:
            notes.append(f"{role} {exc}")
    msg = "clock " + (" ".join(notes) if notes else f"ok  {src}")
    return {
        "source": src,
        "when": target.strftime("%Y-%m-%d %H:%M:%S"),
        "times": {
            k: (v.strftime("%Y-%m-%d %H:%M:%S") if v else "")
            for k, v in times.items()
        },
        "message": msg,
    }


def cmd_set(args):
    assignments = []
    if args.program is not None:
        assignments.append(("expprogram", args.program))
    if args.iso is not None:
        assignments.append(("iso", args.iso))
    if args.shutter is not None:
        assignments.append(("shutterspeed", args.shutter))
    if getattr(args, "fstop", None) is not None:
        assignments.append(("f-number", format_aperture(args.fstop)))
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


def _capture_args(card, filename=None):
    if card:
        return ["--set-config", "capturetarget=1", "--capture-image"]
    return [
        "--set-config",
        "capturetarget=0",
        "--capture-image-and-download",
        "--force-overwrite",
        f"--filename={filename}",
    ]


def _gp_capture(port, capture, assignments, timeout):
    """One gphoto2 process: close LV, freeze ISO, capture."""
    packed = shot_config(assignments)
    tries = []
    if packed:
        tries.append(["--set-config", "viewfinder=0"] + config_args(packed) + list(capture))
        tries.append(config_args(packed) + list(capture))
    tries.append(["--set-config", "viewfinder=0"] + list(capture))
    tries.append(list(capture))
    last = None
    for args in tries:
        try:
            gp(args, port=port, timeout=timeout)
            return
        except CamError as exc:
            last = exc
    if last:
        raise last


def _shoot_one(role, port, dest, stamp, assignments=None):
    dest.mkdir(parents=True, exist_ok=True)
    filename = str(dest / f"{role}_{stamp}.%C")
    t0 = time.perf_counter()
    _gp_capture(port, _capture_args(False, filename), assignments, 180)
    return role, time.perf_counter() - t0


def _shoot_card(role, port, assignments=None):
    t0 = time.perf_counter()
    _gp_capture(port, _capture_args(True), assignments, 90)
    return role, time.perf_counter() - t0


LIST_FILE = re.compile(r"^#(\d+)\s+(\S+)")
LIST_FOLDER = re.compile(r"folder '([^']+)'")


def parse_list_files(text):
    files = []
    folder = ""
    for line in text.splitlines():
        fold = LIST_FOLDER.search(line)
        if fold:
            folder = fold.group(1)
            continue
        hit = LIST_FILE.match(line.strip())
        if hit and folder:
            files.append({"folder": folder, "name": hit.group(2), "n": int(hit.group(1))})
    return files


def list_images(port):
    return parse_list_files(gp(["--list-files"], port=port, timeout=45))


def list_cards(have):
    with ThreadPoolExecutor(max_workers=len(have) or 1) as pool:
        futs = {role: pool.submit(list_images, have[role]["port"]) for role in have}
        return {role: fut.result() for role, fut in futs.items()}


def _file_key(row):
    return (row["folder"], row["name"])


def wait_new_images(port, before, timeout=25, interval=0.45, list_fn=None):
    """Poll the card until a new file appears after a remote / GPIO fire."""
    seen = {_file_key(row) for row in before}
    list_fn = list_images if list_fn is None else list_fn
    deadline = time.perf_counter() + timeout
    last = None
    while time.perf_counter() < deadline:
        try:
            now = list_fn(port)
            new = [row for row in now if _file_key(row) not in seen]
            if new:
                return new
            last = None
        except CamError as exc:
            last = exc
        time.sleep(interval)
    if last:
        raise last
    raise CamError("GPIO fired; no new file on the card")


def _download_one(port, row, dest_path):
    gp(
        [
            "--folder",
            row["folder"],
            "--get-file",
            str(row["n"]),
            "--force-overwrite",
            f"--filename={dest_path}",
        ],
        port=port,
        timeout=180,
    )


def pull_role(role, port, before, dest, stamp, list_fn=None):
    new = wait_new_images(port, before, list_fn=list_fn)
    dest.mkdir(parents=True, exist_ok=True)
    saved = []
    for row in sorted(new, key=lambda item: (item["folder"], -item["n"])):
        ext = Path(row["name"]).suffix.lower() or ".jpg"
        out = dest / f"{role}_{stamp}{ext}"
        if out.exists():
            out = dest / f"{role}_{stamp}_{Path(row['name']).stem}{ext}"
        last = None
        for _ in range(4):
            try:
                _download_one(port, row, out)
                last = None
                break
            except CamError as exc:
                last = exc
                time.sleep(0.45)
        if last:
            raise last
        saved.append(out.name)
    return saved


def pull_new(have, before, dest, stamp):
    with ThreadPoolExecutor(max_workers=len(have) or 1) as pool:
        futs = {
            role: pool.submit(
                pull_role, role, have[role]["port"], before[role], dest, stamp
            )
            for role in have
        }
        return {role: fut.result() for role, fut in futs.items()}


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
    s.add_argument("--fstop", help="lens f-number, e.g. 5.6")
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
