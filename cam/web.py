#!/usr/bin/env python3
"""Field + lab control pages for the two bodies.

  python3 cam/web.py
  iPhone (same Wi-Fi):  http://<lan-ip>:8787/
  laptop debugger:      http://127.0.0.1:8787/lab
"""

from __future__ import annotations

import atexit
import json
import os
import re
import socket
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import brightness
import dual
import gpio
import link
import live
import pano
import settings
import wifi

HERE = Path(__file__).resolve().parent
LIVE = live.Live()
LINK = link.Link(LIVE)
PORT = 8787
KIOSK_CHROME = "--class=duals-kiosk-chromium"


def _shutdown():
    LINK.stop()
    wifi.WATCH.stop()
    LIVE.stop()
    dual.ptp_hold(False)


atexit.register(_shutdown)


def lan_ips():
    found = []
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("1.1.1.1", 80))
        found.append(sock.getsockname()[0])
        sock.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip and not ip.startswith("127."):
                found.append(ip)
    except socket.gaierror:
        pass
    out = []
    for ip in found:
        if ip not in out:
            out.append(ip)
    return out


def urls_for(port):
    return [f"http://127.0.0.1:{port}/lab"] + [f"http://{ip}:{port}/" for ip in lan_ips()]


def _json(handler, code, payload):
    body = json.dumps(payload).encode()
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _html(handler, name):
    body = (HERE / name).read_bytes()
    handler.send_response(200)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_json(handler):
    n = int(handler.headers.get("Content-Length") or 0)
    if n == 0:
        return {}
    return json.loads(handler.rfile.read(n))


def _stop_live():
    LINK.set_live(False)


def _live_message(snap):
    if not snap["roles"]:
        return "live view off"
    bits = []
    for role, info in snap["roles"].items():
        if info["alive"]:
            bits.append(f"{role} {info['frames']}f")
        else:
            bits.append(f"{role} stopped" + (f" ({info['error']})" if info["error"] else ""))
    return "  ".join(bits)


def _kiosk_stop_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(runtime) / "duals-kiosk.stop"


def _kiosk_running():
    return subprocess.run(
        ["pgrep", "-f", "--", KIOSK_CHROME],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def _kiosk_enabled():
    return os.environ.get("DUALS_KIOSK") == "1" or _kiosk_running()


def _exit_kiosk():
    path = _kiosk_stop_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("1\n")
    except OSError as exc:
        raise dual.CamError(f"cannot write kiosk stop file: {exc}") from exc
    subprocess.run(["pkill", "-f", "--", KIOSK_CHROME], check=False)
    return {"ok": True, "message": "desktop"}


def _maybe_sync(have, prefs):
    if not prefs.get("sync", True) or len(have) < 2:
        return ""
    try:
        return dual.copy_from_master(have, prefs.get("master") or "T").get("message") or ""
    except dual.CamError as exc:
        return str(exc)


def _align_for_shot(have, prefs, assignments):
    """Meter T (or master), freeze those numbers on both; else app/sync."""
    if not have:
        return assignments, ""
    if prefs.get("lock_t", True) and len(have) >= 2:
        try:
            info = dual.lock_from_master(have, prefs.get("master") or "T")
            return info.get("assignments") or [], info.get("message") or ""
        except dual.CamError as exc:
            copied = str(exc)
            if assignments:
                _apply_exposure(have, assignments)
                return assignments, copied
            return assignments, copied or _maybe_sync(have, prefs)
    if assignments:
        _apply_exposure(have, assignments)
        packed = dual.pack_assignments(assignments)
        return assignments, " ".join(f"{k}={v}" for k, v in packed)
    return assignments, _maybe_sync(have, prefs)


def _merge_exposure(data, prefs):
    data = data if isinstance(data, dict) else {}
    prefs = prefs or {}
    out = {}
    for key in settings.EXPOSURE:
        val = data.get(key)
        if val is None or str(val).strip() == "":
            val = prefs.get(key)
        val = str(val).strip() if val is not None else ""
        if val:
            out[key] = val
    return out


def _apply_exposure(have, assignments, fast=False):
    notes = []
    if not assignments or not have:
        return notes
    from concurrent.futures import ThreadPoolExecutor

    timeout = 45
    with ThreadPoolExecutor(max_workers=len(have)) as pool:
        futs = [
            pool.submit(dual._set_one, row["port"], assignments, timeout)
            for row in have.values()
        ]
        for fut in futs:
            notes.extend(fut.result() or [])
    return notes


def _status_now(rows):
    rows = list(rows or [])
    if not rows:
        return [], []
    from concurrent.futures import ThreadPoolExecutor

    with ThreadPoolExecutor(max_workers=len(rows)) as pool:
        blocks = list(pool.map(dual._status_one, rows))
    by_port = {b.get("port"): b for b in blocks}
    cameras = []
    for row in rows:
        extra = dict(row)
        got = by_port.get(row["port"]) or {}
        for key, val in got.items():
            if val:
                extra[key] = val
        cameras.append(extra)
    attach_usb_speed(cameras)
    return cameras, blocks


def _shot_files(saved=None, dest=None, stamp=None):
    names = []
    if saved:
        for role in sorted(saved):
            names.extend(saved[role] or [])
        return names
    if dest and stamp:
        for path in sorted(Path(dest).glob(f"*_{stamp}.*")):
            if path.suffix.lower() in (".jpg", ".jpeg", ".png"):
                names.append(path.name)
    return names


def _assignments(data):
    out = []
    for src, key in (
        ("program", "expprogram"),
        ("iso", "iso"),
        ("shutter", "shutterspeed"),
        ("fstop", "f-number"),
        ("wb", "whitebalance"),
        ("quality", "imagequality"),
    ):
        val = (data.get(src) or "").strip()
        if not val:
            continue
        if key == "expprogram" and val not in ("M", "A", "S", "P"):
            continue
        if key == "iso":
            if val.lower() == "auto":
                out.append(("isoauto", "On"))
                out.append(("autoiso", "On"))
            else:
                iso = val.replace("ISO", "").replace("iso", "").strip()
                out.append(("isoauto", "Off"))
                out.append(("autoiso", "Off"))
                out.append(("iso", iso or val))
            continue
        if key == "shutterspeed":
            if val.lower() == "auto":
                continue
            out.append((key, dual.format_shutter(val)))
            continue
        if key == "f-number":
            if val.lower() == "auto":
                continue
            out.append((key, dual.format_aperture(val)))
            continue
        out.append((key, val))
    return out


def _send_path(handler, path, ctype, download=None):
    body = Path(path).read_bytes()
    name = download or Path(path).name
    handler.send_response(200)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Cache-Control", "no-store")
    if download:
        handler.send_header("Content-Disposition", f'attachment; filename="{name}"')
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _send_jpeg(handler, payload):
    if not payload:
        handler.send_response(204)
        handler.end_headers()
        return
    handler.send_response(200)
    handler.send_header("Content-Type", "image/jpeg")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)


def _send_mjpeg(handler, role):
    handler.send_response(200)
    handler.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
    handler.send_header("Cache-Control", "no-cache, no-store")
    handler.end_headers()
    last = None
    idle = 0
    while True:
        jpeg = LIVE.jpeg(role)
        alive = LIVE.running().get(role, False)
        if jpeg is not None and jpeg is not last:
            last = jpeg
            idle = 0
            try:
                handler.wfile.write(
                    b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: "
                    + str(len(jpeg)).encode()
                    + b"\r\n\r\n"
                    + jpeg
                    + b"\r\n"
                )
                handler.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                return
        elif not alive:
            idle += 1
            if last is None or idle > 8:
                return
        time.sleep(0.05)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % (fmt % args))

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/field"):
            return _html(self, "field.html")
        if path == "/lab":
            return _html(self, "lab.html")
        try:
            if path == "/api/meta":
                port = self.server.server_address[1]
                phone = urls_for(port)
                lan = [u for u in phone if "127.0.0.1" not in u]
                return _json(
                    self, 200,
                    {
                        "lab": f"http://127.0.0.1:{port}/lab",
                        "phone": lan[0] if lan else f"http://127.0.0.1:{port}/",
                        "urls": phone,
                        "pair": dual.load_pair(),
                        "live": LIVE.snapshot(),
                        "gpio": gpio.snapshot(),
                        "settings": settings.load(),
                        "brightness": brightness.snapshot(),
                        "kiosk": _kiosk_enabled(),
                        "wifi": wifi.status(),
                        "link": LINK.snapshot(),
                    },
                )
            if path == "/api/health":
                return _json(self, 200, {"ok": True})
            if path == "/api/link":
                return _json(self, 200, LINK.snapshot())
            if path == "/api/wifi":
                return _json(self, 200, wifi.status())
            if path == "/api/brightness":
                snap = brightness.snapshot()
                msg = (
                    f"screen {snap['value']}%"
                    if snap.get("available")
                    else "no HDMI brightness"
                )
                return _json(self, 200, {**snap, "message": msg})
            if path == "/api/live":
                snap = LIVE.snapshot()
                return _json(self, 200, {**snap, "message": _live_message(snap)})
            m = re.fullmatch(r"/api/live/([TR])\.(jpg|mjpg)", path)
            if m:
                role, kind = m.group(1), m.group(2)
                if kind == "jpg":
                    return _send_jpeg(self, LIVE.jpeg(role))
                return _send_mjpeg(self, role)
            if path == "/api/captures":
                pairs = pano.list_pairs()
                n = sum(1 for row in pairs if row["ready"])
                return _json(
                    self, 200,
                    {
                        "pairs": pairs,
                        "jobs": pano.jobs_snapshot(),
                        "queue": pano.queue_status(),
                        "disk": pano.disk_stats(),
                        "message": f"{n} JPEG pair(s) in captures/",
                    },
                )
            if path == "/api/pano/job":
                q = parse_qs(urlparse(self.path).query)
                stamp = (q.get("stamp", [""])[0] or "").strip()
                return _json(
                    self, 200,
                    {
                        "job": pano.job_get(stamp) if stamp else {},
                        "jobs": pano.jobs_snapshot(),
                        "pairs": pano.list_pairs(),
                        "disk": pano.disk_stats(),
                    },
                )
            m = re.fullmatch(r"/api/file/([\w.-]+)", path)
            if m:
                q = parse_qs(urlparse(self.path).query)
                dl = (q.get("dl", [""])[0] or "").lower() in ("1", "true", "yes")
                width = q.get("w", [None])[0]
                try:
                    width = int(width) if width else None
                except ValueError:
                    raise dual.CamError("bad width")
                dest = pano.serve(m.group(1), None if dl else width)
                return _send_path(
                    self, dest, pano.content_type(dest),
                    download=m.group(1) if dl else None,
                )
            if path == "/api/detect":
                with LINK.usb():
                    rows = dual.detect_bodies()
                    LINK.absorb(rows)
                    cameras, blocks = _status_now(rows) if rows else ([], [])
                    if blocks:
                        LINK.set_hud(blocks)
                if not rows:
                    msg = "no cameras. Setup → USB → MTP/PTP, wake, plug USB."
                elif any(not row.get("serial") for row in rows):
                    msg = f"{len(rows)} body(ies) — no serial (USB busy). Detect again."
                else:
                    msg = f"{len(rows)} body(ies)"
                return _json(self, 200, {
                    "cameras": cameras or rows, "pair": dual.load_pair(),
                    "status": blocks, "link": LINK.snapshot(), "message": msg,
                })
            if path == "/api/status":
                with LINK.usb():
                    rows = dual.detect_bodies()
                    LINK.absorb(rows)
                    if not rows:
                        raise dual.CamError("no cameras")
                    cameras, blocks = _status_now(rows)
                    if blocks:
                        LINK.set_hud(blocks)
                lines = []
                for b in blocks:
                    lines.append(
                        f"{b.get('role')}  {b.get('expprogram') or '-'}  "
                        f"iso={b.get('iso')}  shutter={b.get('shutterspeed')}  "
                        f"f={b.get('f-number') or '-'}  "
                        f"auto={b.get('isoauto') or b.get('autoiso') or '-'}  "
                        f"wb={b.get('whitebalance') or '-'}  bat={b.get('batterylevel')}  "
                        f"{b.get('port')}"
                    )
                return _json(
                    self, 200,
                    {"cameras": cameras, "status": blocks, "pair": dual.load_pair(),
                     "link": LINK.snapshot(),
                     "message": "\n".join(lines)},
                )
        except dual.CamError as exc:
            return _json(self, 400, {"error": str(exc)})
        return _json(self, 404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            data = _read_json(self)
            if path == "/api/kiosk/exit":
                return _json(self, 200, _exit_kiosk())
            if path == "/api/wifi/scan":
                return _json(self, 200, wifi.scan())
            if path == "/api/wifi/join":
                ssid = str(data.get("ssid") or "").strip()
                psk = str(data.get("psk") or "")
                return _json(self, 200, wifi.join(ssid, psk))
            if path == "/api/wifi/ap":
                val = data.get("on")
                if isinstance(val, str):
                    on = val.lower() not in ("0", "false", "no", "")
                else:
                    on = bool(val)
                return _json(self, 200, wifi.set_ap(on))
            if path == "/api/brightness":
                snap = brightness.set(data.get("value"))
                settings.save({"brightness": snap["value"]})
                return _json(
                    self, 200,
                    {**snap, "message": f"screen {snap['value']}%"},
                )
            if path == "/api/settings":
                prefs = settings.save(data)
                return _json(
                    self, 200,
                    {**prefs, "message": (
                        "settings  download="
                        + ("on" if prefs["download"] else "off")
                        + "  gpio="
                        + ("on" if prefs["gpio"] else "off")
                        + "  flop="
                        + ("on" if prefs["flip_r"] else "off")
                        + "  deghost="
                        + ("on" if prefs.get("deghost") else "off")
                        + "  balance="
                        + ("on" if prefs.get("balance", True) else "off")
                        + "  live-ae="
                        + ("cam" if prefs.get("follow_cam") else "app")
                        + "  lock-t="
                        + ("on" if prefs.get("lock_t", True) else "off")
                        + f"  ol={prefs['overlap']:.0%}"
                        + "  master="
                        + prefs.get("master", "T")
                        + "  sync="
                        + ("on" if prefs.get("sync") else "off")
                        + f"  preview={prefs.get('preview_s', settings.PREVIEW_S)}s"
                        + f"  idle={prefs.get('idle_min', settings.IDLE_MIN)}m"
                    )},
                )
            if path == "/api/idle":
                on = data.get("idle")
                if isinstance(on, str):
                    on = on.lower() not in ("0", "false", "no", "")
                LINK.set_idle(bool(on))
                snap = LINK.snapshot()
                return _json(
                    self, 200,
                    {
                        **snap,
                        "idle": bool(on),
                        "message": "idle  live off  slow poll" if on else "idle off",
                    },
                )
            if path == "/api/gpio":
                if "sim" not in data:
                    raise dual.CamError("need sim")
                val = data["sim"]
                if isinstance(val, str):
                    on = val.lower() not in ("0", "false", "no", "")
                else:
                    on = bool(val)
                snap = gpio.set_sim(on)
                return _json(
                    self, 200,
                    {
                        **snap,
                        "message": (
                            "sim as Pi — 同期 GPIO on VIEW"
                            if snap["sim"]
                            else "sim off"
                        ),
                    },
                )
            if path == "/api/pair":
                if data.get("swap"):
                    saved = dual.swap_pair()
                else:
                    has_t, has_r = "t" in data, "r" in data
                    if not has_t and not has_r:
                        raise dual.CamError("need a T or R serial")
                    t = str(data.get("t") or "").strip() if has_t else None
                    r = str(data.get("r") or "").strip() if has_r else None
                    saved = dual.save_pair(t, r, replace=False)
                bits = "  ".join(f"{k}={v}" for k, v in saved.items()) or "(cleared)"
                with LINK.usb():
                    rows = dual.detect_bodies()
                    LINK.absorb(rows)
                    cameras, blocks = _status_now(rows) if rows else ([], [])
                    if blocks:
                        LINK.set_hud(blocks)
                return _json(self, 200, {
                    "message": f"paired {bits}",
                    "pair": saved,
                    "cameras": cameras,
                    "status": blocks,
                    "link": LINK.snapshot(),
                })
            if path == "/api/live/start":
                LINK.set_live(True)
                deadline = time.time() + 8.0
                snap = LINK.snapshot()
                while time.time() < deadline:
                    snap = LINK.snapshot()
                    roles = snap.get("roles") or {}
                    if any((roles.get(role) or {}).get("live") for role in ("T", "R")):
                        break
                    time.sleep(0.15)
                missing = snap.get("missing") or []
                ok = any(
                    (snap.get("roles") or {}).get(role, {}).get("live")
                    for role in ("T", "R")
                )
                msg = snap.get("message") or "live"
                if missing:
                    msg += "  missing " + " ".join(missing)
                return _json(
                    self, 200,
                    {**snap, "ok": ok, "message": msg, "live": LIVE.snapshot()},
                )
            if path == "/api/live/stop":
                _stop_live()
                return _json(self, 200, {
                    "message": "live view stopped",
                    "link": LINK.snapshot(),
                })
            if path == "/api/set":
                prefs = settings.load()
                follow = bool(prefs.get("follow_cam")) and not data.get("force")
                exp = _merge_exposure(data, prefs)
                assignments = [] if follow else _assignments(exp or data)
                if not follow and not assignments:
                    raise dual.CamError("nothing to set")
                if exp and not follow:
                    settings.save(exp)
                if assignments:
                    LINK.remember(assignments)
                with LINK.usb():
                    have = dict(LINK.have())
                    if not have:
                        have = dual.require_online(dual.detect_bodies())
                        LINK.absorb(have.values())
                    notes = _apply_exposure(have, assignments)
                    cameras, blocks = _status_now(list(have.values()))
                    if blocks:
                        LINK.set_hud(blocks)
                roles = " and ".join(sorted(have))
                if follow:
                    msg = f"live AE  camera decides  {roles}"
                else:
                    msg = "set " + " ".join(f"{k}={v}" for k, v in assignments) + f" on {roles}"
                if notes:
                    msg += "  (" + "; ".join(notes)
                    if any(n.startswith("expprogram=") for n in notes):
                        msg += " — turn the mode dial to M"
                    if any(n.startswith("f-number=") for n in notes):
                        msg += " — f/ needs A or M, or a CPU lens"
                    msg += ")"
                return _json(
                    self, 200,
                    {
                        "message": msg,
                        "cameras": cameras,
                        "status": blocks,
                        "pair": dual.load_pair(),
                        "link": LINK.snapshot(),
                    },
                )
            if path == "/api/shoot":
                from concurrent.futures import ThreadPoolExecutor
                from datetime import datetime

                with LINK.usb():
                    prefs = settings.load()
                    follow = bool(prefs.get("follow_cam"))
                    exp = _merge_exposure(data, prefs)
                    if exp and not follow:
                        settings.save(exp)
                        prefs = settings.load()
                    assignments = [] if follow else _assignments(exp)
                    if assignments:
                        LINK.remember(assignments)
                    preview_s = prefs.get("preview_s", settings.PREVIEW_S)
                    target = (data.get("target") or "").strip() or settings.shoot_target(prefs)

                    def shot_json(message, files=None, stamp=""):
                        return _json(
                            self, 200,
                            {
                                "message": message,
                                "files": files or [],
                                "stamp": stamp,
                                "preview_s": preview_s,
                            },
                        )

                    if target == "gpio":
                        snap = gpio.snapshot()
                        if not snap["available"]:
                            raise dual.CamError("GPIO shutter is only on a Raspberry Pi")
                        if not snap["pi"]:
                            info = gpio.fire()
                            return shot_json(
                                f"gpio sim  BCM {info['pin']}  (no pulse)  "
                                "on a Pi: Y-lead fire"
                                + (
                                    ", then USB download → captures/"
                                    if prefs["download"]
                                    else ", files stay on cards"
                                ),
                            )
                        have = None
                        try:
                            have = dual.require_online(dual.detect_bodies())
                        except dual.CamError:
                            have = None
                        copied = ""
                        clock_msg = ""
                        if have:
                            try:
                                clock_msg = (dual.sync_clocks(have) or {}).get("message") or ""
                            except dual.CamError:
                                clock_msg = ""
                            assignments, copied = _align_for_shot(have, prefs, assignments)
                        if not prefs["download"]:
                            info = gpio.fire()
                            return shot_json(
                                f"gpio {info['pin']}  {info['ms']}ms  {info['backend']}"
                                "  cards"
                                + (f"  {copied}" if copied else ""),
                            )
                        if not have:
                            raise dual.CamError("no cameras")
                        LINK.absorb(have.values())
                        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        dest = pano.CAPTURES
                        before = dual.list_cards(have)
                        info = gpio.fire()
                        saved = dual.pull_new(have, before, dest, stamp)
                        bits = "  ".join(
                            f"{role} {','.join(saved[role])}" for role in sorted(saved)
                        )
                        pano.refresh_exif(dest, stamp)
                        return shot_json(
                            f"gpio {info['pin']}  {info['ms']}ms  {info['backend']}"
                            f"  → {bits}"
                            + (f"  {copied}" if copied else ""),
                            _shot_files(saved=saved),
                            stamp,
                        )
                    have = dual.require_online(dual.detect_bodies())
                    LINK.absorb(have.values())
                    clock_msg = ""
                    try:
                        clock_msg = (dual.sync_clocks(have) or {}).get("message") or ""
                    except dual.CamError:
                        clock_msg = ""
                    assignments, copied = _align_for_shot(have, prefs, assignments)
                    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    dest = pano.CAPTURES
                    with ThreadPoolExecutor(max_workers=len(have)) as pool:
                        if target == "card":
                            futs = [
                                pool.submit(
                                    dual._shoot_card,
                                    role,
                                    have[role]["port"],
                                    assignments,
                                )
                                for role in have
                            ]
                        else:
                            futs = [
                                pool.submit(
                                    dual._shoot_one,
                                    role,
                                    have[role]["port"],
                                    dest,
                                    stamp,
                                    assignments,
                                )
                                for role in have
                            ]
                        times = [fut.result() for fut in futs]
                    msg = "  ".join(f"{role} {dt:.2f}s" for role, dt in times)
                    where = "cards" if target == "card" else "captures/"
                    files = []
                    if target != "card":
                        pano.refresh_exif(dest, stamp)
                        files = _shot_files(dest=dest, stamp=stamp)
                    return shot_json(
                        f"shot {stamp}  {msg}  → {where}"
                        + (f"  {copied}" if copied else "")
                        + (f"  {clock_msg}" if clock_msg else ""),
                        files,
                        stamp,
                    )
            if path == "/api/captures/delete":
                stamp = (data.get("stamp") or "").strip()
                side = (data.get("side") or "").strip().upper()
                info = pano.delete_stamp(stamp, sides=[side] if side else None)
                return _json(
                    self, 200,
                    {
                        **info,
                        "pairs": pano.list_pairs(),
                        "disk": pano.disk_stats(),
                        "message": f"deleted {stamp}" + (f" {side}" if side else "")
                        + f"  ({info['count']} file(s))",
                    },
                )
            if path == "/api/captures/before-today":
                info = pano.delete_before_today()
                return _json(
                    self, 200,
                    {
                        **info,
                        "pairs": pano.list_pairs(),
                        "disk": pano.disk_stats(),
                        "message": f"removed {info['count']} before {info['today']}",
                    },
                )
            if path == "/api/captures/keep-last":
                info = pano.keep_last(data.get("n", 5))
                return _json(
                    self, 200,
                    {
                        **info,
                        "pairs": pano.list_pairs(),
                        "disk": pano.disk_stats(),
                        "message": f"kept {len(info['kept'])}, removed {info['count']}",
                    },
                )
            if path == "/api/captures/protect":
                stamp = (data.get("stamp") or "").strip()
                on = data.get("protected")
                if isinstance(on, str):
                    on = on.lower() not in ("0", "false", "no", "")
                info = pano.set_protected(stamp, bool(on))
                return _json(
                    self, 200,
                    {
                        **info,
                        "pairs": pano.list_pairs(),
                        "disk": pano.disk_stats(),
                        "message": (
                            f"protected {stamp}" if info["protected"]
                            else f"unlocked {stamp}"
                        ),
                    },
                )
            if path == "/api/captures/delete-unprotected":
                info = pano.delete_unprotected()
                return _json(
                    self, 200,
                    {
                        **info,
                        "pairs": pano.list_pairs(),
                        "disk": pano.disk_stats(),
                        "message": (
                            f"deleted {info['count']}"
                            + (f"  kept {len(info['skipped'])} locked" if info["skipped"] else "")
                        ),
                    },
                )
            if path == "/api/pano":
                stamp = (data.get("stamp") or "").strip()
                if not stamp:
                    raise dual.CamError("select a T/R pair")
                prefs = settings.load()
                try:
                    overlap = data.get("overlap")
                    if overlap is None:
                        overlap = prefs.get("overlap", pano.OVERLAP)
                    overlap = float(overlap)
                except (TypeError, ValueError):
                    raise dual.CamError("bad overlap")
                flip_r = data.get("flip_r")
                if flip_r is None:
                    flip_r = prefs.get("flip_r", False)
                if isinstance(flip_r, str):
                    flip_r = flip_r.lower() not in ("0", "false", "no", "")
                deghost = data.get("deghost")
                if deghost is None:
                    deghost = prefs.get("deghost", False)
                if isinstance(deghost, str):
                    deghost = deghost.lower() not in ("0", "false", "no", "")
                balance = data.get("balance")
                if balance is None:
                    balance = prefs.get("balance", True)
                if isinstance(balance, str):
                    balance = balance.lower() not in ("0", "false", "no", "")
                mode = (data.get("mode") or "open").strip().lower()
                job = pano.start_stitch(
                    stamp, overlap=overlap, flip_r=bool(flip_r), mode=mode,
                    deghost=bool(deghost), balance=bool(balance),
                )
                stat = pano.queue_status()
                return _json(
                    self, 200,
                    {
                        **job,
                        "queue": stat,
                        "message": stat.get("message")
                        or job.get("message")
                        or f"queued {mode} {stamp}",
                    },
                )
        except dual.CamError as exc:
            return _json(self, 400, {"error": str(exc)})
        return _json(self, 404, {"error": "not found"})


class Server(ThreadingHTTPServer):
    allow_reuse_address = True


def main():
    dual.ptp_hold(True)
    port = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    httpd = Server(("0.0.0.0", port), Handler)
    print("field (iPhone)  " + "  ".join(u for u in urls_for(port) if "/lab" not in u))
    print(f"lab  (laptop)   http://127.0.0.1:{port}/lab")
    if gpio.on_pi():
        print(f"gpio           BCM {gpio.PIN} high {int(gpio.PULSE_S * 1000)}ms then USB download")
    elif gpio.sim_on():
        print("gpio           sim (USB tab) — no pulse on this Mac")
    print("ptpcamerad held down (python3 cam/dual.py ptp-on to restore Photos)")
    brightness.restore(settings.load().get("brightness"))
    pano.warmup_open()
    LINK.start()
    print("usb            link thread watching T/R")
    if gpio.on_pi():
        wifi.WATCH.start()
        print("wifi           watch thread pinging gateway")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
