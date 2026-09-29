"""Persist field/lab switches. Missing file uses Pi-aware defaults."""

from __future__ import annotations

import json
from pathlib import Path

import gpio

PATH = Path(__file__).resolve().parent / "settings.json"
STITCH_MODES = ("match", "blend", "cut", "open", "hugin")
BOOLS = (
    "download", "gpio", "flip_r", "sync", "lock_t", "deghost", "balance",
    "follow_cam", "crop_inner", "keep_card", "stitch_raw", "raw_look", "bulb",
)
EXPOSURE = ("iso", "shutter", "fstop", "wb", "quality", "program")
OVERLAP = 0.20
PREVIEW_S = 10
IDLE_MIN = 10
ANA_SQUEEZE = (1.0, 1.33, 1.5, 2.0)


def _master(val):
    s = str(val or "").strip().upper()
    return s if s in ("T", "R") else None


def _brightness(val):
    try:
        n = int(round(float(val)))
    except (TypeError, ValueError):
        return None
    if n < 1 or n > 100:
        return None
    return n


def _stitch_mode(val):
    s = str(val or "").strip().lower()
    return s if s in STITCH_MODES else None


def _overlap(val):
    try:
        n = float(val)
    except (TypeError, ValueError):
        return None
    if n > 1:
        n = n / 100.0
    if n < 0.05 or n > 0.50:
        return None
    return n


def _preview_s(val):
    try:
        n = int(round(float(val)))
    except (TypeError, ValueError):
        return None
    if n < 0 or n > 15:
        return None
    return n


def _idle_min(val):
    try:
        n = int(round(float(val)))
    except (TypeError, ValueError):
        return None
    if n < 0 or n > 60:
        return None
    return n


def _ana_squeeze(val):
    s = str(val or "").strip().lower()
    if s in ("off", "0", "false", "no"):
        return 1.0
    try:
        n = float(val)
    except (TypeError, ValueError):
        return None
    if n < 1.05:
        return 1.0
    if n > 2.5:
        return None
    return min(ANA_SQUEEZE[1:], key=lambda x: abs(x - n))


def _iso(val):
    s = str(val or "").replace("ISO", "").replace("iso", "").strip()
    if not s:
        return None
    if s.lower() == "auto":
        return "Auto"
    if s.isdigit():
        return s
    return None


def _fstop(val):
    s = str(val or "").strip()
    if not s:
        return None
    if s.lower() == "auto":
        return "Auto"
    t = s.lower().replace(" ", "").replace("f/", "").replace("f", "")
    try:
        n = float(t)
    except ValueError:
        return None
    if n <= 0 or n > 64:
        return None
    if abs(n - round(n)) < 0.05:
        return str(int(round(n)))
    return f"{n:.1f}".rstrip("0").rstrip(".")


def _exposure_val(key, val):
    if key == "iso":
        return _iso(val)
    if key == "fstop":
        return _fstop(val)
    s = str(val or "").strip()
    if not s or len(s) > 40:
        return None
    if key == "program" and s not in ("M", "A", "S", "P", "Auto"):
        return None
    return s


def defaults(pi=None):
    on = gpio.on_pi() if pi is None else bool(pi)
    return {
        "download": on, "gpio": on, "flip_r": False, "overlap": OVERLAP,
        "sync": True, "lock_t": True, "master": "T", "preview_s": PREVIEW_S,
        "idle_min": IDLE_MIN, "deghost": False, "balance": True, "follow_cam": False,
        "bulb": False,
        "stitch_mode": "hugin" if on else "open",
        "crop_inner": True, "keep_card": False, "stitch_raw": False, "raw_look": True,
        "ana_squeeze": 1.0,
    }


def load(pi=None):
    out = defaults(pi)
    if not PATH.is_file():
        return out
    try:
        data = json.loads(PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return out
    if not isinstance(data, dict):
        return out
    for key in BOOLS:
        if key in data:
            out[key] = bool(data[key])
    if "overlap" in data:
        ol = _overlap(data["overlap"])
        if ol is not None:
            out["overlap"] = ol
    if "stitch_mode" in data:
        mode = _stitch_mode(data["stitch_mode"])
        if mode:
            out["stitch_mode"] = mode
    if "master" in data:
        m = _master(data["master"])
        if m:
            out["master"] = m
    if "brightness" in data:
        b = _brightness(data["brightness"])
        if b is not None:
            out["brightness"] = b
    if "preview_s" in data:
        n = _preview_s(data["preview_s"])
        if n is not None:
            out["preview_s"] = n
    if "idle_min" in data:
        n = _idle_min(data["idle_min"])
        if n is not None:
            out["idle_min"] = n
    if "ana_squeeze" in data:
        n = _ana_squeeze(data["ana_squeeze"])
        if n is not None:
            out["ana_squeeze"] = n
    for key in EXPOSURE:
        if key not in data:
            continue
        val = _exposure_val(key, data[key])
        if val is not None:
            out[key] = val
    return out


def save(data, pi=None):
    out = load(pi)
    if not isinstance(data, dict):
        data = {}
    for key in BOOLS:
        if key not in data:
            continue
        val = data[key]
        if isinstance(val, str):
            out[key] = val.lower() not in ("0", "false", "no", "")
        else:
            out[key] = bool(val)
    if "overlap" in data:
        ol = _overlap(data["overlap"])
        if ol is not None:
            out["overlap"] = ol
    if "stitch_mode" in data:
        mode = _stitch_mode(data["stitch_mode"])
        if mode:
            out["stitch_mode"] = mode
    if "master" in data:
        m = _master(data["master"])
        if m:
            out["master"] = m
    if "brightness" in data:
        b = _brightness(data["brightness"])
        if b is not None:
            out["brightness"] = b
    if "preview_s" in data:
        n = _preview_s(data["preview_s"])
        if n is not None:
            out["preview_s"] = n
    if "idle_min" in data:
        n = _idle_min(data["idle_min"])
        if n is not None:
            out["idle_min"] = n
    if "ana_squeeze" in data:
        n = _ana_squeeze(data["ana_squeeze"])
        if n is not None:
            out["ana_squeeze"] = n
    for key in EXPOSURE:
        if key not in data:
            continue
        val = _exposure_val(key, data[key])
        if val is not None:
            out[key] = val
    PATH.write_text(json.dumps(out) + "\n")
    return out


def shoot_target(prefs=None, snap=None):
    prefs = prefs if prefs is not None else load()
    snap = snap if snap is not None else gpio.snapshot()
    if prefs.get("gpio") and snap.get("available"):
        return "gpio"
    if prefs.get("download"):
        return "download"
    return "card"
