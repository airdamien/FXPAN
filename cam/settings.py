"""Persist field/lab switches. Missing file uses Pi-aware defaults."""

from __future__ import annotations

import json
from pathlib import Path

import gpio

PATH = Path(__file__).resolve().parent / "settings.json"
KEYS = ("download", "gpio")


def defaults(pi=None):
    on = gpio.on_pi() if pi is None else bool(pi)
    return {"download": on, "gpio": on}


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
    for key in KEYS:
        if key in data:
            out[key] = bool(data[key])
    return out


def save(data, pi=None):
    out = load(pi)
    if not isinstance(data, dict):
        data = {}
    for key in KEYS:
        if key not in data:
            continue
        val = data[key]
        if isinstance(val, str):
            out[key] = val.lower() not in ("0", "false", "no", "")
        else:
            out[key] = bool(val)
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
