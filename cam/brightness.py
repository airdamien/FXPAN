"""HDMI panel backlight via DDC/CI VCP 0x10. No ddcutil."""

from __future__ import annotations

import fcntl
import os
import time
from pathlib import Path

import dual

DRM = Path("/sys/class/drm")
I2C_SLAVE = 0x0703
DDC = 0x37
HOST = 0x51
SRC = 0x6E
VCP_BRIGHT = 0x10
MIN = 1
MAX = 100


def _xor(bs):
    x = 0
    for b in bs:
        x ^= b
    return x


def _frame(payload):
    return bytes(payload) + bytes([_xor([SRC, *payload])])


def parse_getvcp(data, code=VCP_BRIGHT):
    if not data or len(data) < 11:
        raise dual.CamError("ddc short read")
    if data[2] != 0x02 or data[3] != 0 or data[4] != code:
        raise dual.CamError("ddc get failed")
    mx = (data[6] << 8) | data[7]
    cur = (data[8] << 8) | data[9]
    if mx <= 0:
        mx = MAX
    return cur, mx


def clamp(val, mx=MAX):
    try:
        n = int(round(float(val)))
    except (TypeError, ValueError):
        return None
    hi = int(mx) if mx else MAX
    if n < MIN:
        n = MIN
    if n > hi:
        n = hi
    return n


def invert(val, mx=MAX):
    """This scaler treats VCP 0x10 backwards: 0 is brightest."""
    n = clamp(val, mx)
    if n is None:
        return None
    hi = int(mx) if mx else MAX
    return clamp(hi - n, hi)


def find_bus(drm=None):
    root = Path(drm or DRM)
    if not root.is_dir():
        return None
    for con in sorted(root.glob("card*-HDMI-A-*")):
        try:
            status = (con / "status").read_text().strip()
        except OSError:
            continue
        if status != "connected":
            continue
        ddc = con / "ddc"
        try:
            name = ddc.resolve().name
        except OSError:
            continue
        if name.startswith("i2c-"):
            try:
                return int(name.split("-", 1)[1])
            except ValueError:
                continue
    return None


def _open(bus):
    path = f"/dev/i2c-{bus}"
    try:
        fd = os.open(path, os.O_RDWR)
    except OSError as exc:
        raise dual.CamError(f"cannot open {path}") from exc
    try:
        fcntl.ioctl(fd, I2C_SLAVE, DDC)
    except OSError as exc:
        os.close(fd)
        raise dual.CamError(f"ddc busy on i2c-{bus}") from exc
    return fd


def _get(fd):
    os.write(fd, _frame([HOST, 0x82, 0x01, VCP_BRIGHT]))
    time.sleep(0.05)
    return parse_getvcp(os.read(fd, 11))


def _set(fd, value):
    os.write(fd, _frame([HOST, 0x84, 0x03, VCP_BRIGHT, 0x00, value & 0xFF]))
    time.sleep(0.08)


def snapshot(drm=None):
    bus = find_bus(drm)
    if bus is None:
        return {"available": False, "value": None, "max": MAX, "bus": None}
    fd = None
    try:
        fd = _open(bus)
        cur, mx = _get(fd)
    except (OSError, dual.CamError):
        return {"available": False, "value": None, "max": MAX, "bus": bus}
    finally:
        if fd is not None:
            os.close(fd)
    return {"available": True, "value": invert(cur, mx), "max": int(mx), "bus": bus}


def set(value, drm=None):
    n = clamp(value)
    if n is None:
        raise dual.CamError("brightness is 1–100")
    bus = find_bus(drm)
    if bus is None:
        raise dual.CamError("no HDMI panel")
    fd = _open(bus)
    try:
        _cur, mx = _get(fd)
        _set(fd, invert(n, mx))
        cur, mx = _get(fd)
    except OSError as exc:
        raise dual.CamError("ddc set failed") from exc
    finally:
        os.close(fd)
    return {"available": True, "value": invert(cur, mx), "max": int(mx), "bus": bus}


def restore(value, drm=None):
    if value is None:
        return
    n = clamp(value)
    if n is None:
        return
    try:
        set(n, drm=drm)
    except dual.CamError:
        pass
