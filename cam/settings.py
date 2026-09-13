"""Persist field/lab switches. Missing file uses Pi-aware defaults."""

from __future__ import annotations

import json
from pathlib import Path

import gpio

PATH = Path(__file__).resolve().parent / "settings.json"
BOOLS = ("download", "gpio", "flip_r", "sync")
OVERLAP = 0.20


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


def _overlap(val):
    try:
        n = float(val)
    except (TypeError, ValueError):
        return None
    if n > 1:
        n = n / 100.0
    if n < 0.05 or n > 0.45:
        return None
    return n


def defaults(pi=None):
    on = gpio.on_pi() if pi is None else bool(pi)
    return {
        "download": on, "gpio": on, "flip_r": False, "overlap": OVERLAP,
        "sync": True, "master": "T",
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
    if "master" in data:
        m = _master(data["master"])
        if m:
            out["master"] = m
    if "brightness" in data:
        b = _brightness(data["brightness"])
        if b is not None:
            out["brightness"] = b
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
    if "master" in data:
        m = _master(data["master"])
        if m:
            out["master"] = m
    if "brightness" in data:
        b = _brightness(data["brightness"])
        if b is not None:
            out["brightness"] = b
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
