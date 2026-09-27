#!/usr/bin/env python3
"""FXPAN OS — the next field UI, served beside the current kiosk.

  python3 cam/fxos/serve.py                          two simulated D800s
  python3 cam/fxos/serve.py --proxy http://PI:8787    the real rig through web.py
  open http://127.0.0.1:8790/                          (?kiosk=1 hides the cursor)

cam/field.html and web.py are not touched. Modes, custom looks and per-shot
notes persist in cam/fxos/state.json. The simulator keeps its captures and
settings in cam/fxos/.sim/ and never writes to captures/.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import secrets
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
LOGO = HERE.parent.parent / "logos" / "fxpan.svg"
STATE_PATH = HERE / "state.json"
PORT = 8790
TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml; charset=utf-8",
    ".ttf": "font/ttf",
    ".woff2": "font/woff2",
    ".txt": "text/plain; charset=utf-8",
}
STATIC = re.compile(r"^/((?:js|fonts)/)?[\w.-]+$")
SECTIONS = ("frame", "light", "focus", "look", "drive", "wb")

LOOK_KEYS = ("id", "base", "name", "color", "highlight", "shadow", "grain", "filter")
DEFAULT_CURRENT = {
    "frame": {"guide": "none"},
    "focus": {"aid": "peaking", "color": "red", "level": "std"},
    "look": {"id": "standard", "base": "standard", "color": 0, "highlight": 0,
             "shadow": 0, "grain": "off", "filter": "none"},
    "drive": {"timer": 0, "auto_stitch": True},
}


def _look(base, color=0, highlight=0, shadow=0, grain="off", filt="none"):
    return {"id": base, "base": base, "color": color, "highlight": highlight,
            "shadow": shadow, "grain": grain, "filter": filt}


def _light(iso, shutter, fstop, program="M"):
    return {"program": program, "iso": iso, "shutter": shutter, "fstop": fstop,
            "master": "T", "lock_t": True, "sync": True, "follow_cam": False}


def _drive(release="sync", quality="NEF+Fine", timer=0, review=10, engine="hugin"):
    return {"release": release, "save": "pi", "quality": quality, "timer": timer,
            "review": review, "auto_stitch": True, "engine": engine}


FOCUS_PEAK = {"aid": "peaking", "color": "red", "level": "std"}
DEFAULT_MODES = [
    {"id": "landscape", "name": "Landscape Pano", "note": "Tripod, deep focus, 2 s timer",
     "frame": {"squeeze": 1.0, "guide": "none", "clip": True},
     "light": _light("100", "1/60", "11"), "focus": dict(FOCUS_PEAK),
     "look": _look("landscape", color=1, shadow=1),
     "drive": _drive(timer=2), "wb": "Sunny"},
    {"id": "street", "name": "XPan Street", "note": "Handheld 65:24, fast shutter",
     "frame": {"squeeze": 1.0, "guide": "none", "clip": True},
     "light": _light("800", "1/500", "8"), "focus": {**FOCUS_PEAK, "aid": "off"},
     "look": _look("chrome", highlight=1, shadow=1, grain="weak"),
     "drive": _drive(quality="JPEG Fine", review=3), "wb": "Auto"},
    {"id": "ana2", "name": "Anamorphic 2×", "note": "5.42:1 through the 2× adapter",
     "frame": {"squeeze": 2.0, "guide": "none", "clip": True},
     "light": _light("400", "1/125", "5.6"), "focus": dict(FOCUS_PEAK),
     "look": _look("standard"), "drive": _drive(), "wb": "Auto"},
    {"id": "mono", "name": "Black & White", "note": "Red filter for sky",
     "frame": {"squeeze": 1.0, "guide": "none", "clip": True},
     "light": _light("400", "1/250", "8"), "focus": dict(FOCUS_PEAK),
     "look": _look("mono", highlight=1, shadow=2, grain="weak", filt="red"),
     "drive": _drive(), "wb": "Auto"},
    {"id": "bench", "name": "Bench Calibration", "note": "Checker pairs over USB for overlap",
     "frame": {"squeeze": 1.0, "guide": "none", "clip": False},
     "light": _light("100", "1/15", "8"),
     "focus": {"aid": "peaking", "color": "yellow", "level": "high"},
     "look": _look("neutral"),
     "drive": _drive(release="usb", quality="JPEG Fine", timer=2, review=15, engine="match"),
     "wb": "Auto"},
]


def _default_state():
    return {
        "version": 1,
        "current": copy.deepcopy(DEFAULT_CURRENT),
        "active": "",
        "modes": copy.deepcopy(DEFAULT_MODES),
        "looks": [],
        "shots": {},
    }


def _text(val, limit):
    return str(val or "").strip()[:limit]


def _clean_look(val):
    val = val if isinstance(val, dict) else {}
    out = {k: val[k] for k in LOOK_KEYS if k in val}
    for key in ("color", "highlight", "shadow"):
        try:
            out[key] = max(-4, min(4, int(out.get(key) or 0)))
        except (TypeError, ValueError):
            out[key] = 0
    for key in ("id", "base", "name", "grain", "filter"):
        if key in out:
            out[key] = _text(out[key], 40)
    return out


def _clean_mode(val):
    val = val if isinstance(val, dict) else {}
    out = {}
    for sec in SECTIONS:
        if sec == "wb":
            if "wb" in val:
                out["wb"] = _text(val["wb"], 24)
            continue
        part = val.get(sec)
        if isinstance(part, dict):
            out[sec] = _clean_look(part) if sec == "look" else {
                str(k)[:24]: v for k, v in part.items()
                if isinstance(v, (str, int, float, bool)) and len(str(v)) <= 40
            }
    return out


class Store:
    """Modes, the fxos-only part of the current state, custom looks, shot notes."""

    def __init__(self, path):
        self.path = Path(path)
        self._lock = threading.Lock()
        self.data = _default_state()
        try:
            got = json.loads(self.path.read_text())
        except (OSError, json.JSONDecodeError):
            got = None
        if isinstance(got, dict) and got.get("version") == 1:
            self.data.update({k: got[k] for k in self.data if k in got})
            for sec, val in DEFAULT_CURRENT.items():
                self.data["current"].setdefault(sec, copy.deepcopy(val))

    def _save(self):
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=2) + "\n")
        tmp.replace(self.path)

    def snapshot(self):
        with self._lock:
            return copy.deepcopy(self.data)

    def _find(self, mode_id):
        for i, mode in enumerate(self.data["modes"]):
            if mode.get("id") == mode_id:
                return i, mode
        raise ValueError("no such mode")

    def post_state(self, body):
        with self._lock:
            cur = self.data["current"]
            for sec, val in (body.get("current") or {}).items():
                if sec not in DEFAULT_CURRENT or not isinstance(val, dict):
                    continue
                part = _clean_look(val) if sec == "look" else _clean_mode({sec: val}).get(sec, {})
                if sec == "look":
                    cur[sec] = {**DEFAULT_CURRENT["look"], **part}
                else:
                    cur[sec].update(part)
            if "active" in body:
                want = _text(body.get("active"), 40)
                if want and not any(m["id"] == want for m in self.data["modes"]):
                    raise ValueError("no such mode")
                self.data["active"] = want
            if "looks" in body and isinstance(body["looks"], list):
                looks = []
                for row in body["looks"][:24]:
                    look = _clean_look(row)
                    if look.get("id") and look.get("name"):
                        looks.append(look)
                self.data["looks"] = looks
            self._save()
        return self.snapshot()

    def post_mode(self, body):
        act = body.get("action")
        with self._lock:
            modes = self.data["modes"]
            if act == "create":
                if len(modes) >= 24:
                    raise ValueError("24 modes is the limit")
                name = _text(body.get("name"), 40) or "New mode"
                mode = {"id": "m_" + secrets.token_hex(3), "name": name,
                        "note": _text(body.get("note"), 80), **_clean_mode(body.get("mode"))}
                modes.append(mode)
                if body.get("activate", True):
                    self.data["active"] = mode["id"]
            elif act == "update":
                i, mode = self._find(body.get("id"))
                modes[i] = {"id": mode["id"], "name": mode["name"], "note": mode.get("note", ""),
                            **_clean_mode(body.get("mode"))}
            elif act == "rename":
                _i, mode = self._find(body.get("id"))
                mode["name"] = _text(body.get("name"), 40) or mode["name"]
                if "note" in body:
                    mode["note"] = _text(body.get("note"), 80)
            elif act == "duplicate":
                i, mode = self._find(body.get("id"))
                if len(modes) >= 24:
                    raise ValueError("24 modes is the limit")
                twin = copy.deepcopy(mode)
                twin["id"] = "m_" + secrets.token_hex(3)
                twin["name"] = (mode["name"][:35] + " copy")
                modes.insert(i + 1, twin)
            elif act == "delete":
                i, mode = self._find(body.get("id"))
                modes.pop(i)
                if self.data["active"] == mode["id"]:
                    self.data["active"] = ""
            elif act == "activate":
                self._find(body.get("id"))
                self.data["active"] = body.get("id")
            else:
                raise ValueError("action is create, update, rename, duplicate, delete or activate")
            self._save()
        return self.snapshot()

    def post_shot(self, body):
        stamp = _text(body.get("stamp"), 40)
        if not re.fullmatch(r"[\w.-]+", stamp or ""):
            raise ValueError("bad stamp")
        with self._lock:
            shots = self.data["shots"]
            shots[stamp] = {
                "mode": _text(body.get("mode"), 40),
                "mode_name": _text(body.get("mode_name"), 40),
                "look": _clean_look(body.get("look")),
                "squeeze": body.get("squeeze") if isinstance(body.get("squeeze"), (int, float)) else 1,
                "guide": _text(body.get("guide"), 12),
            }
            for old in sorted(shots)[:-400]:
                shots.pop(old, None)
            self._save()
            return dict(shots[stamp])

    def look_for(self, stamp):
        with self._lock:
            return copy.deepcopy((self.data["shots"].get(stamp) or {}).get("look") or {})


def _git_version():
    try:
        out = subprocess.run(["git", "-C", str(HERE), "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=3)
        return out.stdout.strip() or "dev"
    except (OSError, subprocess.TimeoutExpired):
        return "dev"


class Handler(BaseHTTPRequestHandler):
    server_version = "fxos/1"

    def log_message(self, fmt, *args):
        if not self.path.startswith(("/api/live/", "/api/link")):
            sys.stderr.write("%s\n" % (fmt % args))

    def _send(self, code, body, ctype, download=""):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store, must-revalidate")
        if download:
            self.send_header("Content-Disposition", f'attachment; filename="{download}"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, code, payload):
        self._send(code, json.dumps(payload).encode(), "application/json")

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")

    def _route(self, method):
        app = self.server.app
        url = urlparse(self.path)
        path = url.path
        raw = self._body() if method == "POST" else b""
        try:
            data = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return self._json(400, {"error": "bad json"})
        try:
            if path.startswith("/api/"):
                if app.proxy:
                    return self._proxy(method, raw)
                return self._sim(method, path, parse_qs(url.query), data)
            if path.startswith("/fxos/api/"):
                return self._fxos(method, path, data)
            if path.startswith("/sim/api/"):
                if not app.rig:
                    return self._json(404, {"error": "not in sim mode"})
                if method == "POST":
                    return self._json(200, app.rig.sim_control(data))
                return self._json(200, app.rig.sim_state())
            if method == "GET":
                return self._static(path)
        except ValueError as exc:
            return self._json(400, {"error": str(exc)})
        return self._json(404, {"error": "not found"})

    def _index(self):
        # Versioned asset URLs, modules included via an import map, so a
        # kiosk Chromium never runs yesterday's files after an update.
        files = [HERE / "index.html", HERE / "app.css", *sorted((HERE / "js").glob("*.js"))]
        v = max(int(p.stat().st_mtime) for p in files if p.is_file())
        imap = {"imports": {f"/js/{p.name}": f"/js/{p.name}?v={v}" for p in files if p.suffix == ".js"}}
        html = (HERE / "index.html").read_text()
        html = html.replace('href="/app.css"', f'href="/app.css?v={v}"')
        html = html.replace('src="/js/app.js"', f'src="/js/app.js?v={v}"')
        html = html.replace("<!--importmap-->", f'<script type="importmap">{json.dumps(imap)}</script>')
        return self._send(200, html.encode(), TYPES[".html"])

    def _static(self, path):
        if path in ("/", "/index.html"):
            return self._index()
        if path == "/fxpan.svg":
            return self._send(200, LOGO.read_bytes(), TYPES[".svg"])
        if not STATIC.match(path) or ".." in path:
            return self._json(404, {"error": "not found"})
        file = HERE / path.lstrip("/")
        ctype = TYPES.get(file.suffix.lower())
        if not ctype or not file.is_file():
            return self._json(404, {"error": "not found"})
        return self._send(200, file.read_bytes(), ctype)

    def _fxos(self, method, path, data):
        app = self.server.app
        if path == "/fxos/api/state":
            snap = app.store.post_state(data) if method == "POST" else app.store.snapshot()
            return self._json(200, {**snap, **app.info()})
        if method != "POST":
            return self._json(404, {"error": "not found"})
        if path == "/fxos/api/modes":
            return self._json(200, {**app.store.post_mode(data), **app.info()})
        if path == "/fxos/api/shot":
            return self._json(200, {"shot": app.store.post_shot(data)})
        return self._json(404, {"error": "not found"})

    def _sim(self, method, path, query, data):
        app = self.server.app
        if path == "/api/pano" and method == "POST" and not data.get("look"):
            data["look"] = app.store.look_for(str(data.get("stamp") or ""))
        try:
            rep = app.rig.api(method, path, query, data, self.server.server_address[1])
        except app.rig_errors as exc:
            return self._json(400, {"error": str(exc)})
        if rep.json is not None:
            return self._json(rep.code, rep.json)
        return self._send(rep.code, rep.body or b"", rep.ctype, rep.download)

    def _proxy(self, method, raw):
        target = self.server.app.proxy + self.path
        req = urllib.request.Request(
            target, data=raw if method == "POST" else None, method=method,
            headers={"Content-Type": self.headers.get("Content-Type") or "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=240) as resp:
                body, code = resp.read(), resp.status
                ctype = resp.headers.get("Content-Type") or "application/octet-stream"
                disp = resp.headers.get("Content-Disposition") or ""
        except urllib.error.HTTPError as exc:
            body, code = exc.read(), exc.code
            ctype = exc.headers.get("Content-Type") or "application/json"
            disp = ""
        except (urllib.error.URLError, OSError) as exc:
            return self._json(502, {"error": f"rig unreachable: {exc}"})
        m = re.search(r'filename="([^"]+)"', disp)
        return self._send(code, body, ctype, m.group(1) if m else "")


class App:
    def __init__(self, proxy="", real_stitch=False):
        self.proxy = proxy.rstrip("/")
        self.store = Store(STATE_PATH)
        self.version = _git_version()
        self.rig = None
        self.rig_errors = ()
        if not self.proxy:
            sys.path.insert(0, str(HERE))
            import sim

            self.rig = sim.Rig(real_stitch=real_stitch)
            self.rig_errors = (sim.SimError, sim.dual.CamError)

    def info(self):
        return {
            "server": {
                "mode": "proxy" if self.proxy else "sim",
                "proxy": self.proxy,
                "version": self.version,
                "classic": (self.proxy + "/") if self.proxy else "http://127.0.0.1:8787/",
            }
        }


class Server(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--proxy", default="", help="forward /api/* to a running web.py, e.g. http://192.0.2.10:8787")
    ap.add_argument("--real-stitch", action="store_true",
                    help="sim: run pano.py's stitcher on the sim captures instead of the quick fake")
    args = ap.parse_args(argv)
    app = App(proxy=args.proxy, real_stitch=args.real_stitch)
    httpd = Server((args.host, args.port), Handler)
    httpd.app = app
    mode = f"proxy → {app.proxy}" if app.proxy else "simulated T/R D800s"
    print(f"FXPAN OS  {mode}")
    print(f"open      http://{args.host}:{args.port}/")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
