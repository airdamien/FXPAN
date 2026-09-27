"""Two simulated D800s behind the /api/* contract of cam/web.py.

No USB, no gphoto2. Live view and captures are cut from real panoramas in
captures/: R is the left body (mirrored, like the reflected leg), T the
right, 20% overlap. Listing, thumbnails, locks and deletes go through
pano.py against .sim/captures, and settings through settings.py against
.sim/settings.json, so both behave exactly as they do on the Pi. Nothing
here writes to captures/ or cam/settings.json.
"""

from __future__ import annotations

import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
CAM = HERE.parent
if str(CAM) not in sys.path:
    sys.path.insert(0, str(CAM))

import dual  # noqa: E402
import pano  # noqa: E402
import settings  # noqa: E402

SIM = HERE / ".sim"
CAPTURES = SIM / "captures"
FRAMES = SIM / "frames"
SEED = CAM.parent / "captures"
PAIR_PATH = SIM / "cameras.json"
settings.PATH = SIM / "settings.json"

MAGICK = shutil.which("magick")
LV_W, LV_H = 640, 427   # D800 live view is 640 × 424
LV_FPS = 8
N_FRAMES = 24
CROP = 0.96             # live window inside the body frame; the rest is drift room
OVERLAP = 0.20
SEED_NAME = re.compile(r"^[TRPX]_\w+\.(jpe?g|nef|json)$", re.I)
EXPOSURE_KEYS = ("iso", "shutter", "fstop", "wb", "quality", "program")

# The same look model as js/look.js. Looks are rendered after the stitch,
# so both halves of a panorama always get the identical grade.
LOOK_BASE = {
    "standard": {"sat": 1.00, "curve": 0.0},
    "neutral": {"sat": 0.86, "curve": -1.5},
    "vivid": {"sat": 1.35, "curve": 1.5},
    "landscape": {"sat": 1.18, "curve": 1.0, "gain": (1.0, 1.05, 1.06)},
    "chrome": {"sat": 0.78, "curve": 2.2},
    "mono": {"sat": 0.0, "curve": 1.2, "mono": True},
}
MONO_MIX = {
    "none": (0.30, 0.59, 0.11),
    "yellow": (0.40, 0.50, 0.10),
    "orange": (0.50, 0.40, 0.10),
    "red": (0.66, 0.30, 0.04),
    "green": (0.22, 0.66, 0.12),
}
GRAIN = {"off": 0.0, "weak": 0.18, "strong": 0.34}


class SimError(Exception):
    pass


@dataclass
class Reply:
    code: int = 200
    json: dict | None = None
    body: bytes | None = None
    ctype: str = "application/json"
    download: str = ""


def look_amounts(look):
    base = LOOK_BASE.get((look or {}).get("base"), LOOK_BASE["standard"])
    c = base["curve"]
    clamp = lambda v: max(-5.0, min(5.0, v))  # noqa: E731
    shadow = clamp(c + _int(look, "shadow"))
    high = clamp(c + _int(look, "highlight"))
    return shadow, high


def look_curve(x, shadow, high):
    """Tone curve shared with js/look.js: + pushes shadows down, highlights up."""
    if x < 0.5:
        y = x - shadow * 0.03 * math.sin(2 * math.pi * x)
    else:
        y = x - high * 0.03 * math.sin(2 * math.pi * x)
    return min(1.0, max(0.0, y))


def _int(obj, key):
    try:
        return int((obj or {}).get(key) or 0)
    except (TypeError, ValueError):
        return 0


def look_args(look, tmpdir):
    """ImageMagick operators for a look, applied to the stitched P_."""
    look = look or {}
    base = LOOK_BASE.get(look.get("base"), LOOK_BASE["standard"])
    args = []
    if base.get("mono"):
        r, g, b = MONO_MIX.get(look.get("filter") or "none", MONO_MIX["none"])
        args += ["-color-matrix", f"{r} {g} {b} {r} {g} {b} {r} {g} {b}"]
    else:
        sat = max(0.0, base["sat"] * (1 + 0.12 * _int(look, "color")))
        if abs(sat - 1) > 0.01:
            args += ["-modulate", f"100,{sat * 100:.0f},100"]
        gain = base.get("gain")
        if gain:
            args += ["-color-matrix", f"{gain[0]} 0 0 0 {gain[1]} 0 0 0 {gain[2]}"]
    shadow, high = look_amounts(look)
    if shadow or high:
        lut = Path(tmpdir) / "look.pgm"
        vals = bytes(round(255 * look_curve(i / 255, shadow, high)) for i in range(256))
        lut.write_bytes(b"P5\n1 256\n255\n" + vals)
        args += [str(lut), "-clut"]
    grain = GRAIN.get(look.get("grain") or "off", 0.0)
    if grain:
        args += ["-attenuate", f"{grain}", "+noise", "Gaussian"]
    return args


def _magick(args, timeout=180):
    if not MAGICK:
        raise SimError("ImageMagick `magick` not found")
    proc = subprocess.run([MAGICK, *args], capture_output=True, text=True, timeout=timeout)
    if proc.returncode:
        err = (proc.stderr or proc.stdout or "magick failed").strip().splitlines()
        raise SimError(err[-1] if err else "magick failed")
    return proc.stdout


def _size(path):
    w, h = _magick(["identify", "-format", "%w %h", str(path)]).split()
    return int(w), int(h)


def geometry(w, h):
    """Body frames inside a w × h pano: frame w, frame h, pano left, top.

    Two 3:2 frames with OVERLAP make a 2.7:1 strip.
    """
    fh = min(float(h), w / (1.5 * (2 - OVERLAP)))
    fw = fh * 1.5
    pw = fw * (2 - OVERLAP)
    return fw, fh, (w - pw) / 2, (h - fh) / 2


def _seed():
    CAPTURES.mkdir(parents=True, exist_ok=True)
    if any(pano.PAIR_RE.match(p.name) for p in CAPTURES.iterdir()):
        return
    if not SEED.is_dir():
        return
    for path in sorted(SEED.iterdir()):
        if path.is_file() and SEED_NAME.match(path.name):
            shutil.copy2(path, CAPTURES / path.name)


def _scene_sources():
    out = []
    if SEED.is_dir():
        for path in sorted(SEED.glob("P_*.jpg")):
            if not pano.PANO_ANA_RE.match(path.name):
                out.append(path)
    if out or not MAGICK:
        return out
    synthetic = SIM / "scene_synthetic.jpg"
    if not synthetic.is_file():
        SIM.mkdir(parents=True, exist_ok=True)
        _magick(["-size", "2700x1000", "-seed", "7", "plasma:steelblue-khaki",
                 "-blur", "0x3", str(synthetic)])
    return [synthetic]


class Scene:
    """One source pano, cut into looping T/R live frames."""

    def __init__(self, src, idx):
        self.src = Path(src)
        self.idx = idx
        self.size = (0, 0)
        self.frames = {}
        self.error = ""
        self._lock = threading.Lock()

    @property
    def ready(self):
        return bool(self.frames)

    @property
    def name(self):
        return self.src.stem

    def prepare(self):
        with self._lock:
            if self.frames:
                return
            try:
                self._prepare()
            except (SimError, OSError, subprocess.TimeoutExpired) as exc:
                self.error = str(exc)

    def _prepare(self):
        out = FRAMES / f"{self.idx:02d}"
        key = {"src": str(self.src), "mtime": self.src.stat().st_mtime, "v": 4}
        marker = out / "src.json"
        self.size = _size(self.src)
        names = {role: [out / f"{role}_{k:02d}.jpg" for k in range(N_FRAMES)] for role in ("T", "R")}
        fresh = marker.is_file() and json.loads(marker.read_text()) == key
        if not fresh or not all(p.is_file() for files in names.values() for p in files):
            out.mkdir(parents=True, exist_ok=True)
            self._render(out)
            marker.write_text(json.dumps(key))
        self.frames = {role: [p.read_bytes() for p in files] for role, files in names.items()}

    def _render(self, out):
        w, h = self.size
        _fw, fh, _x0, _y0 = geometry(w, h)
        s = (LV_H / CROP) / fh
        ww, wh = max(LV_W + 2, round(w * s)), max(LV_H + 2, round(h * s))
        work = out / "work.jpg"
        _magick([str(self.src), "-resize", f"{ww}x{wh}!", "-quality", "90", str(work)])
        fw, fh, x0, y0 = geometry(ww, wh)
        # The windows, not the frames, must overlap by OVERLAP: that is
        # the strip the preview blends and the balance meter compares.
        centers = {"R": x0 + fw / 2, "T": x0 + fw / 2 + LV_W * (1 - OVERLAP)}
        cy = y0 + fh / 2
        ax = fw * (1 - CROP) / 2 * 0.85
        ay = fh * (1 - CROP) / 2 * 0.85
        for role, cx in centers.items():
            args = [str(work), "-quality", "80"]
            for k in range(N_FRAMES):
                a = 2 * math.pi * k / N_FRAMES
                left = min(ww - LV_W, max(0, round(cx + ax * math.sin(a) - LV_W / 2)))
                top = min(wh - LV_H, max(0, round(cy + ay * math.sin(a + 1.3) - LV_H / 2)))
                args += ["(", "-clone", "0", "-crop", f"{LV_W}x{LV_H}+{left}+{top}", "+repage"]
                if role == "R":
                    args.append("-flop")
                args += ["-write", str(out / f"{role}_{k:02d}.jpg"), "+delete", ")"]
            _magick(args + ["null:"])

    def shot_boxes(self):
        w, h = self.size
        fw, fh, x0, y0 = geometry(w, h)
        pw = fw * (2 - OVERLAP)
        return {
            "R": (round(fw), round(fh), round(x0), round(y0)),
            "T": (round(fw), round(fh), round(x0 + pw - fw), round(y0)),
            "P": (round(pw), round(fh), round(x0), round(y0)),
        }


@dataclass
class Body:
    serial: str
    port: str
    battery: float
    shots: int
    online: bool = True
    model: str = "Nikon DSC D800"


@dataclass
class Rig:
    real_stitch: bool = False
    bodies: dict = field(default_factory=dict)

    def __post_init__(self):
        SIM.mkdir(parents=True, exist_ok=True)
        _seed()
        self._lock = threading.RLock()
        pair = self._load_pair()
        self.pair = {"T": pair.get("T") or "3003207", "R": pair.get("R") or "3300047"}
        self.bodies = {
            self.pair["T"]: Body(self.pair["T"], "usb:020,004", 87.0, 1412),
            self.pair["R"]: Body(self.pair["R"], "usb:020,005", 91.0, 1398),
        }
        self.want_live = False
        self.idle = False
        self.desync = False
        self.gpio_sim = True
        self.bright = 70
        self.wifi_mode = "station"
        self.wifi_ssid = "studio"
        self._live_t0 = 0.0
        self._busy_until = 0.0
        self._drain_at = time.time()
        self._shot_scene = {}
        self._stitch_q = []
        self._stitching = False
        self.scenes = [Scene(p, i) for i, p in enumerate(_scene_sources())]
        self.scene = 0
        if not settings.PATH.is_file():
            settings.save({"flip_r": True, "overlap": OVERLAP, "stitch_mode": "hugin",
                           "program": "M", "iso": "400", "shutter": "1/250", "fstop": "8",
                           "wb": "Auto", "quality": "NEF+Fine"}, pi=True)
        if self.scenes:
            threading.Thread(target=self.scenes[0].prepare, name="sim-scene", daemon=True).start()

    # --- state ---------------------------------------------------------------
    def _load_pair(self):
        for path in (PAIR_PATH, CAM / "cameras.json"):
            try:
                data = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(data, dict):
                return {k: str(v) for k, v in data.items() if k in ("T", "R") and v}
        return {}

    def _save_pair(self):
        PAIR_PATH.write_text(json.dumps(self.pair, indent=2) + "\n")

    def prefs(self):
        return settings.load(pi=True)

    def save_prefs(self, data):
        return settings.save(data, pi=True)

    def role_of(self, serial):
        for role, sn in self.pair.items():
            if sn and sn == serial:
                return role
        return ""

    def online(self):
        """role → Body for paired bodies on USB."""
        out = {}
        for role in ("T", "R"):
            body = self.bodies.get(self.pair.get(role) or "")
            if body and body.online:
                out[role] = body
        return out

    def _drain(self):
        now = time.time()
        dt = now - self._drain_at
        self._drain_at = now
        if self._live_running():
            for body in self.online().values():
                body.battery = max(1.0, body.battery - dt * 0.5 / 60)

    def _scene(self):
        if not self.scenes:
            return None
        return self.scenes[self.scene % len(self.scenes)]

    def _live_running(self):
        scene = self._scene()
        return bool(
            self.want_live and not self.idle and scene and scene.ready
            and self.online() and time.time() >= self._busy_until
        )

    # --- camera status ---------------------------------------------------------
    def _block(self, role, body):
        p = self.prefs()
        prog = p.get("program") or "M"
        iso = str(p.get("iso") or "400")
        shut = str(p.get("shutter") or "1/250")
        fnum = str(p.get("fstop") or "8")
        if prog not in ("M", "S") or shut.lower() == "auto":
            shut = "1/320"
        if prog not in ("M", "A") or fnum.lower() == "auto":
            fnum = "5.6"
        if self.desync and role == "R":
            iso = "800" if iso != "800" else "1600"
        auto = iso.lower() == "auto"
        return {
            "role": role, "port": body.port, "model": body.model,
            "serial": body.serial, "serialnumber": body.serial,
            "iso": "Auto" if auto else iso, "isoauto": "On" if auto else "Off",
            "autoiso": "On" if auto else "Off",
            "shutterspeed": shut, "f-number": f"f/{fnum}",
            "imagequality": p.get("quality") or "NEF+Fine",
            "whitebalance": p.get("wb") or "Auto",
            "expprogram": prog, "exposurecompensation": "0",
            "capturetarget": "Memory card", "focusmode": "Manual",
            "batterylevel": f"{round(body.battery)}%",
            "availableshots": str(body.shots),
        }

    def _rows(self):
        rows, blocks = [], []
        for role, body in self.online().items():
            block = self._block(role, body)
            blocks.append(block)
            rows.append({**block, "usb_speed": "480M"})
        return rows, blocks

    def link(self):
        with self._lock:
            self._drain()
            running = self._live_running()
            frames = int((time.time() - self._live_t0) * LV_FPS) if running else 0
            roles = {}
            for role in ("T", "R"):
                body = self.bodies.get(self.pair.get(role) or "")
                on = bool(body and body.online)
                roles[role] = {
                    "paired": bool(self.pair.get(role)),
                    "serial": self.pair.get(role) or "",
                    "port": body.port if on else "",
                    "model": body.model if on else "",
                    "usb_speed": "480M" if on else "",
                    "online": on, "live": running and on,
                    "frames": frames if on else 0, "error": "",
                }
            missing = [r for r in ("T", "R") if self.pair.get(r) and not roles[r]["online"]]
            scene = self._scene()
            if running:
                msg = "live " + "  ".join(
                    f"{r} {roles[r]['frames']}f" if roles[r]["online"] else f"{r} out"
                    for r in ("T", "R"))
            elif self.want_live and scene and not scene.ready:
                msg = "live wait"
            else:
                bits = [f"{r} {roles[r]['port']}" if roles[r]["online"] else f"{r} out"
                        for r in ("T", "R") if self.pair.get(r)]
                msg = "  ".join(bits) or "no cameras"
            extras = [
                {"role": "", "serial": b.serial, "port": b.port, "model": b.model,
                 "usb_speed": "480M"}
                for b in self.bodies.values()
                if b.online and not self.role_of(b.serial)
            ]
            return {
                "want_live": self.want_live,
                "busy": time.time() < self._busy_until,
                "running": running, "roles": roles, "extras": extras,
                "missing": missing, "message": msg,
                "status": {role: self._block(role, b) for role, b in self.online().items()},
                "idle": self.idle,
            }

    def live_snapshot(self):
        link = self.link()
        return {
            "running": link["running"],
            "roles": {
                r: {"frames": v["frames"], "error": "", "port": v["port"], "alive": v["live"]}
                for r, v in link["roles"].items() if v["online"] and self.want_live
            },
        }

    def jpeg(self, role):
        with self._lock:
            if not self._live_running() or role not in self.online():
                return None
            scene = self._scene()
            k = int((time.time() - self._live_t0) * LV_FPS) % N_FRAMES
            return scene.frames[role][k]

    # --- actions -----------------------------------------------------------------
    def live_start(self):
        with self._lock:
            if not self.want_live or self.idle:
                self._live_t0 = time.time()
            self.want_live = True
            self.idle = False
            scene = self._scene()
        if scene and not scene.ready:
            threading.Thread(target=scene.prepare, daemon=True).start()
        deadline = time.time() + 8
        while time.time() < deadline and not self._live_running():
            time.sleep(0.15)
        link = self.link()
        ok = link["running"]
        msg = link["message"]
        if scene and scene.error:
            msg = f"live: {scene.error}"
        if link["missing"]:
            msg += "  missing " + " ".join(link["missing"])
        return {**link, "ok": ok, "message": msg, "live": self.live_snapshot()}

    def live_stop(self):
        with self._lock:
            self.want_live = False
        return {"message": "live view stopped", "link": self.link()}

    def set_idle(self, on):
        with self._lock:
            self.idle = bool(on)
            if self.idle:
                self.want_live = False
        return {**self.link(), "idle": self.idle,
                "message": "idle  live off  slow poll" if on else "idle off"}

    def detect(self):
        time.sleep(0.6)
        rows, blocks = self._rows()
        if not rows:
            msg = "no cameras. Setup → USB → MTP/PTP, wake, plug USB."
        else:
            msg = f"{len(rows)} body(ies)"
        return {"cameras": rows, "pair": dict(self.pair), "status": blocks,
                "link": self.link(), "message": msg}

    def status(self):
        rows, blocks = self._rows()
        if not rows:
            raise SimError("no cameras")
        lines = [
            f"{b['role']}  {b['expprogram']}  iso={b['iso']}  shutter={b['shutterspeed']}  "
            f"f={b['f-number']}  wb={b['whitebalance']}  bat={b['batterylevel']}  {b['port']}"
            for b in blocks
        ]
        return {"cameras": rows, "status": blocks, "pair": dict(self.pair),
                "link": self.link(), "message": "\n".join(lines)}

    def set_pair(self, data):
        with self._lock:
            if data.get("swap"):
                self.pair = {"T": self.pair.get("R", ""), "R": self.pair.get("T", "")}
            else:
                for role, key in (("T", "t"), ("R", "r")):
                    if key not in data:
                        continue
                    serial = str(data.get(key) or "").strip()
                    if serial and serial not in self.bodies:
                        raise SimError(f"no body {serial}")
                    other = "R" if role == "T" else "T"
                    if serial and self.pair.get(other) == serial:
                        self.pair[other] = self.pair.get(role, "")
                    self.pair[role] = serial
            self._save_pair()
        rows, blocks = self._rows()
        bits = "  ".join(f"{k}={v}" for k, v in self.pair.items() if v) or "(cleared)"
        return {"message": f"paired {bits}", "pair": dict(self.pair), "cameras": rows,
                "status": blocks, "link": self.link()}

    def settings_post(self, data):
        prefs = self.save_prefs(data)
        return {**prefs, "message": (
            f"settings  download={'on' if prefs['download'] else 'off'}"
            f"  gpio={'on' if prefs['gpio'] else 'off'}"
            f"  flop={'on' if prefs['flip_r'] else 'off'}"
            f"  ol={prefs['overlap']:.0%}  master={prefs.get('master', 'T')}"
        )}

    def _merge_exposure(self, data, prefs):
        out = {}
        for key in EXPOSURE_KEYS:
            val = (data or {}).get(key)
            if val is None or str(val).strip() == "":
                val = prefs.get(key)
            val = str(val).strip() if val is not None else ""
            if val:
                out[key] = val
        return out

    def set_exposure(self, data):
        prefs = self.prefs()
        follow = bool(prefs.get("follow_cam")) and not data.get("force")
        exp = self._merge_exposure(data, prefs)
        if not follow and not exp:
            raise SimError("nothing to set")
        have = self.online()
        if not have:
            raise SimError("no cameras")
        if exp and not follow:
            self.save_prefs(exp)
        time.sleep(0.3)
        rows, blocks = self._rows()
        roles = " and ".join(sorted(have))
        if follow:
            msg = f"live AE  camera decides  {roles}"
        else:
            bits = [f"{k}={v}" for k, v in exp.items() if str(v).lower() != "auto"]
            msg = "set " + " ".join(bits) + f" on {roles}"
            prog = exp.get("program", "M")
            notes = []
            if str(exp.get("shutter", "")).lower() == "auto" and prog == "M":
                notes.append("shutter AUTO needs the mode dial on A or P")
            if str(exp.get("fstop", "")).lower() != "auto" and prog not in ("M", "A"):
                notes.append("f/ needs the mode dial on A or M")
            if notes:
                msg += "  (" + "; ".join(notes) + ")"
        return {"message": msg, "cameras": rows, "status": blocks,
                "pair": dict(self.pair), "link": self.link()}

    def shoot(self, data):
        prefs = self.prefs()
        follow = bool(prefs.get("follow_cam"))
        exp = self._merge_exposure(data, prefs)
        if exp and not follow:
            prefs = self.save_prefs(exp)
        target = (data.get("target") or "").strip() or settings.shoot_target(
            prefs, snap={"available": self.gpio_sim})
        have = self.online()
        if not have:
            raise SimError("no cameras")
        scene = self._scene()
        if target != "card" and (not scene or not scene.size[0]):
            if scene:
                scene.prepare()
            if not scene or not scene.size[0]:
                raise SimError("sim: no scene to shoot")
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        t0 = time.monotonic()
        with self._lock:
            self._busy_until = time.time() + 30
        try:
            for body in have.values():
                body.shots = max(0, body.shots - 1)
                body.battery = max(1.0, body.battery - 0.15)
            if target == "card":
                time.sleep(0.8)
                times = "  ".join(f"{r} {0.38 + 0.04 * i:.2f}s" for i, r in enumerate(sorted(have)))
                return {"message": f"shot {stamp}  {times}  → cards", "files": [], "stamp": stamp,
                        "preview_s": prefs.get("preview_s", settings.PREVIEW_S)}
            boxes = scene.shot_boxes()

            def cut(role):
                w, h, x, y = boxes[role]
                dest = CAPTURES / f"{role}_{stamp}.jpg"
                args = [str(scene.src), "-crop", f"{w}x{h}+{x}+{y}", "+repage"]
                if role == "R":
                    args.append("-flop")
                _magick(args + ["-strip", "-quality", "92", str(dest)])
                return dest.name

            with ThreadPoolExecutor(max_workers=2) as pool:
                names = list(pool.map(cut, sorted(have)))
            self._write_exif(stamp, have, prefs)
            self._shot_scene[stamp] = scene.idx
            floor = 1.6 if target == "gpio" else 2.2
            time.sleep(max(0.0, floor - (time.monotonic() - t0)))
        finally:
            with self._lock:
                self._busy_until = 0.0
        files = sorted(names)
        if target == "gpio":
            bits = "  ".join(f"{n[0]} {n}" for n in files)
            msg = f"gpio 21  300ms  sim  → {bits}"
        else:
            times = "  ".join(f"{r} {1.1 + 0.07 * i:.2f}s" for i, r in enumerate(sorted(have)))
            msg = f"shot {stamp}  {times}  → captures/"
        return {"message": msg, "files": files, "stamp": stamp,
                "preview_s": prefs.get("preview_s", settings.PREVIEW_S)}

    def _write_exif(self, stamp, have, prefs):
        taken = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        out = {}
        for role, body in have.items():
            b = self._block(role, body)
            out[role] = {
                "iso": b["iso"], "shutter": b["shutterspeed"],
                "f": b["f-number"].replace("f/", ""), "program": b["expprogram"],
                "wb": b["whitebalance"], "taken": taken, "model": "D800",
                "make": "NIKON CORPORATION",
            }
        (CAPTURES / f"X_{stamp}.json").write_text(json.dumps(out, indent=2) + "\n")

    # --- stitching -----------------------------------------------------------------
    def queue_status(self):
        stat = pano.queue_status()
        with self._lock:
            waiting = [item["stamp"] for item in self._stitch_q]
        if not waiting:
            return stat
        n = len(waiting)
        if stat.get("running"):
            return {**stat, "queued": n, "message": f"{stat['message']}  ·  {n} queued"}
        return {"running": False, "queued": n, "stamp": waiting[0], "phase": "queued",
                "error": "", "message": f"{n} queued  next {waiting[0]}"}

    def stitch(self, data, look=None):
        stamp = str(data.get("stamp") or "").strip()
        if not stamp or not pano.SAFE.fullmatch(stamp):
            raise SimError("select a T/R pair")
        prefs = self.prefs()
        mode = str(data.get("mode") or prefs.get("stitch_mode") or "open").strip().lower()
        if mode not in pano.MODES:
            raise SimError("mode is match, blend, cut, open, or hugin")

        def pick(key, default):
            val = data.get(key)
            return prefs.get(key, default) if val is None else val

        try:
            overlap = float(pick("overlap", OVERLAP))
            squeeze = float(data.get("squeeze") or prefs.get("ana_squeeze") or 1.0)
        except (TypeError, ValueError) as exc:
            raise SimError("bad overlap or squeeze") from exc
        flip_r = _truthy(pick("flip_r", True))
        crop_inner = _truthy(pick("crop_inner", True))
        if self.real_stitch:
            job = pano.start_stitch(stamp, overlap=overlap, flip_r=flip_r, mode=mode,
                                    root=CAPTURES, crop_inner=crop_inner, squeeze=squeeze,
                                    deghost=_truthy(pick("deghost", False)),
                                    balance=_truthy(pick("balance", True)))
            stat = self.queue_status()
            return {**job, "queue": stat, "message": stat.get("message") or f"queued {mode} {stamp}"}
        item = {"stamp": stamp, "mode": mode, "overlap": overlap, "flip_r": flip_r,
                "crop_inner": crop_inner, "squeeze": squeeze, "look": look or {}}
        with self._lock:
            if pano.job_get(stamp).get("running"):
                raise SimError(f"already stitching {stamp}")
            if self._stitching:
                self._stitch_q.append(item)
                pano.job_put(stamp, running=True, phase="queued", mode=mode, error="",
                             log="queued  next" if len(self._stitch_q) == 1
                             else f"queued  {len(self._stitch_q) - 1} ahead")
            else:
                self._stitching = True
                pano.job_put(stamp, running=True, phase="start", mode=mode, error="",
                             log=f"start {mode}")
                threading.Thread(target=self._stitch_loop, args=(item,), daemon=True).start()
        stat = self.queue_status()
        return {**pano.job_get(stamp), "queue": stat,
                "message": stat.get("message") or f"queued {mode} {stamp}"}

    def _stitch_loop(self, item):
        while item:
            self._run_stitch(item)
            with self._lock:
                item = self._stitch_q.pop(0) if self._stitch_q else None
                self._stitching = bool(item)
                if item:
                    pano.job_put(item["stamp"], running=True, phase="start", mode=item["mode"],
                                 error="", log=f"start {item['mode']}")

    def _run_stitch(self, item):
        stamp, mode = item["stamp"], item["mode"]
        t0 = time.monotonic()
        try:
            pair = next((p for p in pano.list_pairs(CAPTURES) if p["stamp"] == stamp), None)
            if not pair or not pair.get("ready"):
                raise SimError("need T and R")
            steps = [
                (0.5, f"load {pair['t']}  {pair['r']}"),
                (0.4, "flop R" if item["flip_r"] else "R as shot"),
                (0.8, f"overlap {item['overlap']:.0%}  dy +2 px  rmse 0.021"),
                (0.7, "seam blend" if mode != "cut" else "hard seam"),
            ]
            for dt, line in steps:
                time.sleep(dt)
                pano.job_put(stamp, phase="work", log=line)
            dest = CAPTURES / f"P_{stamp}.jpg"
            with tempfile.TemporaryDirectory() as tmp:
                out = Path(tmp) / dest.name
                src_args = self._pano_source(stamp, pair)
                grade = look_args(item["look"], tmp)
                if grade:
                    pano.job_put(stamp, phase="work", log=f"look {item['look'].get('base', 'standard')}")
                _magick(src_args + grade + ["-strip", "-quality", "90", str(out)], timeout=300)
                if dest.is_symlink() or dest.exists():
                    dest.unlink()
                shutil.move(str(out), dest)
            w, h = _size(dest)
            info = {
                "mode": mode, "overlap": item["overlap"], "overlap_frac": item["overlap"],
                "dy": 2, "flip_r": item["flip_r"], "width": w, "height": h,
                "file": dest.name, "engine": "sim", "phase": "done", "error": "",
                "message": f"{mode}  sim  {w}×{h}",
            }
            sq = item["squeeze"]
            ana = CAPTURES / f"P_{stamp}_ana.jpg"
            if sq >= 1.05:
                pano.job_put(stamp, phase="work", log=f"desqueeze {sq:g}×")
                _magick([str(dest), "-resize", f"{sq * 100:.1f}%x100%", "-quality", "90", str(ana)])
                aw, ah = _size(ana)
                info.update({"squeeze": sq, "pano_ana": ana.name, "ana_width": aw, "ana_height": ah})
                info["message"] += f"  ana {sq:g}× {aw}×{ah}"
            elif ana.exists():
                ana.unlink()
            pano._with_sec(info, t0)
            pano._write_sidecar(CAPTURES, stamp, info)
            pano.job_put(stamp, running=False, log=info["message"],
                         **{k: v for k, v in info.items() if k != "message"})
        except (SimError, dual.CamError, OSError, subprocess.TimeoutExpired) as exc:
            err = str(exc)
            pano.job_put(stamp, running=False, phase="error", error=err, log=err)
            pano._write_sidecar(CAPTURES, stamp, {"mode": mode, "phase": "error",
                                                  "error": err, "message": err})

    def _pano_source(self, stamp, pair):
        """magick input args that produce the untoned stitch for a stamp."""
        idx = self._shot_scene.get(stamp)
        if idx is not None and idx < len(self.scenes):
            scene = self.scenes[idx]
            w, h, x, y = scene.shot_boxes()["P"]
            return [str(scene.src), "-crop", f"{w}x{h}+{x}+{y}", "+repage"]
        existing = CAPTURES / f"P_{stamp}.jpg"
        if existing.is_file():
            keep = CAPTURES / ".sim_src"
            keep.mkdir(exist_ok=True)
            base = keep / existing.name
            if not base.exists():
                shutil.copy2(existing, base)
            return [str(base)]
        t, r = CAPTURES / pair["t"], CAPTURES / pair["r"]
        return ["(", str(r), "-flop", ")", str(t), "+append"]

    # --- sim-only controls ---------------------------------------------------------
    def sim_state(self):
        with self._lock:
            return {
                "scenes": [s.name for s in self.scenes],
                "scene": self.scene,
                "ready": [s.ready for s in self.scenes],
                "online": {r: bool(self.bodies.get(self.pair.get(r) or "") and
                                   self.bodies[self.pair[r]].online) for r in ("T", "R")},
                "battery": {r: round(self.bodies[self.pair[r]].battery)
                            for r in ("T", "R") if self.pair.get(r) in self.bodies},
                "desync": self.desync,
                "real_stitch": self.real_stitch,
            }

    def sim_control(self, data):
        with self._lock:
            if "scene" in data and self.scenes:
                self.scene = int(data["scene"]) % len(self.scenes)
                scene = self.scenes[self.scene]
                if not scene.ready:
                    threading.Thread(target=scene.prepare, daemon=True).start()
                self._live_t0 = time.time()
            for role, on in (data.get("online") or {}).items():
                body = self.bodies.get(self.pair.get(role) or "")
                if body:
                    body.online = bool(on)
            for role, pct in (data.get("battery") or {}).items():
                body = self.bodies.get(self.pair.get(role) or "")
                if body:
                    body.battery = max(1.0, min(100.0, float(pct)))
            if "desync" in data:
                self.desync = bool(data["desync"])
        return self.sim_state()

    # --- /api/* dispatch -----------------------------------------------------------
    def meta(self, port):
        url = f"http://192.0.2.10:{port}/"
        return {
            "lab": f"http://127.0.0.1:{port}/lab", "phone": url, "urls": [url],
            "pair": dict(self.pair), "live": self.live_snapshot(),
            "gpio": self.gpio(), "settings": self.prefs(),
            "brightness": self.brightness(), "kiosk": False,
            "wifi": self.wifi(), "link": self.link(),
        }

    def gpio(self):
        return {"available": self.gpio_sim, "sim": self.gpio_sim, "pi": False,
                "pin": 21, "pulse_ms": 300}

    def brightness(self):
        return {"available": True, "value": self.bright, "max": 100, "bus": 1}

    def wifi(self, networks=None):
        url = "http://192.0.2.10:8790/"
        nets = networks if networks is not None else []
        if self.wifi_mode == "ap":
            return {"available": True, "mode": "ap", "ssid": "", "ap_ssid": "FXPAN",
                    "ap_psk": "stitch2.71", "url": "http://10.42.0.1:8790/",
                    "networks": nets, "message": "AP FXPAN  http://10.42.0.1:8790/"}
        return {"available": True, "mode": "station", "ssid": self.wifi_ssid, "url": url,
                "networks": nets, "message": f"{self.wifi_ssid}  {url}"}

    def _networks(self):
        return [
            {"ssid": self.wifi_ssid, "signal": 78, "security": "WPA2", "in_use": self.wifi_mode == "station"},
            {"ssid": "FXPAN-field", "signal": 64, "security": "WPA2", "in_use": False},
            {"ssid": "workshop-5G", "signal": 41, "security": "WPA3", "in_use": False},
            {"ssid": "cafe", "signal": 22, "security": "", "in_use": False},
        ]

    def api(self, method, path, query, data, port):
        """One /api/* request. Returns a Reply; raises SimError or dual.CamError."""
        q = lambda key: (query.get(key, [""])[0] or "").strip()  # noqa: E731
        if method == "GET":
            if path == "/api/meta":
                return Reply(json=self.meta(port))
            if path == "/api/health":
                return Reply(json={"ok": True, "sim": True})
            if path == "/api/link":
                return Reply(json=self.link())
            if path == "/api/wifi":
                return Reply(json=self.wifi())
            if path == "/api/brightness":
                return Reply(json={**self.brightness(), "message": f"screen {self.bright}%"})
            if path == "/api/live":
                snap = self.live_snapshot()
                return Reply(json={**snap, "message": self.link()["message"]})
            m = re.fullmatch(r"/api/live/([TR])\.jpg", path)
            if m:
                frame = self.jpeg(m.group(1))
                if frame is None:
                    return Reply(code=204, body=b"", ctype="image/jpeg")
                return Reply(body=frame, ctype="image/jpeg")
            if path == "/api/captures":
                pairs = pano.list_pairs(CAPTURES)
                n = sum(1 for row in pairs if row["ready"])
                return Reply(json={"pairs": pairs, "jobs": pano.jobs_snapshot(),
                                   "queue": self.queue_status(),
                                   "disk": pano.disk_stats(CAPTURES),
                                   "message": f"{n} pair(s) in captures/"})
            if path == "/api/pano/job":
                stamp = q("stamp")
                return Reply(json={"job": pano.job_get(stamp) if stamp else {},
                                   "jobs": pano.jobs_snapshot(),
                                   "pairs": pano.list_pairs(CAPTURES),
                                   "disk": pano.disk_stats(CAPTURES)})
            m = re.fullmatch(r"/api/file/([\w.-]+)", path)
            if m:
                dl = q("dl").lower() in ("1", "true", "yes")
                width = q("w")
                try:
                    width = int(width) if width else None
                except ValueError as exc:
                    raise SimError("bad width") from exc
                dest = pano.serve(m.group(1), None if dl else width, CAPTURES)
                return Reply(body=Path(dest).read_bytes(), ctype=pano.content_type(dest),
                             download=m.group(1) if dl else "")
            if path == "/api/detect":
                return Reply(json=self.detect())
            if path == "/api/status":
                return Reply(json=self.status())
            return Reply(code=404, json={"error": "not found"})
        if path == "/api/kiosk/exit":
            return Reply(json={"ok": True, "message": "desktop (sim: nothing to close)"})
        if path == "/api/wifi/scan":
            time.sleep(0.8)
            nets = self._networks()
            return Reply(json={**self.wifi(nets), "message": f"{len(nets)} network(s)"})
        if path == "/api/wifi/join":
            ssid = str(data.get("ssid") or "").strip()
            if not ssid:
                raise SimError("need ssid")
            time.sleep(1.0)
            self.wifi_mode, self.wifi_ssid = "station", ssid
            out = self.wifi()
            return Reply(json={**out, "message": f"joined {ssid}  {out['url']}"})
        if path == "/api/wifi/ap":
            self.wifi_mode = "ap" if _truthy(data.get("on")) else "station"
            out = self.wifi()
            if self.wifi_mode != "ap":
                out["message"] = "AP off"
            return Reply(json=out)
        if path == "/api/brightness":
            try:
                n = int(round(float(data.get("value"))))
            except (TypeError, ValueError) as exc:
                raise SimError("brightness is 1–100") from exc
            self.bright = max(1, min(100, n))
            self.save_prefs({"brightness": self.bright})
            return Reply(json={**self.brightness(), "message": f"screen {self.bright}%"})
        if path == "/api/settings":
            return Reply(json=self.settings_post(data))
        if path == "/api/idle":
            return Reply(json=self.set_idle(_truthy(data.get("idle"))))
        if path == "/api/gpio":
            if "sim" not in data:
                raise SimError("need sim")
            self.gpio_sim = _truthy(data["sim"])
            snap = self.gpio()
            return Reply(json={**snap, "message": "sim as Pi" if snap["sim"] else "sim off"})
        if path == "/api/pair":
            return Reply(json=self.set_pair(data))
        if path == "/api/live/start":
            return Reply(json=self.live_start())
        if path == "/api/live/stop":
            return Reply(json=self.live_stop())
        if path == "/api/set":
            return Reply(json=self.set_exposure(data))
        if path == "/api/shoot":
            return Reply(json=self.shoot(data))
        if path == "/api/captures/delete":
            stamp = str(data.get("stamp") or "").strip()
            side = str(data.get("side") or "").strip().upper()
            info = pano.delete_stamp(stamp, CAPTURES, sides=[side] if side else None)
            return Reply(json={**info, "pairs": pano.list_pairs(CAPTURES),
                               "disk": pano.disk_stats(CAPTURES),
                               "message": f"deleted {stamp}" + (f" {side}" if side else "")
                               + f"  ({info['count']} file(s))"})
        if path == "/api/captures/before-today":
            info = pano.delete_before_today(CAPTURES)
            return Reply(json={**info, "pairs": pano.list_pairs(CAPTURES),
                               "disk": pano.disk_stats(CAPTURES),
                               "message": f"removed {info['count']} before {info['today']}"})
        if path == "/api/captures/keep-last":
            info = pano.keep_last(data.get("n", 5), CAPTURES)
            return Reply(json={**info, "pairs": pano.list_pairs(CAPTURES),
                               "disk": pano.disk_stats(CAPTURES),
                               "message": f"kept {len(info['kept'])}, removed {info['count']}"})
        if path == "/api/captures/protect":
            stamp = str(data.get("stamp") or "").strip()
            info = pano.set_protected(stamp, _truthy(data.get("protected")), CAPTURES)
            return Reply(json={**info, "pairs": pano.list_pairs(CAPTURES),
                               "disk": pano.disk_stats(CAPTURES),
                               "message": f"protected {stamp}" if info["protected"]
                               else f"unlocked {stamp}"})
        if path == "/api/captures/delete-unprotected":
            info = pano.delete_unprotected(CAPTURES)
            msg = f"deleted {info['count']}"
            if info["skipped"]:
                msg += f"  kept {len(info['skipped'])} locked"
            return Reply(json={**info, "pairs": pano.list_pairs(CAPTURES),
                               "disk": pano.disk_stats(CAPTURES), "message": msg})
        if path == "/api/pano":
            return Reply(json=self.stitch(data, data.get("look")))
        return Reply(code=404, json={"error": "not found"})


def _truthy(val):
    if isinstance(val, str):
        return val.strip().lower() not in ("0", "false", "no", "off", "")
    return bool(val)
