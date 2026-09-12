#!/usr/bin/env python3
"""Field + lab control pages for the two bodies.

  python3 cam/web.py
  iPhone (same Wi-Fi):  http://<lan-ip>:8787/
  laptop debugger:      http://127.0.0.1:8787/lab
"""

from __future__ import annotations

import atexit
import json
import re
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dual
import live
import pano

HERE = Path(__file__).resolve().parent
LIVE = live.Live()
PORT = 8787


def _shutdown():
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
    LIVE.stop()


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


def _assignments(data):
    out = []
    for src, key in (
        ("program", "expprogram"),
        ("iso", "iso"),
        ("shutter", "shutterspeed"),
        ("wb", "whitebalance"),
        ("quality", "imagequality"),
    ):
        val = (data.get(src) or "").strip()
        if not val:
            continue
        if key == "expprogram" and val not in ("M", "A", "S", "P"):
            continue
        out.append((key, val))
    return out


def _send_path(handler, path, ctype):
    body = Path(path).read_bytes()
    handler.send_response(200)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Cache-Control", "no-store")
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
                    },
                )
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
                    {"pairs": pairs, "message": f"{n} JPEG pair(s) in captures/"},
                )
            m = re.fullmatch(r"/api/file/([\w.-]+)", path)
            if m:
                q = parse_qs(urlparse(self.path).query)
                width = q.get("w", [None])[0]
                try:
                    width = int(width) if width else None
                except ValueError:
                    raise dual.CamError("bad width")
                dest = pano.serve(m.group(1), width)
                return _send_path(self, dest, pano.content_type(dest))
            if path == "/api/detect":
                _stop_live()
                rows = dual.detect_bodies()
                msg = (
                    f"{len(rows)} body(ies)"
                    if rows
                    else "no cameras. Setup → USB → MTP/PTP, wake, plug USB."
                )
                return _json(self, 200, {"cameras": rows, "pair": dual.load_pair(), "message": msg})
            if path == "/api/status":
                _stop_live()
                rows = dual.detect_bodies()
                if not rows:
                    raise dual.CamError("no cameras")
                from concurrent.futures import ThreadPoolExecutor

                with ThreadPoolExecutor(max_workers=len(rows)) as pool:
                    blocks = list(pool.map(dual._status_one, rows))
                by_port = {b.get("port"): b for b in blocks}
                for row in rows:
                    extra = by_port.get(row["port"]) or {}
                    for key in (
                        "iso", "shutterspeed", "batterylevel", "imagequality",
                        "whitebalance", "expprogram", "exposurecompensation",
                        "focusmode", "focusmode2", "meteringmode", "availableshots",
                    ):
                        if extra.get(key):
                            row[key] = extra[key]
                lines = []
                for b in blocks:
                    lines.append(
                        f"{b.get('role')}  {b.get('expprogram') or '-'}  "
                        f"iso={b.get('iso')}  shutter={b.get('shutterspeed')}  "
                        f"wb={b.get('whitebalance') or '-'}  bat={b.get('batterylevel')}  "
                        f"{b.get('port')}"
                    )
                return _json(
                    self, 200,
                    {"cameras": rows, "status": blocks, "pair": dual.load_pair(),
                     "message": "\n".join(lines)},
                )
        except dual.CamError as exc:
            return _json(self, 400, {"error": str(exc)})
        return _json(self, 404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            data = _read_json(self)
            if path == "/api/pair":
                t, r = (data.get("t") or "").strip(), (data.get("r") or "").strip()
                if not t and not r:
                    raise dual.CamError("need a T or R serial")
                data = dual.save_pair(t, r, replace=True)
                bits = "  ".join(f"{k}={v}" for k, v in data.items())
                return _json(self, 200, {"message": f"paired {bits}", "pair": data})
            if path == "/api/live/start":
                have = LIVE.start_from_usb()
                roles = " ".join(sorted(have))
                return _json(self, 200, {"message": f"live view {roles}  (low-res PTP preview)"})
            if path == "/api/live/stop":
                _stop_live()
                return _json(self, 200, {"message": "live view stopped"})
            if path == "/api/set":
                _stop_live()
                assignments = _assignments(data)
                if not assignments:
                    raise dual.CamError("nothing to set")
                have = dual.require_online(dual.detect_bodies())
                from concurrent.futures import ThreadPoolExecutor

                notes = []
                with ThreadPoolExecutor(max_workers=len(have)) as pool:
                    futs = [
                        pool.submit(dual._set_one, row["port"], assignments)
                        for row in have.values()
                    ]
                    for fut in futs:
                        notes.extend(fut.result() or [])
                roles = " and ".join(sorted(have))
                msg = "set " + " ".join(f"{k}={v}" for k, v in assignments) + f" on {roles}"
                if notes:
                    msg += "  (" + "; ".join(notes)
                    if any(n.startswith("expprogram=") for n in notes):
                        msg += " — turn the mode dial to M"
                    msg += ")"
                return _json(self, 200, {"message": msg})
            if path == "/api/shoot":
                from concurrent.futures import ThreadPoolExecutor
                from datetime import datetime

                _stop_live()
                have = dual.require_online(dual.detect_bodies())
                target = (data.get("target") or "card").strip()
                stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                dest = pano.CAPTURES
                with ThreadPoolExecutor(max_workers=len(have)) as pool:
                    if target == "card":
                        futs = [
                            pool.submit(dual._shoot_card, role, have[role]["port"])
                            for role in have
                        ]
                    else:
                        futs = [
                            pool.submit(dual._shoot_one, role, have[role]["port"], dest, stamp)
                            for role in have
                        ]
                    times = [fut.result() for fut in futs]
                msg = "  ".join(f"{role} {dt:.2f}s" for role, dt in times)
                where = "cards" if target == "card" else "captures/"
                return _json(self, 200, {"message": f"shot {stamp}  {msg}  → {where}"})
            if path == "/api/captures/delete":
                stamp = (data.get("stamp") or "").strip()
                side = (data.get("side") or "").strip().upper()
                info = pano.delete_stamp(stamp, sides=[side] if side else None)
                return _json(
                    self, 200,
                    {
                        **info,
                        "pairs": pano.list_pairs(),
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
                        "message": f"kept {len(info['kept'])}, removed {info['count']}",
                    },
                )
            if path == "/api/pano":
                stamp = (data.get("stamp") or "").strip()
                if not stamp:
                    raise dual.CamError("select a T/R pair")
                try:
                    overlap = data.get("overlap")
                    overlap = float(overlap) if overlap is not None else pano.OVERLAP
                except (TypeError, ValueError):
                    raise dual.CamError("bad overlap")
                flip_r = data.get("flip_r", True)
                if isinstance(flip_r, str):
                    flip_r = flip_r.lower() not in ("0", "false", "no")
                info = pano.stitch_stamp(stamp, overlap=overlap, flip_r=bool(flip_r))
                return _json(
                    self, 200,
                    {
                        **info,
                        "url": "/api/file/" + info["file"],
                        "message": f"pano {info['file']}  {info['width']}×{info['height']}",
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
    print("ptpcamerad held down (python3 cam/dual.py ptp-on to restore Photos)")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
