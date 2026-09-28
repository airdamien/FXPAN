"""List downloaded T/R JPEG or NEF pairs and stitch a hybrid pano.

After R flop, R is image −X (left) and T is image +X (right) — same order
as LIVE PREVIEW. Match searches overlap, vertical shift, and whether R needs
a flop, so the default below is only a starting guess and a prior.

NEF originals stay on disk. Stitch uses the camera JPEG: either the Fine
companion or the full-size preview embedded in the NEF (Nikon's own tone
curve / WB / NR). Anamorphic squeeze (1.33 / 1.5 / 2) desqueezes P_ after
the splice; P_ and P_*_ana both stay.

Designed overlap by body:

  0.20  FXPAN 65 (openscad/fxpan) — the default. 14.40 mm shift, 64.80 mm
        stitch, 2.711:1. This is the body the name refers to.
  0.20  DX shift kit (openscad/hybrid_shift)
  0.36  FX shift kit (openscad/hybrid_shift FX_MODE) — pass overlap=0.36

The R leg takes one reflection and T takes none, so exactly one frame is
mirrored. find_overlap() detects which, so parity is not a build constraint.

Uses ImageMagick (`magick`) already on this Mac.
"""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
import tempfile
import threading
import shutil
import time
from datetime import date
from pathlib import Path

import dual

MAGICK = os.environ.get("MAGICK", "magick")
_MAGICK_CMDS = {
    "identify", "convert", "mogrify", "composite", "compare", "montage",
}
CAPTURES = Path(__file__).resolve().parent.parent / "captures"


def _cpu_count():
    return max(1, os.cpu_count() or 2)
OVERLAP = 0.20
PAIR_RE = re.compile(r"^(T|R)_(.+)\.(jpe?g|nef)$", re.I)
PANO_RE = re.compile(r"^P_(.+)\.(jpe?g)$", re.I)
PANO_ANA_RE = re.compile(r"^P_(.+)_ana\.(jpe?g)$", re.I)
MASTER_RE = re.compile(r"^P_(.+)_master\.(tiff?)$", re.I)
JPEG_EXTS = {".jpg", ".jpeg"}
RAW_EXTS = {".nef"}
SAFE = re.compile(r"^[\w.-]+$")
DAY_RE = re.compile(r"^(\d{8})_")
MODES = ("match", "blend", "cut", "open", "hugin")
WORK = 360
HUGIN_DIR = Path(__file__).resolve().parent / "templates"
HUGIN_PROFILE = HUGIN_DIR / "fxpan.json"

_jobs = {}
_jobs_lock = threading.Lock()
_queue = []
_queue_lock = threading.Lock()

_EXIF_PROG = {1: "M", 2: "P", 3: "A", 4: "S", 5: "Creative", 6: "Action",
              7: "Portrait", 8: "Landscape"}
_EXIF_WB = {0: "Auto", 1: "Manual"}


def _venv_site():
    root = Path(__file__).resolve().parent / ".venv"
    lib = root / "lib"
    if not lib.is_dir():
        return
    for path in sorted(lib.glob("python*/site-packages")):
        p = str(path)
        if p not in sys.path:
            sys.path.insert(0, p)


def _magick(args, timeout=600, binary=False):
    n = _cpu_count()
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(n)
    # Policy default is ~1 GiB / 3 threads; D800 36 MP composites need RAM
    # or Magick spills to disk and looks single-core.
    # Limits after identify/convert: `magick -limit … identify` treats
    # identify as a filename → "no decode delegate for this image format `'".
    limits = [
        "-limit", "thread", str(n),
        "-limit", "memory", "4GiB",
        "-limit", "map", "6GiB",
    ]
    env["MAGICK_THREAD_LIMIT"] = str(n)
    env["MAGICK_MEMORY_LIMIT"] = "4GiB"
    env["MAGICK_MAP_LIMIT"] = "6GiB"
    if args and args[0] in _MAGICK_CMDS:
        prefixed = [args[0], *limits, *args[1:]]
    else:
        prefixed = [*limits, *args]
    try:
        proc = subprocess.run(
            [MAGICK, *prefixed],
            capture_output=True,
            text=not binary,
            timeout=timeout,
            env=env,
        )
    except FileNotFoundError as exc:
        raise dual.CamError("ImageMagick `magick` not found") from exc
    if proc.returncode:
        err = proc.stderr if binary else (proc.stderr or proc.stdout or "")
        if isinstance(err, bytes):
            err = err.decode("utf-8", "replace")
        err = (err or "magick failed").strip()
        raise dual.CamError(err.split("\n")[-1])
    return proc.stdout


def _size(path):
    w, h = _magick(["identify", "-format", "%w %h", str(path)]).split()
    return int(w), int(h)


def _pair_kind(name):
    ext = Path(name).suffix.lower()
    if ext in JPEG_EXTS:
        return "jpg"
    if ext in RAW_EXTS:
        return "nef"
    return ""


def _scan_pairs(root):
    """stamp → role → {jpg: name, nef: name}."""
    sides = {}
    root = Path(root)
    if not root.is_dir():
        return sides
    for path in root.iterdir():
        if not path.is_file():
            continue
        m = PAIR_RE.match(path.name)
        if not m:
            continue
        kind = _pair_kind(path.name)
        if not kind:
            continue
        sides.setdefault(m.group(2), {}).setdefault(m.group(1).upper(), {})[kind] = path.name
    return sides


def master_path(root, stamp):
    return Path(root) / f"P_{stamp}_master.tif"


def _stamp_of(name):
    """Stamp a capture file belongs to, or None."""
    for rx in (PANO_ANA_RE, MASTER_RE):
        m = rx.match(name)
        if m:
            return m.group(1)
    m = PAIR_RE.match(name)
    if m:
        return m.group(2)
    m = PANO_RE.match(name)
    return m.group(1) if m else None


def _scan_panos(root):
    """Return (native, ana) maps stamp → filename. ANA names are not native."""
    native, ana = {}, {}
    root = Path(root)
    if not root.is_dir():
        return native, ana
    for path in root.iterdir():
        if not path.is_file():
            continue
        m = PANO_ANA_RE.match(path.name)
        if m:
            ana[m.group(1)] = path.name
            continue
        m = PANO_RE.match(path.name)
        if m:
            native[m.group(1)] = path.name
    return native, ana


def extract_nef_jpeg(src, dest):
    """Pull the largest embedded JPEG from a Nikon NEF (camera preview)."""
    src, dest = Path(src), Path(dest)
    try:
        data = src.read_bytes()
    except OSError as exc:
        raise dual.CamError(f"read {src.name}") from exc
    best = b""
    start = 0
    while True:
        i = data.find(b"\xff\xd8\xff", start)
        if i < 0:
            break
        j = data.find(b"\xff\xd9", i + 3)
        if j < 0:
            break
        blob = data[i:j + 2]
        if len(blob) > len(best):
            best = blob
        start = i + 2
    if len(best) < 128:
        raise dual.CamError(f"no JPEG preview in {src.name}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(f".{dest.name}.{os.getpid()}.tmp")
    try:
        tmp.write_bytes(best)
        tmp.replace(dest)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
    return dest


def working_jpeg(role_files, stamp, role, root):
    """Camera JPEG for stitch/preview. Fine companion wins; else NEF preview."""
    root = Path(root)
    got = role_files or {}
    jpg = got.get("jpg")
    if jpg:
        path = root / jpg
        if path.is_file():
            return path
    nef = got.get("nef")
    if not nef:
        return None
    src = root / nef
    if not src.is_file():
        return None
    dest = root / f"{role}_{stamp}.jpg"
    if dest.is_file() and dest.stat().st_mtime >= src.stat().st_mtime:
        return dest
    return extract_nef_jpeg(src, dest)


RAW_MAX_GAIN = 8.0


def _raw_tone(lin, gain):
    """Linear 0..1 → display 0..1: gain, then a shoulder instead of a clip.

    Extended Reinhard with the white point at `gain`, so sensor white lands
    on 1.0 and the highlights the camera JPEG clips roll off instead.
    """
    import numpy as np

    x = lin * np.float32(gain)
    w2 = np.float32(gain * gain)
    y = x * (1 + x / w2) / (1 + x)
    return np.power(np.clip(y, 0, 1), np.float32(1 / 2.2))


# Nikon Standard Picture Control, roughly: an S-curve about mid-grey and
# more colour. Display only; the TIFF master never gets it.
LOOK_CONTRAST = 0.35
LOOK_SATURATION = 1.20


def _nikon_look(y):
    """Display-referred BGR 0..1 → contrast + saturation, still 0..1."""
    import numpy as np

    s = y * y * (3 - 2 * y)
    y = y + np.float32(LOOK_CONTRAST) * (s - y)
    luma = (
        np.float32(0.0722) * y[..., 0]
        + np.float32(0.7152) * y[..., 1]
        + np.float32(0.2126) * y[..., 2]
    )[..., None]
    return np.clip(luma + np.float32(LOOK_SATURATION) * (y - luma), 0, 1)


def _raw_display(lin, gain, look):
    """Linear BGR 0..1 → display BGR 0..1 (gain, shoulder, optional look)."""
    y = _raw_tone(lin, gain)
    return _nikon_look(y) if look else y


def _raw_gain(t_lin, t_jpeg, look=True):
    """One gain for both bodies: T's display render matches its camera JPEG's mean."""
    import cv2
    import numpy as np

    ref = cv2.imread(str(t_jpeg), cv2.IMREAD_REDUCED_GRAYSCALE_4) if t_jpeg else None
    if ref is None:
        return 1.0
    want = float((ref.astype(np.float32) / 255.0).mean())
    sample = t_lin[::16, ::16].astype(np.float32) / 65535.0

    def mean(g):
        return float(_raw_display(sample, g, look).mean())

    lo, hi = 0.25, RAW_MAX_GAIN
    if mean(hi) <= want:
        return hi
    if mean(lo) >= want:
        return lo
    for _ in range(14):
        mid = (lo * hi) ** 0.5
        if mean(mid) < want:
            lo = mid
        else:
            hi = mid
    return (lo * hi) ** 0.5


def develop_pair(t_nef, r_nef, size=None, on_log=None, t_jpeg=None, look=True):
    """Develop both NEFs the same way, linear 16-bit BGR.

    Returns {"t", "r", "gain"}. T's as-shot white balance goes on both so
    the halves meet without a colour step. The pixels stay linear and
    ungained so the TIFF master keeps every level of the 14-bit NEF; `gain`
    (matched to T's camera JPEG when given) is for the display JPEG only.
    size=(w, h) crops to the camera JPEG frame.
    """
    try:
        import rawpy
    except ImportError as exc:
        raise dual.CamError("rawpy missing — .venv/bin/pip install rawpy") from exc
    import numpy as np
    from concurrent.futures import ThreadPoolExecutor

    with rawpy.imread(str(t_nef)) as raw:
        wb = [float(v) for v in raw.camera_whitebalance]
    if not any(wb[:3]):
        wb = None

    def linear(path):
        with rawpy.imread(str(path)) as raw:
            return raw.postprocess(
                output_bps=16, no_auto_bright=True, gamma=(1, 1),
                use_camera_wb=wb is None, user_wb=wb,
                highlight_mode=rawpy.HighlightMode.Blend,
            )

    def crop(rgb):
        img = rgb[:, :, ::-1]
        if size:
            tw, th = size
            h, w = img.shape[:2]
            if w >= tw and h >= th:
                x, y = (w - tw) // 2, (h - th) // 2
                img = img[y:y + th, x:x + tw]
        return np.ascontiguousarray(img)

    if on_log:
        on_log("raw  developing T and R NEFs (T white balance on both)")
    with ThreadPoolExecutor(max_workers=2) as pool:
        ft = pool.submit(lambda: crop(linear(t_nef)))
        fr = pool.submit(lambda: crop(linear(r_nef)))
        t_lin, r_lin = ft.result(), fr.result()
    gain = _raw_gain(t_lin, t_jpeg, look)
    if on_log:
        on_log(f"raw  display ×{gain:.2f}, highlight shoulder"
               + (", Nikon-like look" if look else ", neutral"))
    return {"t": t_lin, "r": r_lin, "gain": gain}


def _srgb_lut16():
    """Linear 16-bit code → sRGB-encoded 16-bit code.

    Distinct on every 4th level (the blend keeps 14 bits), so no NEF level
    merges with its neighbour, even at the top where sRGB is flattest.
    """
    import numpy as np

    x = np.arange(65536, dtype=np.float64) / 65535.0
    y = np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)
    return np.round(y * 65535.0).astype(np.uint16)


def write_master_tiff(path, lin):
    """16-bit sRGB TIFF, Deflate + horizontal predictor (lossless)."""
    import cv2
    import numpy as np

    path = Path(path)
    out = np.take(_srgb_lut16(), lin)
    params = []
    for key, val in (
        ("IMWRITE_TIFF_COMPRESSION", "IMWRITE_TIFF_COMPRESSION_ADOBE_DEFLATE"),
        ("IMWRITE_TIFF_PREDICTOR", "IMWRITE_TIFF_PREDICTOR_HORIZONTAL"),
    ):
        if hasattr(cv2, key) and hasattr(cv2, val):
            params += [int(getattr(cv2, key)), int(getattr(cv2, val))]
    tmp = path.with_name(f".{path.stem}.{os.getpid()}.tmp.tif")
    try:
        if not cv2.imwrite(str(tmp), out, params):
            raise dual.CamError(f"cannot write {path.name}")
        tmp.replace(path)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
    return path


def write_raw_display(path, lin, gain, look):
    """Display JPEG from the linear blend, in row bands to keep memory flat."""
    import numpy as np

    out = np.empty(lin.shape, np.uint8)
    for y in range(0, lin.shape[0], 256):
        band = lin[y:y + 256].astype(np.float32) / np.float32(65535.0)
        out[y:y + 256] = (_raw_display(band, gain, look) * 255.0 + 0.5).astype(np.uint8)
    _write_jpeg(path, out)


def _raw_view_u8(lin, gain):
    """8-bit gamma view of linear 16-bit for SIFT (it cannot see linear shadows)."""
    import numpy as np

    lut = (np.clip(_raw_tone(np.arange(65536, dtype=np.float32) / 65535.0, gain), 0, 1)
           * 255.0 + 0.5).astype(np.uint8)
    return np.take(lut, lin)


def ensure_pair_jpegs(stamp, root=None):
    """Make sure T/R JPEGs exist for this stamp. NEF originals are left in place."""
    root = Path(root or CAPTURES)
    files = _scan_pairs(root).get(stamp) or {}
    out = {}
    for role in ("T", "R"):
        path = working_jpeg(files.get(role), stamp, role, root)
        if path is not None:
            out[role] = path
    return out


def desqueeze_jpeg(src, dest, squeeze, on_log=None):
    """Widen a squeezed splice by `squeeze` (2× HD → 5.42:1)."""
    squeeze = float(squeeze)
    if squeeze < 1.05:
        return None
    src, dest = Path(src), Path(dest)
    w, h = _size(src)
    nw = max(w + 1, int(round(w * squeeze)))
    if on_log:
        on_log(f"ana  {squeeze:g}×  {w}×{h} → {nw}×{h}")
    tmp = dest.with_name(f".{dest.name}.{os.getpid()}.tmp")
    try:
        _magick([
            str(src), "-filter", "Lanczos",
            "-resize", f"{nw}x{h}!",
            "-quality", "92",
            str(tmp),
        ])
        tmp.replace(dest)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
    return dest


def _finish_pano(info, dest, stamp, root, squeeze, on_log, t0):
    sq = float(squeeze or 1.0)
    dest = Path(dest)
    if sq >= 1.05 and dest.is_file():
        ana = Path(root) / f"P_{stamp}_ana.jpg"
        try:
            desqueeze_jpeg(dest, ana, sq, on_log)
            info["pano_ana"] = ana.name
            info["squeeze"] = sq
            aw, ah = _size(ana)
            info["ana_width"] = aw
            info["ana_height"] = ah
            msg = (info.get("message") or "").rstrip()
            extra = f"ana {sq:g}× {aw}×{ah}"
            info["message"] = f"{msg}  {extra}" if msg else extra
        except dual.CamError as exc:
            if on_log:
                on_log(f"ana failed: {exc}")
            info["ana_error"] = str(exc)
    _with_sec(info, t0)
    _write_sidecar(root, stamp, info)
    return info


def _sidecar_path(root, stamp):
    return Path(root) / f"P_{stamp}.json"


def _read_sidecar(root, stamp):
    path = _sidecar_path(root, stamp)
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _write_sidecar(root, stamp, info):
    path = _sidecar_path(root, stamp)
    keep = {
        k: info[k]
        for k in (
            "mode", "overlap", "overlap_frac", "dy", "flip_r", "rmse",
            "width", "height", "file", "message", "phase", "error",
            "deghost", "sec", "engine", "squeeze", "pano_ana",
            "ana_width", "ana_height", "source", "look", "master",
        )
        if k in info
    }
    path.write_text(json.dumps(keep, indent=2) + "\n")


def _with_sec(info, t0):
    sec = round(max(0.0, time.monotonic() - t0), 1)
    info["sec"] = sec
    msg = (info.get("message") or "").rstrip()
    info["message"] = f"{msg}  {sec:.1f}s" if msg else f"{sec:.1f}s"
    return info


def jobs_snapshot():
    with _jobs_lock:
        return {k: dict(v) for k, v in _jobs.items()}


def job_get(stamp):
    with _jobs_lock:
        cur = _jobs.get(stamp)
        return dict(cur) if cur else {}


def job_put(stamp, **kw):
    with _jobs_lock:
        cur = _jobs.setdefault(stamp, {"stamp": stamp, "log": [], "running": False})
        line = kw.pop("log", None)
        if line:
            log = list(cur.get("log") or [])
            log.append(line)
            cur["log"] = log[-24:]
            cur["message"] = line
        cur.update(kw)
        return dict(cur)


def _stitch_of(root, stamp):
    info = dict(_read_sidecar(root, stamp))
    live = job_get(stamp)
    if live:
        info.update({k: live[k] for k in live if k != "log"})
        if live.get("log"):
            info["log"] = live["log"]
    return info


def _u16(buf, off, le):
    return int.from_bytes(buf[off:off + 2], "little" if le else "big")


def _u32(buf, off, le):
    return int.from_bytes(buf[off:off + 4], "little" if le else "big")


def _rational(buf, off, le, signed=False):
    if signed:
        n = int.from_bytes(buf[off:off + 4], "little" if le else "big", signed=True)
        d = int.from_bytes(buf[off + 4:off + 8], "little" if le else "big", signed=True)
    else:
        n = _u32(buf, off, le)
        d = _u32(buf, off + 4, le)
    return n, d


def _ifd_values(buf, off, le):
    if off + 2 > len(buf):
        return {}
    n = _u16(buf, off, le)
    out = {}
    for i in range(n):
        e = off + 2 + i * 12
        if e + 12 > len(buf):
            break
        tag = _u16(buf, e, le)
        typ = _u16(buf, e + 2, le)
        cnt = _u32(buf, e + 4, le)
        val = buf[e + 8:e + 12]
        size = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 9: 4, 10: 8}.get(typ)
        if not size or cnt > 64:
            continue
        nbytes = size * cnt
        data = val if nbytes <= 4 else buf[_u32(buf, e + 8, le):_u32(buf, e + 8, le) + nbytes]
        if len(data) < nbytes:
            continue
        if typ == 2:
            out[tag] = data.split(b"\x00", 1)[0].decode("ascii", "replace").strip()
        elif typ == 3:
            out[tag] = _u16(data, 0, le)
        elif typ == 4:
            out[tag] = _u32(data, 0, le)
        elif typ == 5:
            out[tag] = _rational(data, 0, le)
        elif typ == 10:
            out[tag] = _rational(data, 0, le, signed=True)
    return out


def _ratio_text(val):
    if not isinstance(val, tuple) or len(val) != 2 or not val[1]:
        return ""
    n, d = val
    if n == 0:
        return "0"
    if abs(n) >= abs(d):
        sec = n / d
        if abs(sec - round(sec)) < 0.05:
            return str(int(round(sec)))
        return f"{sec:.1f}".rstrip("0").rstrip(".")
    inv = abs(d / n)
    k = int(round(inv))
    if k >= 2 and abs(inv - k) < 0.08 * k:
        return f"1/{k}"
    return f"{n}/{d}"


def _format_exif(tags):
    info = {}
    iso = tags.get(0x8827) or tags.get(0x8833)
    if iso:
        info["iso"] = str(iso)
    shut = _ratio_text(tags.get(0x829A))
    if shut:
        info["shutter"] = shut
    fnum = _ratio_text(tags.get(0x829D))
    if fnum and fnum not in ("0", "0.0"):
        info["f"] = fnum
    prog = _EXIF_PROG.get(tags.get(0x8822))
    if prog:
        info["program"] = prog
    wb = _EXIF_WB.get(tags.get(0xA403))
    if wb:
        info["wb"] = wb
    taken = tags.get(0x9003)
    if isinstance(taken, str) and taken:
        info["taken"] = taken.replace(":", "-", 2)
    model = tags.get(0x0110)
    if isinstance(model, str) and model:
        info["model"] = model.replace("NIKON ", "").replace("Nikon ", "")
    make = tags.get(0x010F)
    if isinstance(make, str) and make:
        info["make"] = make
    ec = tags.get(0x9204)
    if isinstance(ec, tuple) and ec[1]:
        ev = ec[0] / ec[1]
        if abs(ev) >= 0.05:
            info["ec"] = f"{ev:+.1f}"
    return info


def read_exif(path):
    """ISO / shutter / program from JPEG EXIF. Empty if the file has none."""
    try:
        data = Path(path).read_bytes()[:131072]
    except OSError:
        return {}
    if data[:2] != b"\xff\xd8":
        return {}
    i = 2
    while i + 4 <= len(data) and data[i] == 0xFF:
        marker = data[i + 1]
        if marker in (0xD8, 0xD9):
            i += 2
            continue
        if marker == 0xDA:
            break
        seglen = int.from_bytes(data[i + 2:i + 4], "big")
        if seglen < 2:
            break
        if marker == 0xE1:
            payload = data[i + 4:i + 2 + seglen]
            if payload.startswith(b"Exif\x00\x00") and len(payload) > 14:
                tiff = payload[6:]
                le = tiff[:2] == b"II"
                if tiff[:2] not in (b"II", b"MM"):
                    return {}
                tags = _ifd_values(tiff, _u32(tiff, 4, le), le)
                exif_off = tags.get(0x8769)
                if isinstance(exif_off, int):
                    tags.update(_ifd_values(tiff, exif_off, le))
                return _format_exif(tags)
        i += 2 + seglen
    return {}


def _exif_cache_path(root, stamp):
    return Path(root) / f"X_{stamp}.json"


def refresh_exif(root, stamp):
    """Read T/R EXIF and write X_<stamp>.json. Returns {T: {...}, R: {...}}."""
    root = Path(root or CAPTURES)
    have = {}
    files = _scan_pairs(root).get(stamp) or {}
    for role in ("T", "R"):
        got = files.get(role) or {}
        name = got.get("jpg") or got.get("nef")
        if name:
            have[role] = name
    return pair_exif(root, stamp, have)


def pair_exif(root, stamp, have):
    root = Path(root)
    cache = _exif_cache_path(root, stamp)
    newest = 0.0
    for name in have.values():
        path = root / name
        if path.is_file():
            newest = max(newest, path.stat().st_mtime)
    if cache.is_file() and newest and cache.stat().st_mtime >= newest:
        try:
            data = json.loads(cache.read_text())
            if isinstance(data, dict):
                return {k: v for k, v in data.items() if k in ("T", "R") and isinstance(v, dict)}
        except (OSError, json.JSONDecodeError):
            pass
    out = {}
    for role in ("T", "R"):
        name = have.get(role)
        if not name:
            continue
        info = read_exif(root / name)
        if info:
            out[role] = info
    if out:
        cache.write_text(json.dumps(out, indent=2) + "\n")
    elif cache.is_file():
        cache.unlink()
    return out


def list_pairs(root=None):
    root = Path(root or CAPTURES)
    sides = _scan_pairs(root)
    panos, panos_ana = _scan_panos(root)
    stamps = set(sides) | set(panos) | set(panos_ana)
    locked = protected_set(root)
    rows = []
    for stamp in stamps:
        have = sides.get(stamp) or {}
        t_files = have.get("T") or {}
        r_files = have.get("R") or {}
        t_jpg, t_nef = t_files.get("jpg"), t_files.get("nef")
        r_jpg, r_nef = r_files.get("jpg"), r_files.get("nef")
        have_exif = {}
        if t_jpg or t_nef:
            have_exif["T"] = t_jpg or t_nef
        if r_jpg or r_nef:
            have_exif["R"] = r_jpg or r_nef
        rows.append(
            {
                "stamp": stamp,
                "t": t_jpg or t_nef,
                "r": r_jpg or r_nef,
                "t_nef": t_nef,
                "r_nef": r_nef,
                "pano": panos.get(stamp),
                "pano_ana": panos_ana.get(stamp),
                "master": (
                    master_path(root, stamp).name if master_path(root, stamp).is_file() else None
                ),
                "pano_mtime": _mtime(root / panos[stamp]) if panos.get(stamp) else 0,
                "pano_ana_mtime": (
                    _mtime(root / panos_ana[stamp]) if panos_ana.get(stamp) else 0
                ),
                "ready": bool((t_jpg or t_nef) and (r_jpg or r_nef)),
                "protected": stamp in locked,
                "exif": pair_exif(root, stamp, have_exif),
                "stitch": _stitch_of(root, stamp),
            }
        )
    rows.sort(key=lambda row: row["stamp"], reverse=True)
    return rows


def disk_stats(root=None):
    """Free space on the captures volume and a rough remaining-set count."""
    root = Path(root or CAPTURES)
    root.mkdir(parents=True, exist_ok=True)
    usage = shutil.disk_usage(root)
    sizes = []
    if root.is_dir():
        by_stamp = {}
        for path in root.iterdir():
            if not path.is_file() or path.suffix.lower() not in (".jpg", ".jpeg", ".nef", ".tif"):
                continue
            stamp = _stamp_of(path.name)
            if not stamp:
                continue
            by_stamp.setdefault(stamp, 0)
            try:
                by_stamp[stamp] += path.stat().st_size
            except OSError:
                pass
        sizes = [n for n in by_stamp.values() if n > 0]
    avg = int(sorted(sizes)[len(sizes) // 2]) if sizes else 0
    if not avg:
        avg = 14_000_000
    shots = int(usage.free // avg) if avg else 0
    return {
        "total": usage.total,
        "used": usage.used,
        "free": usage.free,
        "avg_set": avg,
        "sets": len(sizes),
        "shots": shots,
    }


def _protect_path(root):
    return Path(root or CAPTURES) / "protected.json"


def protected_set(root=None):
    path = _protect_path(root)
    if not path.is_file():
        return set()
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return set()
    if isinstance(data, dict):
        data = data.get("stamps") or []
    if not isinstance(data, list):
        return set()
    return {str(s) for s in data if s and "/" not in str(s) and ".." not in str(s)}


def set_protected(stamp, on, root=None):
    if not stamp or "/" in stamp or ".." in stamp:
        raise dual.CamError("bad stamp")
    root = Path(root or CAPTURES)
    stamps = protected_set(root)
    if on:
        stamps.add(stamp)
    else:
        stamps.discard(stamp)
    path = _protect_path(root)
    if stamps:
        path.write_text(json.dumps(sorted(stamps), indent=2) + "\n")
    elif path.is_file():
        path.unlink()
    return {"stamp": stamp, "protected": stamp in stamps}


def _prune_protected(root, stamp):
    left = Path(root).is_dir() and any(
        _stamp_of(path.name) == stamp for path in Path(root).iterdir()
    )
    if not left:
        set_protected(stamp, False, root)


def resolve(name, root=None):
    root = Path(root or CAPTURES).resolve()
    if not SAFE.fullmatch(name or ""):
        raise dual.CamError("bad name")
    path = (root / name).resolve()
    if path.parent != root or not path.is_file():
        raise dual.CamError("missing")
    return path


def content_type(path):
    ext = Path(path).suffix.lower()
    if ext in (".jpg", ".jpeg"):
        return "image/jpeg"
    if ext == ".png":
        return "image/png"
    if ext == ".nef":
        return "application/octet-stream"
    if ext in (".tif", ".tiff"):
        return "image/tiff"
    raise dual.CamError("not an image")


def _mtime(path):
    try:
        return int(Path(path).stat().st_mtime)
    except OSError:
        return 0


def thumb(name, width, root=None):
    root = Path(root or CAPTURES)
    src = resolve(name, root)
    width = max(80, min(2560, int(width)))
    dest_dir = root / ".thumbs"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{width}_{src.name}"
    if dest.exists() and dest.stat().st_mtime >= src.stat().st_mtime:
        return dest
    tmp = dest.with_name(f".{dest.name}.{os.getpid()}.tmp")
    try:
        # Width cap only. A square box plus CSS object-fit:cover was
        # cropping hybrid panos (~2.7:1) to 3:2.
        _magick([str(src), "-thumbnail", f"{width}x", "-quality", "70", str(tmp)])
        tmp.replace(dest)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
    return dest


def serve(name, width=None, root=None):
    src = resolve(name, root)
    if src.suffix.lower() in RAW_EXTS:
        if not width:
            return src
        m = PAIR_RE.match(src.name)
        if not m:
            raise dual.CamError("not an image")
        jpg = working_jpeg(
            {"nef": src.name}, m.group(2), m.group(1).upper(), src.parent
        )
        if jpg is None:
            raise dual.CamError("not an image")
        try:
            return thumb(jpg.name, width, src.parent)
        except dual.CamError:
            return jpg
    if width:
        try:
            return thumb(name, width, root)
        except dual.CamError:
            pass
    return src


def find_pair(stamp, root=None):
    root = Path(root or CAPTURES)
    if not stamp or "/" in stamp or ".." in stamp:
        raise dual.CamError("bad stamp")
    got = ensure_pair_jpegs(stamp, root)
    if "T" not in got or "R" not in got:
        raise dual.CamError(f"need T and R for {stamp}")
    return got["T"], got["R"]


class _Gray:
    __slots__ = ("w", "h", "pix")

    def __init__(self, w, h, pix):
        self.w, self.h, self.pix = w, h, pix


def _parse_pgm(data):
    if not data.startswith(b"P5"):
        raise dual.CamError("gray preview failed")
    i = 2
    if data[i:i + 1] in (b"\n", b"\r"):
        i += 1
    def token():
        nonlocal i
        while i < len(data) and data[i:i + 1] in (b" ", b"\t", b"\n", b"\r"):
            i += 1
        if i < len(data) and data[i:i + 1] == b"#":
            while i < len(data) and data[i:i + 1] not in (b"\n", b"\r"):
                i += 1
            return token()
        j = i
        while i < len(data) and data[i:i + 1] not in (b" ", b"\t", b"\n", b"\r"):
            i += 1
        return data[j:i]
    w, h, mx = int(token()), int(token()), int(token())
    if mx != 255:
        raise dual.CamError("gray preview failed")
    if i < len(data) and data[i:i + 1] in (b"\n", b"\r"):
        i += 1
    pix = data[i:i + w * h]
    if len(pix) < w * h:
        raise dual.CamError("gray preview failed")
    return _Gray(w, h, pix)


def _gray(path, width=WORK):
    raw = _magick(
        [str(path), "-colorspace", "gray", "-resize", f"{width}x", "-depth", "8", "pgm:-"],
        binary=True,
    )
    return _parse_pgm(raw)


def _score_ol(t, r, ol, dy):
    y0t = max(0, -dy)
    y0r = max(0, dy)
    rows = min(t.h - y0t, r.h - y0r)
    if rows < 8 or ol < 4 or ol >= t.w or ol >= r.w:
        return 1e9
    xr = r.w - ol
    tp, rp = t.pix, r.pix
    tw, rw = t.w, r.w
    i0 = int(rows * 0.22)
    i1 = max(i0 + 8, int(rows * 0.78))
    n = (i1 - i0) * ol
    sumt = sumr = sumt2 = sumr2 = sumtr = 0
    for i in range(i0, i1):
        toff = (y0t + i) * tw
        roff = (y0r + i) * rw + xr
        for x in range(ol):
            tv = tp[toff + x]
            rv = rp[roff + x]
            sumt += tv
            sumr += rv
            sumt2 += tv * tv
            sumr2 += rv * rv
            sumtr += tv * rv
    n = float(n)
    mt, mr = sumt / n, sumr / n
    vt = sumt2 / n - mt * mt
    vr = sumr2 / n - mr * mr
    if vt < 8 or vr < 8:
        return 1e9
    ncc = (sumtr / n - mt * mr) / (vt * vr) ** 0.5
    frac = ol / t.w
    return (1.0 - ncc) + 0.004 * abs(dy) + 0.10 * abs(frac - OVERLAP)


def _search_shift(t, r, on_log=None, max_dy=None):
    if max_dy is None:
        max_dy = min(8, t.h // 24)
    max_dy = max(0, int(max_dy))
    best = (1e9, OVERLAP, 0)
    for pct in range(10, 43, 3):
        ol = max(4, int(round(t.w * pct / 100)))
        for dy in range(-max_dy, max_dy + 1, 2 if max_dy else 1):
            s = _score_ol(t, r, ol, dy)
            if s < best[0]:
                best = (s, pct / 100, dy)
                if on_log:
                    on_log(f"search ol={pct}% dy={dy:+d}  {s:.1f}")
    pct0 = int(round(best[1] * 100))
    dy0 = best[2]
    for pct in range(max(10, pct0 - 3), min(44, pct0 + 4)):
        ol = max(4, int(round(t.w * pct / 100)))
        for dy in range(max(-max_dy, dy0 - 3), min(max_dy, dy0 + 3) + 1):
            s = _score_ol(t, r, ol, dy)
            if s < best[0]:
                best = (s, pct / 100, dy)
    return best


def find_overlap(t_path, r_path, try_flip=True, on_log=None, max_dy=None):
    def log(msg):
        if on_log:
            on_log(msg)

    t = _gray(t_path)
    candidates = [(False, r_path)]
    tmp = None
    if try_flip:
        tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
        tmp.close()
        _magick([str(r_path), "-flop", tmp.name])
        candidates.append((True, Path(tmp.name)))
    best = None
    try:
        for flop, path in candidates:
            log("gray " + ("flop" if flop else "as-shot"))
            r = _gray(path)
            rmse, frac, dy = _search_shift(t, r, on_log=log, max_dy=max_dy)
            row = (rmse, flop, frac, dy)
            log(f"{'flop' if flop else 'as-shot'}  ol={frac:.0%} dy={dy:+d}  {rmse:.1f}")
            if best is None:
                best = row
            elif flop and rmse < best[0] * 0.92:
                best = row
            elif (not flop) and rmse <= best[0]:
                best = row
    finally:
        if tmp:
            Path(tmp.name).unlink(missing_ok=True)
    rmse, flop, frac, dy = best
    return {"rmse": rmse, "flip_r": flop, "overlap": frac, "dy": dy}


def _search_align(
    t_path, r_path, overlap, flip_r, dy=0, on_log=None, weak_rmse=0.42, max_dy=None,
):
    """Measure overlap / flop. max_dy=0 keeps the frames vertically locked."""
    found = find_overlap(
        t_path, r_path, try_flip=True, on_log=on_log, max_dy=max_dy,
    )
    if found["rmse"] <= weak_rmse:
        overlap = found["overlap"]
        flip_r = found["flip_r"]
        if max_dy == 0:
            dy = 0
        else:
            tw, _ = _size(t_path)
            dy = int(round(found["dy"] * (tw / WORK)))
        if on_log:
            on_log(
                f"align ol={overlap:.0%} dy={dy:+d} "
                f"flip={'on' if flip_r else 'off'}  {found['rmse']:.2f}"
            )
    elif on_log:
        on_log(
            f"align weak ({found['rmse']:.2f}) — keep ol={overlap:.0%} "
            f"dy={dy:+d} flip={'on' if flip_r else 'off'}"
        )
    return overlap, flip_r, dy, found


def _mean(path):
    return float(_magick(["identify", "-format", "%[fx:mean]", str(path)]))


def _overlap_scale(t_path, r_path, overlap=OVERLAP):
    """R-east / T-west strip mean. Paths must already be oriented (R flopped if needed).

    Full-frame means are the wrong signal on a hybrid pano: T and R see different
    halves of the scene, so a dark unique half on T and a bright unique half on R
    drive the scale the wrong way. The designed overlap is the same object.
    """
    overlap = float(overlap)
    w, h = _size(t_path)
    ol = max(1, min(w - 1, int(round(w * overlap))))
    x = w - ol
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        _magick([
            str(r_path), "-colorspace", "sRGB",
            "-crop", f"{ol}x{h}+{x}+0", "+repage", str(tmp / "rol.png"),
        ])
        _magick([
            str(t_path), "-colorspace", "sRGB",
            "-crop", f"{ol}x{h}+0+0", "+repage", str(tmp / "tol.png"),
        ])
        t_m, r_m = _mean(tmp / "tol.png"), _mean(tmp / "rol.png")
    if r_m <= 0.02 or t_m <= 0.02:
        return None
    return t_m / r_m


def _balance_r(t_path, r_path, dest, overlap=OVERLAP, on_log=None):
    """Scale R so the overlap strip matches T. Returns the path to use for R."""
    scale = _overlap_scale(t_path, r_path, overlap)
    if scale is None:
        return Path(r_path)
    if abs(scale - 1) <= 0.03:
        return Path(r_path)
    if not (0.40 <= scale <= 2.50):
        if on_log:
            on_log(f"balance skip R ×{scale:.2f} (overlap too different)")
        return Path(r_path)
    dest = Path(dest)
    if on_log:
        on_log(f"balance R ×{scale:.2f} (overlap)")
    _magick([str(r_path), "-evaluate", "multiply", f"{scale:.4f}", str(dest)])
    return dest


def _strip_mean(path, w, h, x0, x1):
    x0 = max(0, min(w - 1, int(x0)))
    x1 = max(x0 + 1, min(w, int(x1)))
    with tempfile.TemporaryDirectory() as tmp:
        crop = Path(tmp) / "s.png"
        _magick([
            str(path), "-crop", f"{x1 - x0}x{h}+{x0}+0", "+repage", str(crop),
        ])
        return _mean(crop)


def _lift_unique(path, dest, east, overlap=OVERLAP, on_log=None):
    """Brighten the unique half so a stopped-down taking lens matches the overlap.

    Hybrid T unique is east, flopped R unique is west. The overlap is on-axis
    enough to stay lit at f/5.6; the far edge goes black by f/8.
    """
    path = Path(path)
    w, h = _size(path)
    ol = max(1, min(w - 1, int(round(w * float(overlap)))))
    edge = max(4, int(round(w * 0.08)))
    if east:
        mid = _strip_mean(path, w, h, 0, ol)
        rim = _strip_mean(path, w, h, w - edge, w)
        x0, x1 = ol, w - 1
    else:
        mid = _strip_mean(path, w, h, w - ol, w)
        rim = _strip_mean(path, w, h, 0, edge)
        x0, x1 = 0, w - ol
    if rim <= 0.02 or mid <= 0.02:
        return path
    gain = mid / rim
    if gain < 1.12:
        return path
    if gain > 2.50:
        gain = 2.50
    dest = Path(dest)
    extra = f"{gain - 1:.4f}"
    _magick([
        str(path),
        "(", "+clone",
        "(", "-size", f"{w}x{h}", "xc:black",
        "-sparse-color", "barycentric",
        f"{x0},0 black {x1},0 white", ")",
        "-compose", "multiply", "-composite",
        "-evaluate", "multiply", extra, ")",
        "-compose", "plus", "-composite",
        str(dest),
    ])
    if on_log:
        side = "T-east" if east else "R-west"
        on_log(f"vignette {side} ×{gain:.2f} (unique vs overlap)")
    return dest


def _match_seam_img(img):
    """Scale the right side so soldermask near the seam matches the left."""
    import numpy as np
    import cv2

    if img is None or getattr(img, "size", 0) == 0:
        return img, ""
    h, w = img.shape[:2]
    if w < 400 or h < 80:
        return img, ""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img
    y0, y1 = int(h * 0.22), int(h * 0.78)
    left = gray[y0:y1, int(w * 0.40):int(w * 0.47)].astype(np.float32).ravel()
    right = gray[y0:y1, int(w * 0.53):int(w * 0.60)].astype(np.float32).ravel()
    if left.size < 80 or right.size < 80:
        return img, ""

    def ink(flat):
        cut = np.percentile(flat, 45)
        dark = flat[flat <= cut]
        return float(np.median(dark if dark.size else flat))

    lo, ro = ink(left), ink(right)
    if lo < 6 or ro < 6:
        return img, ""
    scale = lo / ro
    if not (0.55 <= scale <= 1.70) or abs(scale - 1) < 0.02:
        return img, ""
    seam = int(w * 0.50)
    ramp = max(40, w // 80)
    xs = np.arange(w, dtype=np.float32)
    t = np.clip((xs - (seam - ramp)) / (2.0 * ramp), 0.0, 1.0)
    gain = 1.0 + (scale - 1.0) * t
    out = img.astype(np.float32)
    if out.ndim == 3:
        out *= gain[None, :, None]
    else:
        out *= gain[None, :]
    np.clip(out, 0, 255, out)
    return out.astype(np.uint8), f"balance seam ×{scale:.2f}"


def _compose_geometry(w, h, overlap, dy):
    overlap = float(overlap)
    if overlap < 0.05 or overlap > 0.50:
        raise dual.CamError("overlap 0.05–0.50")
    dy = int(dy)
    ol = max(1, min(w - 1, int(round(w * overlap))))
    x = w - ol
    out_w = w + w - ol
    ty = max(0, -dy)
    ry = max(0, dy)
    out_h = h + abs(dy)
    return ol, x, out_w, out_h, ty, ry


def _overlap_strip_rows(h, ty, ry):
    """Row origin and height for R-east / T-west overlap strips when frames are offset."""
    y0 = max(ty, ry)
    r_y = y0 - ry
    t_y = y0 - ty
    strip_h = h - abs(ty - ry)
    if strip_h < 8:
        return 0, 0, h
    return r_y, t_y, strip_h


def _crop_overlap_strips(r_path, t_path, dest_r, dest_t, w, h, ol, x, ty, ry):
    r_y, t_y, strip_h = _overlap_strip_rows(h, ty, ry)
    for src, dest, crop in (
        (r_path, dest_r, f"{ol}x{strip_h}+{x}+{r_y}"),
        (t_path, dest_t, f"{ol}x{strip_h}+0+{t_y}"),
    ):
        _magick([str(src), "-crop", crop, "+repage", str(dest)])
    return strip_h


def _prep_compose_sources(
    t_path, r_path, tmp, overlap, flip_r, dy=0, balance=True, lift=True, on_log=None,
):
    def log(msg):
        if on_log:
            on_log(msg)

    w, h = _size(t_path)
    rw, rh = _size(r_path)
    ol, x, out_w, out_h, ty, ry = _compose_geometry(w, h, overlap, dy)
    tmp = Path(tmp)
    r_use = tmp / "r.jpg"
    t_use = tmp / "t.jpg"
    args = [str(r_path), "-colorspace", "sRGB"]
    if flip_r:
        args += ["-flop"]
    if (rw, rh) != (w, h):
        args += ["-resize", f"{w}x{h}!"]
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=2) as pool:
        fr = pool.submit(_magick, args + [str(r_use)])
        ft = pool.submit(_magick, [str(t_path), "-colorspace", "sRGB", str(t_use)])
        fr.result()
        ft.result()
    if balance:
        r_use = _balance_r(t_use, r_use, tmp / "r_bal.jpg", overlap, on_log=log)
    if lift:
        t_use = _lift_unique(t_use, tmp / "t_lift.jpg", east=True, overlap=overlap, on_log=log)
        r_use = _lift_unique(r_use, tmp / "r_lift.jpg", east=False, overlap=overlap, on_log=log)
    return t_use, r_use, w, h, ol, x, out_w, out_h, ty, ry, int(dy)


def hugin_available():
    return bool(shutil.which(MAGICK))


def _load_hugin_profiles():
    if not HUGIN_PROFILE.is_file():
        return {}
    try:
        data = json.loads(HUGIN_PROFILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def hugin_profile(w, h, profile="fxpan65"):
    data = _load_hugin_profiles()
    base = dict(data.get(profile) or {})
    sensors = base.pop("sensors", {})
    if isinstance(sensors, dict):
        row = sensors.get(f"{w}x{h}")
        if isinstance(row, dict):
            base.update(row)
    base.setdefault("profile", profile)
    base.setdefault("flip_r", True)
    base.setdefault("overlap", OVERLAP)
    base.setdefault("dy", 0)
    base.setdefault("hfov", 50.0)
    return base


def _blend_overlap_strips(rol, tol, dest, ol, strip_h):
    """Feather-blend two same-size overlap strips (row-aligned)."""
    dest = Path(dest)
    if ol <= 1:
        _magick(["-size", f"{ol}x{strip_h}", "xc:#808080", str(dest)])
        return
    mask = dest.parent / "mask.png"
    _magick([
        "-size", f"{ol}x{strip_h}", "xc:",
        "-sparse-color", "barycentric",
        f"0,0 black {ol - 1},0 white",
        str(mask),
    ])
    _magick([str(rol), str(tol), str(mask), "-compose", "over", "-composite", str(dest)])


def _compose_overlap_blend(r_path, t_path, dest, w, h, ol, x, ty, ry):
    """Blend the overlap band; strips are row-aligned for dy."""
    tmp = Path(dest).parent
    rol = tmp / "rol.png"
    tol = tmp / "tol.png"
    strip_h = _crop_overlap_strips(r_path, t_path, rol, tol, w, h, ol, x, ty, ry)
    _blend_overlap_strips(rol, tol, dest, ol, strip_h)


def _overlap_canvas_y(ty, ry):
    return max(ty, ry)


def _compose_pano(dest, r_path, t_path, ol_path, out_w, out_h, x, ty, ry):
    """Place R, T, and the overlap blend on the output canvas."""
    oy = _overlap_canvas_y(ty, ry)
    _magick([
        "-size", f"{out_w}x{out_h}",
        "xc:black",
        str(r_path), "-geometry", f"+0+{ry}", "-composite",
        str(t_path), "-geometry", f"+{x}+{ty}", "-composite",
        str(ol_path), "-geometry", f"+{x}+{oy}", "-composite",
        "-quality", "92",
        str(dest),
    ])


def stitch_hugin(
    t_path, r_path, dest, overlap=OVERLAP, flip_r=True, dy=0, on_log=None,
    balance=False, lift=True, profile="fxpan65", crop_inner=True, images=None,
):
    """images=(t_bgr, r_bgr) skips the JPEG read (16-bit RAW develop)."""
    def log(msg):
        if on_log:
            on_log(msg)

    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        import cv2
        cv2.setNumThreads(_cpu_count())
    except ImportError:
        cv2 = None
    found = None
    t_bgr = r_bgr = None
    if cv2 is not None:
        if images is not None:
            t_bgr, r_bgr = images.pop("t"), images.pop("r")
        else:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=2) as pool:
                ft = pool.submit(_imread_bgr, t_path)
                fr = pool.submit(_imread_bgr, r_path)
                t_bgr, r_bgr = ft.result(), fr.result()
        h, w = t_bgr.shape[:2]
        prof = hugin_profile(w, h, profile=profile)
        if flip_r is False and prof.get("flip_r"):
            flip_r = True
        if flip_r:
            r_bgr = cv2.flip(r_bgr, 1)
        rh, rw = r_bgr.shape[:2]
        if (rh, rw) != (h, w):
            r_bgr = cv2.resize(r_bgr, (w, h), interpolation=cv2.INTER_AREA)
        if balance and images is not None:
            t_bgr, r_bgr, msg = _balance_linear(t_bgr, r_bgr, overlap)
            if msg:
                log(msg)
        elif balance:
            r_bgr, msg = _balance_r_bgr(t_bgr, r_bgr, overlap)
            if msg:
                log(msg)
        tmask, rmask, band = _overlap_feature_masks(w, h, overlap)
        log(f"hugin  SIFT similarity in {band}px overlap")
        if images is not None:
            found = _sift_similarity(
                _raw_view_u8(r_bgr, images["gain"]), _raw_view_u8(t_bgr, images["gain"]),
                rmask, tmask,
            )
        else:
            found = _sift_similarity(r_bgr, t_bgr, rmask, tmask)
        if not found and images is not None:
            # The feather fallback reads the JPEG files; stay on the 16-bit frames.
            log("hugin  SIFT missed — profile overlap, no rotation")
            found = _profile_similarity(w, overlap, dy)
        if found:
            log(
                f"hugin  rot={found['rot']:+.2f}° scale={found['scale']:.4f} "
                f"ol={found['overlap']:.0%} n={found['n']}  flip={'on' if flip_r else 'off'}"
            )
            Mr, Mt, cw, ch = _affine_canvas(found["M"], w, h)
            r_rgba = _warp_bgr(r_bgr, Mr, cw, ch)
            t_rgba = _warp_bgr(t_bgr, Mt, cw, ch)
            if crop_inner:
                x0, y0, x1, y1 = _inner_crop_box(r_rgba, t_rgba)
                r_rgba = r_rgba[y0:y1, x0:x1]
                t_rgba = t_rgba[y0:y1, x0:x1]
                log(f"hugin  clip inner  {x1 - x0}×{y1 - y0}")
            log("hugin  overlap + multiband")
            extra = {}
            if images is not None:
                t_bgr = r_bgr = None
                lin = _multiband_blend(r_rgba, t_rgba)
                del r_rgba, t_rgba
                oh, ow = lin.shape[:2]
                master = images.get("master")
                if master:
                    log(f"raw  16-bit master  {Path(master).name}")
                    write_master_tiff(master, lin)
                    extra["master"] = Path(master).name
                write_raw_display(dest, lin, images["gain"], images.get("look", True))
                extra["source"] = "raw"
                extra["look"] = "nikon" if images.get("look", True) else "neutral"
                del lin
            else:
                ow, oh = _multiband_write(r_rgba, t_rgba, dest)
            return {
                **extra,
                "file": dest.name,
                "width": ow,
                "height": oh,
                "overlap": int(round(w * found["overlap"])),
                "overlap_frac": found["overlap"],
                "dy": int(round(found["ty"])),
                "rot": round(found["rot"], 3),
                "scale": round(found["scale"], 5),
                "inliers": found["n"],
                "flip_r": bool(flip_r),
                "mode": "hugin",
                "engine": "multiband",
                "crop_inner": bool(crop_inner),
                "profile": prof.get("profile", profile),
            }
        log("hugin  SIFT missed — feather")
    w, h = (t_bgr.shape[1], t_bgr.shape[0]) if t_bgr is not None else _size(t_path)
    prof = hugin_profile(w, h, profile=profile)
    if flip_r is False and prof.get("flip_r"):
        flip_r = True
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        t_use, r_use, w, h, ol, x, out_w, out_h, ty, ry, eff_dy = _prep_compose_sources(
            t_path, r_path, tmp, overlap, flip_r, dy=dy,
            balance=balance, lift=False, on_log=on_log,
        )
        log(
            f"hugin mosaic  ol={ol}px ({overlap:.0%}) dy={eff_dy:+d} "
            f"flip={'on' if flip_r else 'off'}  {out_w}×{out_h}"
        )
        ol_blend = tmp / "ol.png"
        _compose_overlap_blend(r_use, t_use, ol_blend, w, h, ol, x, ty, ry)
        _compose_pano(dest, r_use, t_use, ol_blend, out_w, out_h, x, ty, ry)
    ow, oh = _size(dest)
    return {
        "file": dest.name,
        "width": ow,
        "height": oh,
        "overlap": ol,
        "overlap_frac": overlap,
        "dy": eff_dy,
        "flip_r": bool(flip_r),
        "mode": "hugin",
        "engine": "feather",
        "profile": prof.get("profile", profile),
    }


def stitch_files(
    t_path, r_path, dest, overlap=OVERLAP, flip_r=False, mode="blend", dy=0, on_log=None,
    balance=True,
):
    def log(msg):
        if on_log:
            on_log(msg)

    mode = (mode or "blend").strip().lower()
    if mode not in ("blend", "cut"):
        raise dual.CamError("mode is blend or cut")
    overlap = float(overlap)
    dy = int(dy)
    w, h = _size(t_path)
    ol, x, out_w, out_h, ty, ry = _compose_geometry(w, h, overlap, dy)
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    log(f"compose {mode}  ol={ol}px ({overlap:.0%}) dy={dy:+d} flip={'on' if flip_r else 'off'}")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        t_use, r_use, w, h, ol, x, out_w, out_h, ty, ry, _dy = _prep_compose_sources(
            t_path, r_path, tmp, overlap, flip_r, dy=dy, balance=balance, on_log=log,
        )
        rol = tmp / "rol.png"
        tol = tmp / "tol.png"
        strip_h = _crop_overlap_strips(r_use, t_use, rol, tol, w, h, ol, x, ty, ry)
        oy = _overlap_canvas_y(ty, ry)
        if mode == "cut":
            keep = w - ol + ol // 2
            take = w - (ol - ol // 2)
            _magick(
                [str(r_use), "-crop", f"{keep}x{h}+0+0", "+repage", str(tmp / "rcut.png")]
            )
            _magick(
                [
                    str(t_use),
                    "-crop",
                    f"{take}x{h}+{ol - ol // 2}+0",
                    "+repage",
                    str(tmp / "tcut.png"),
                ]
            )
            _magick(
                [
                    "-size",
                    f"{out_w}x{out_h}",
                    "xc:black",
                    str(tmp / "rcut.png"),
                    "-geometry",
                    f"+0+{ry}",
                    "-composite",
                    str(tmp / "tcut.png"),
                    "-geometry",
                    f"+{keep}+{ty}",
                    "-composite",
                    "-quality",
                    "92",
                    str(dest),
                ]
            )
        else:
            _blend_overlap_strips(rol, tol, tmp / "ol.png", ol, strip_h)
            _magick(
                [
                    "-size",
                    f"{out_w}x{out_h}",
                    "xc:black",
                    str(r_use),
                    "-geometry",
                    f"+0+{ry}",
                    "-composite",
                    str(t_use),
                    "-geometry",
                    f"+{x}+{ty}",
                    "-composite",
                    str(tmp / "ol.png"),
                    "-geometry",
                    f"+{x}+{oy}",
                    "-composite",
                    "-quality",
                    "92",
                    str(dest),
                ]
            )
    ow, oh = _size(dest)
    return {
        "file": dest.name,
        "width": ow,
        "height": oh,
        "overlap": ol,
        "overlap_frac": overlap,
        "dy": dy,
        "flip_r": bool(flip_r),
        "mode": mode,
    }


def stamp_day(stamp):
    m = DAY_RE.match(stamp or "")
    return m.group(1) if m else ""


def _unlink_named(root, name):
    n = 0
    path = Path(root) / name
    if path.is_file():
        path.unlink()
        n += 1
    if name[:2].upper() == "P_" and Path(name).suffix.lower() in (".jpg", ".jpeg"):
        side = Path(root) / (Path(name).stem + ".json")
        if side.is_file():
            side.unlink()
            n += 1
    thumbs = Path(root) / ".thumbs"
    if thumbs.is_dir():
        for thumb in thumbs.iterdir():
            if thumb.is_file() and thumb.name.endswith("_" + name):
                thumb.unlink()
                n += 1
    return n


def delete_stamp(stamp, root=None, sides=None):
    if not stamp or "/" in stamp or ".." in stamp:
        raise dual.CamError("bad stamp")
    root = Path(root or CAPTURES)
    if stamp in protected_set(root):
        raise dual.CamError("protected  unlock first")
    want = {s.upper() for s in sides} if sides else {"T", "R", "P"}
    if not want.issubset({"T", "R", "P"}):
        raise dual.CamError("side is T, R, or P")
    names = []
    for row in list_pairs(root):
        if row["stamp"] != stamp:
            continue
        def add(name):
            if name and name not in names:
                names.append(name)
        if "T" in want:
            add(row.get("t"))
            add(row.get("t_nef"))
        if "R" in want:
            add(row.get("r"))
            add(row.get("r_nef"))
        if "P" in want:
            add(row.get("pano"))
            add(row.get("pano_ana"))
            add(row.get("master"))
        break
    else:
        raise dual.CamError("missing pair")
    count = 0
    for name in names:
        count += _unlink_named(root, name)
    left = root.is_dir() and any(_stamp_of(path.name) == stamp for path in root.iterdir())
    if not left:
        extra = _exif_cache_path(root, stamp)
        if extra.is_file():
            extra.unlink()
            count += 1
        _prune_protected(root, stamp)
    return {"stamp": stamp, "removed": names, "count": count}


def delete_before_today(root=None, today=None):
    today = today or date.today().strftime("%Y%m%d")
    removed = []
    skipped = []
    for row in list_pairs(root):
        day = stamp_day(row["stamp"])
        if not day or day >= today:
            continue
        if row.get("protected"):
            skipped.append(row["stamp"])
            continue
        delete_stamp(row["stamp"], root)
        removed.append(row["stamp"])
    return {"today": today, "removed": removed, "skipped": skipped, "count": len(removed)}


def keep_last(n=5, root=None):
    try:
        n = int(n)
    except (TypeError, ValueError) as exc:
        raise dual.CamError("keep 1–99") from exc
    if n < 1 or n > 99:
        raise dual.CamError("keep 1–99")
    rows = sorted(
        list_pairs(root),
        key=lambda row: (1 if stamp_day(row["stamp"]) else 0, row["stamp"]),
        reverse=True,
    )
    unlocked = [row for row in rows if not row.get("protected")]
    keep = unlocked[:n]
    drop = unlocked[n:]
    removed = []
    for row in drop:
        delete_stamp(row["stamp"], root)
        removed.append(row["stamp"])
    kept = [row["stamp"] for row in keep] + [
        row["stamp"] for row in rows if row.get("protected")
    ]
    return {"kept": kept, "removed": removed, "count": len(removed)}


def delete_unprotected(root=None):
    removed = []
    skipped = []
    for row in list_pairs(root):
        if row.get("protected"):
            skipped.append(row["stamp"])
            continue
        delete_stamp(row["stamp"], root)
        removed.append(row["stamp"])
    return {"removed": removed, "skipped": skipped, "count": len(removed)}


def subtract_ghost(src, dest, dx, dy, gain):
    """Subtract a shifted copy: dest ≈ src − gain · roll(src, dx, dy)."""
    dx, dy = int(dx), int(dy)
    gain = float(gain)
    src, dest = Path(src), Path(dest)
    if (dx == 0 and dy == 0) or gain <= 0:
        if src.resolve() != dest.resolve():
            dest.write_bytes(src.read_bytes())
        return
    _magick([
        str(src),
        "(", str(src), "-roll", f"{dx:+d}{dy:+d}",
        "-evaluate", "multiply", f"{gain:.4f}", ")",
        "-compose", "Minus_Src", "-composite",
        str(dest),
    ])


def estimate_plate_ghost(path, tag="R"):
    """S2 ghost ≈ gain × shifted copy. None if the copy is too weak to trust.

    R sees the uncoated-S2 bounce more strongly. T still gets a weaker internal
    reflection; search a lower gain floor for that path.
    """
    _venv_site()
    try:
        import cv2
        import numpy as np
    except ImportError:
        return None
    gray = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if gray is None:
        return None
    h, w = gray.shape
    scale = 4 if min(h, w) >= 400 else 1
    small = cv2.resize(
        gray.astype(np.float32), (w // scale, h // scale),
        interpolation=cv2.INTER_AREA,
    )
    hp = small - cv2.GaussianBlur(small, (0, 0), 5)
    pad = 16 if min(hp.shape) > 48 else 4
    inner = hp[pad:-pad, pad:-pad]
    best = None
    dy_hi = 4 if scale > 1 else 6
    if str(tag).upper() == "T":
        gain_lo, gain_hi = 0.012, 0.10
        dx_hi = 18 if scale > 1 else 64
        dx_lo = 2 if scale > 1 else 6
    else:
        gain_lo, gain_hi = 0.03, 0.10
        dx_hi = 14 if scale > 1 else 50
        dx_lo = 3 if scale > 1 else 8
    for dy in range(-dy_hi, dy_hi + 1):
        for dx in list(range(-dx_hi, -dx_lo)) + list(range(dx_lo, dx_hi + 1)):
            rolled = np.roll(np.roll(small, dy, 0), dx, 1)
            base = small[pad:-pad, pad:-pad]
            shb = rolled[pad:-pad, pad:-pad]
            gain = float(np.dot(base.ravel(), shb.ravel())) / (
                float(np.dot(shb.ravel(), shb.ravel())) + 1e-6
            )
            if not (gain_lo <= gain <= gain_hi):
                continue
            if best is None or gain > best[0]:
                best = (gain, dx, dy)
    if not best:
        return None
    gain, dx_s, dy_s = best
    sh2 = np.roll(np.roll(hp, 2 * dy_s, 0), 2 * dx_s, 1)[pad:-pad, pad:-pad]
    den2 = float(np.dot(sh2.ravel(), sh2.ravel())) + 1e-6
    gain2 = float(np.dot(inner.ravel(), sh2.ravel())) / den2
    sh1 = np.roll(np.roll(hp, dy_s, 0), dx_s, 1)[pad:-pad, pad:-pad]
    den1 = float(np.dot(sh1.ravel(), sh1.ravel())) + 1e-6
    g_hp = float(np.dot(inner.ravel(), sh1.ravel())) / den1
    if g_hp > 0 and gain2 > 0.45 * g_hp:
        return None
    return {
        "dx": int(dx_s * scale), "dy": int(dy_s * scale),
        "gain": round(float(gain), 4),
    }


def _deghost_path(path, tmp, tag, on_log=None):
    info = estimate_plate_ghost(path, tag=tag)
    if not info:
        return path, None
    dest = Path(tmp) / f"{tag}.jpg"
    subtract_ghost(path, dest, info["dx"], info["dy"], info["gain"])
    if on_log:
        on_log(
            f"deghost {tag}  dx={info['dx']:+d} dy={info['dy']:+d} "
            f"gain={info['gain']:.3f}"
        )
    return dest, info


def _overlap_feature_masks(w, h, overlap, tmp=None):
    import numpy as np

    band = max(int(w * overlap * 1.5), int(w * 0.22))
    band = min(band, w // 2)
    tmask = np.zeros((h, w), np.uint8)
    tmask[:, :band] = 255
    rmask = np.zeros((h, w), np.uint8)
    rmask[:, w - band :] = 255
    return tmask, rmask, band


def _sift_overlap_shift(left_path, right_path, left_mask, right_mask):
    """Translation (dx, dy) mapping right-image pts onto left-image pts.

    Hybrid: left is flopped R, right is T. Overlap is left-east / right-west.
    dx ≈ width − overlap_px. stitch_files dy is −dy (R up when features sit
    lower in R than in T).
    """
    import cv2
    import numpy as np

    left = _cv_u8(left_path)
    right = _cv_u8(right_path)
    ml = _cv_u8(left_mask)
    mr = _cv_u8(right_mask)
    if left is None or right is None or ml is None or mr is None:
        return None
    orig_w = left.shape[1]
    h, w = left.shape
    work = 1600
    scale = 1.0
    if w > work:
        scale = work / float(w)
        nw, nh = int(round(w * scale)), int(round(h * scale))
        left = cv2.resize(left, (nw, nh), interpolation=cv2.INTER_AREA)
        right = cv2.resize(right, (nw, nh), interpolation=cv2.INTER_AREA)
        ml = cv2.resize(ml, (nw, nh), interpolation=cv2.INTER_NEAREST)
        mr = cv2.resize(mr, (nw, nh), interpolation=cv2.INTER_NEAREST)
    sift = cv2.SIFT_create(nfeatures=4000)
    k1, d1 = sift.detectAndCompute(left, ml)
    k2, d2 = sift.detectAndCompute(right, mr)
    if d1 is None or d2 is None or len(k1) < 8 or len(k2) < 8:
        return None
    raw = cv2.BFMatcher(cv2.NORM_L2).knnMatch(d1, d2, k=2)
    dxs, dys = [], []
    for pair in raw:
        if len(pair) < 2:
            continue
        m, n = pair
        if m.distance >= 0.75 * n.distance:
            continue
        x1, y1 = k1[m.queryIdx].pt
        x2, y2 = k2[m.trainIdx].pt
        dxs.append(x1 - x2)
        dys.append(y1 - y2)
    if len(dxs) < 12:
        return None
    dxs = np.asarray(dxs, np.float64)
    dys = np.asarray(dys, np.float64)
    dx0, dy0 = float(np.median(dxs)), float(np.median(dys))
    ok = (np.abs(dxs - dx0) < 8) & (np.abs(dys - dy0) < 8)
    if int(ok.sum()) < 8:
        return None
    dx = float(np.median(dxs[ok])) / scale
    dy = float(np.median(dys[ok])) / scale
    ol = orig_w - dx
    frac = ol / orig_w
    if frac < 0.05 or frac > 0.50:
        return None
    return {
        "overlap": frac,
        "dy": int(round(-dy)),
        "n": int(ok.sum()),
    }


def _similarity_params(M):
    a, b = float(M[0][0]), float(M[0][1])
    scale = (a * a + b * b) ** 0.5
    rot = float(math.degrees(math.atan2(b, a)))
    return scale, rot, float(M[0][2]), float(M[1][2])


def _similarity_sane(M, w, h):
    if M is None:
        return False
    try:
        scale, rot, tx, ty = _similarity_params(M)
    except (TypeError, IndexError, ValueError):
        return False
    if not (0.94 <= scale <= 1.06):
        return False
    if abs(rot) > 8.0:
        return False
    if not (0.40 * w <= tx <= 0.95 * w):
        return False
    if abs(ty) > 0.20 * h:
        return False
    return True


def _sift_similarity(left_path, right_path, left_mask, right_mask, work=2400):
    """Similarity (scale+rot+trans) mapping right/T pixels onto left/R pixels."""
    import cv2
    import numpy as np

    left = _cv_u8(left_path)
    right = _cv_u8(right_path)
    ml = _cv_u8(left_mask)
    mr = _cv_u8(right_mask)
    if left is None or right is None or ml is None or mr is None:
        return None
    orig_w, orig_h = left.shape[1], left.shape[0]
    h, w = left.shape
    scale = 1.0
    if w > work:
        scale = work / float(w)
        nw, nh = int(round(w * scale)), int(round(h * scale))
        left = cv2.resize(left, (nw, nh), interpolation=cv2.INTER_AREA)
        right = cv2.resize(right, (nw, nh), interpolation=cv2.INTER_AREA)
        ml = cv2.resize(ml, (nw, nh), interpolation=cv2.INTER_NEAREST)
        mr = cv2.resize(mr, (nw, nh), interpolation=cv2.INTER_NEAREST)
    sift = cv2.SIFT_create(nfeatures=6000, contrastThreshold=0.02)
    k1, d1 = sift.detectAndCompute(left, ml)
    k2, d2 = sift.detectAndCompute(right, mr)
    if d1 is None or d2 is None or len(k1) < 8 or len(k2) < 8:
        return None
    raw = cv2.BFMatcher(cv2.NORM_L2).knnMatch(d1, d2, k=2)
    pts1, pts2 = [], []
    for pair in raw:
        if len(pair) < 2:
            continue
        m, n = pair
        if m.distance >= 0.80 * n.distance:
            continue
        pts1.append(k1[m.queryIdx].pt)
        pts2.append(k2[m.trainIdx].pt)
    if len(pts1) < 8:
        return None
    pts1 = np.float32(pts1)
    pts2 = np.float32(pts2)
    M, inl = cv2.estimateAffinePartial2D(
        pts2, pts1, method=cv2.RANSAC, ransacReprojThreshold=4.0,
    )
    if M is None or inl is None:
        return None
    n = int(inl.sum())
    if n < 6:
        return None
    M = M.astype(np.float64)
    M[0, 2] /= scale
    M[1, 2] /= scale
    if not _similarity_sane(M, orig_w, orig_h):
        return None
    sc, rot, tx, ty = _similarity_params(M)
    ol = orig_w - tx
    frac = ol / orig_w
    if frac < 0.05 or frac > 0.50:
        return None
    return {
        "M": M,
        "overlap": frac,
        "rot": rot,
        "scale": sc,
        "tx": tx,
        "ty": ty,
        "n": n,
    }


def _profile_similarity(w, overlap, dy=0):
    """Plain shift from the designed overlap, in _sift_similarity's shape."""
    import numpy as np

    tx = w * (1.0 - float(overlap))
    M = np.array([[1.0, 0.0, tx], [0.0, 1.0, float(dy)]], np.float64)
    return {"M": M, "overlap": float(overlap), "rot": 0.0, "scale": 1.0,
            "tx": tx, "ty": float(dy), "n": 0}


def _affine_canvas(M, w, h):
    import cv2
    import numpy as np

    r_corners = np.float32([[0, 0], [w, 0], [w, h], [0, h]]).reshape(-1, 1, 2)
    t_corners = cv2.transform(r_corners, M)
    pts = np.vstack([r_corners.reshape(-1, 2), t_corners.reshape(-1, 2)])
    minx, miny = np.floor(pts.min(axis=0)).astype(int)
    maxx, maxy = np.ceil(pts.max(axis=0)).astype(int)
    off = np.array([[1.0, 0.0, float(-minx)], [0.0, 1.0, float(-miny)]], np.float64)
    M3 = np.vstack([M, [0.0, 0.0, 1.0]])
    off3 = np.vstack([off, [0.0, 0.0, 1.0]])
    Mt = (off3 @ M3)[:2]
    return off, Mt, int(maxx - minx), int(maxy - miny)


def _inner_crop_box(r_rgba, t_rgba):
    """Crop top/bottom to a straight edge; keep the full mosaic width."""
    import numpy as np

    a = np.maximum(r_rgba[:, :, 3], t_rgba[:, :, 3])
    h, w = a.shape
    opaque = a > 32
    col_n = opaque.sum(axis=0)
    has_c = col_n > 0
    if not has_c.any():
        return 0, 0, w, h
    tops = np.where(has_c, np.argmax(opaque, axis=0), 0)
    bots = np.where(has_c, h - 1 - np.argmax(opaque[::-1], axis=0), h - 1)
    ch = np.where(has_c, bots - tops + 1, 0)
    med_h = float(np.median(ch[has_c]))
    good_c = has_c & (ch >= 0.90 * med_h)
    if not good_c.any():
        return 0, 0, w, h
    x0 = int(np.argmax(has_c))
    x1 = int(w - np.argmax(has_c[::-1]))
    y0 = int(tops[good_c].max())
    y1 = int(bots[good_c].min()) + 1
    if x1 <= x0 or y1 <= y0:
        return 0, 0, w, h
    return x0, y0, x1, y1


def _imread_bgr(path):
    import cv2

    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise dual.CamError(f"cannot read {path}")
    return img


def _cv_u8(src):
    import cv2
    import numpy as np

    if src is None:
        return None
    if isinstance(src, (str, Path)):
        return cv2.imread(str(src), cv2.IMREAD_GRAYSCALE)
    img = src.get() if hasattr(src, "get") else src
    img = np.asarray(img)
    if img.dtype == np.uint16:
        img = (img >> 8).astype(np.uint8)
    if img.ndim == 3:
        code = cv2.COLOR_BGRA2GRAY if img.shape[2] == 4 else cv2.COLOR_BGR2GRAY
        return cv2.cvtColor(img, code)
    return img


def _balance_r_bgr(t, r, overlap):
    import numpy as np

    h, w = t.shape[:2]
    top = 65535 if r.dtype == np.uint16 else 255
    ol = max(1, min(w - 1, int(round(w * float(overlap)))))
    t_m = float(t[:, :ol].mean())
    r_m = float(r[:, w - ol:].mean())
    if r_m <= 5.0 * top / 255 or t_m <= 5.0 * top / 255:
        return r, ""
    scale = t_m / r_m
    if abs(scale - 1) <= 0.03:
        return r, ""
    if not (0.40 <= scale <= 2.50):
        return r, f"balance skip R ×{scale:.2f} (overlap too different)"
    out = np.clip(r.astype(np.float32) * scale, 0, top).astype(r.dtype)
    return out, f"balance R ×{scale:.2f} (overlap)"


def _balance_linear(t, r, overlap):
    """Match the bodies on linear 16-bit by scaling the brighter one down.

    Scaling up would clip the sensor's top levels out of the master.
    """
    import cv2

    h, w = t.shape[:2]
    ol = max(1, min(w - 1, int(round(w * float(overlap)))))
    t_m = float(t[:, :ol].mean())
    r_m = float(r[:, w - ol:].mean())
    if r_m < 16 or t_m < 16:
        return t, r, ""
    scale = t_m / r_m
    if abs(scale - 1) <= 0.03:
        return t, r, ""
    if not (0.40 <= scale <= 2.50):
        return t, r, f"balance skip ×{scale:.2f} (overlap too different)"
    if scale < 1:
        return t, cv2.multiply(r, (scale, scale, scale, 0)), f"balance R ×{scale:.2f} (overlap)"
    inv = 1.0 / scale
    return cv2.multiply(t, (inv, inv, inv, 0)), r, f"balance T ×{inv:.2f} (overlap)"


def _warp_bgr(img, M, out_w, out_h):
    import cv2
    import numpy as np

    rgba = cv2.cvtColor(img, cv2.COLOR_BGR2BGRA)
    return cv2.warpAffine(
        rgba, M.astype(np.float32), (out_w, out_h),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0, 0),
    )


def _overlap_blend_masks(r_a, t_a, dilate=96):
    """Voronoi seam in the overlap, then widen so multiband can hide it."""
    import cv2
    import numpy as np

    r_m = (r_a > 32).astype(np.uint8)
    t_m = (t_a > 32).astype(np.uint8)
    only_r = r_m & (1 - t_m)
    only_t = t_m & (1 - r_m)
    both = r_m & t_m
    h, w = r_m.shape
    if int(only_r.sum()) >= 8 and int(only_t.sum()) >= 8:
        dr = cv2.distanceTransform(
            ((1 - only_r) * 255).astype(np.uint8), cv2.DIST_L2, 5,
        )
        dt = cv2.distanceTransform(
            ((1 - only_t) * 255).astype(np.uint8), cv2.DIST_L2, 5,
        )
        prefer_r = dr <= dt
    else:
        xs = np.broadcast_to(np.arange(w, dtype=np.float32), (h, w))
        prefer_r = xs < (w * 0.5)
    rm = np.where(only_r | (both & prefer_r), 255, 0).astype(np.uint8)
    tm = np.where(only_t | (both & ~prefer_r), 255, 0).astype(np.uint8)
    rad = max(8, int(dilate))
    k = np.ones((1, 2 * rad + 1), np.uint8)
    rm = cv2.dilate(rm, k)
    tm = cv2.dilate(tm, k)
    rm = np.minimum(rm, r_m * 255)
    tm = np.minimum(tm, t_m * 255)
    return rm, tm


def _write_jpeg(path, bgr, quality=92):
    import cv2

    path = Path(path)
    if bgr.dtype != "uint8":
        bgr = (bgr >> 8).astype("uint8")
    ok = cv2.imwrite(str(path), bgr, [int(cv2.IMWRITE_JPEG_QUALITY), int(quality)])
    if not ok:
        raise dual.CamError(f"cannot write {path}")


def _multiband_write(r_rgba, t_rgba, dest):
    dst = _multiband_blend(r_rgba, t_rgba)
    _write_jpeg(dest, dst)
    return dst.shape[1], dst.shape[0]


def _multiband_blend(r_rgba, t_rgba):
    import cv2
    import numpy as np

    r_bgr, t_bgr = r_rgba[:, :, :3], t_rgba[:, :, :3]
    rm, tm = _overlap_blend_masks(r_rgba[:, :, 3], t_rgba[:, :, 3])
    h, w = r_bgr.shape[:2]
    blender = cv2.detail.MultiBandBlender()
    blender.setNumBands(5)
    blender.prepare((0, 0, w, h))
    # The blender works in int16 and its pyramid overshoots at hard edges;
    # 16-bit input keeps 14 bits so a near-white edge cannot wrap negative.
    deep = r_bgr.dtype == np.uint16
    shift = 2
    if deep:
        blender.feed(np.right_shift(r_bgr, shift).view(np.int16), rm, (0, 0))
        blender.feed(np.right_shift(t_bgr, shift).view(np.int16), tm, (0, 0))
    else:
        blender.feed(r_bgr.astype(np.int16), rm, (0, 0))
        blender.feed(t_bgr.astype(np.int16), tm, (0, 0))
    dst, dm = blender.blend(None, None)
    if deep:
        dst = np.clip(np.asarray(dst, np.int32) << shift, 0, 65535).astype(np.uint16)
    else:
        dst = np.clip(dst, 0, 255).astype(np.uint8)
    if dm is not None:
        dst[np.asarray(dm) == 0] = 0
    return dst


def stitch_open(t_path, r_path, dest, flip_r=False, try_both=True, on_log=None,
                balance=True, overlap=OVERLAP):
    """SIFT in the hybrid overlap, then a translation blend (no affine shear)."""
    def log(msg):
        if on_log:
            on_log(msg)

    log("OpenStitching  loading…")
    _venv_site()
    try:
        import cv2  # noqa: F401
    except ImportError as exc:
        raise dual.CamError(
            "OpenCV missing.  cd cam && python3 -m venv .venv && "
            ".venv/bin/pip install -r requirements.txt"
        ) from exc

    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    flips = [True] if flip_r else [False]
    if try_both and not flip_r:
        flips.append(True)
    last = None
    tw, th = _size(t_path)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        tmask, rmask, band = _overlap_feature_masks(tw, th, overlap, tmp)
        log(f"OpenStitching  SIFT only in R-right / T-left {band}px (hybrid overlap)")
        for flop in flips:
            r_use = Path(r_path)
            if flop:
                r_use = tmp / "r.jpg"
                args = [str(r_path), "-flop"]
                rw, rh = _size(r_path)
                if (rw, rh) != (tw, th):
                    args += ["-resize", f"{tw}x{th}!"]
                _magick(args + [str(r_use)])
                log("OpenStitching  R flopped")
            else:
                log("OpenStitching  R as-shot")
                rw, rh = _size(r_use)
                if (rw, rh) != (tw, th):
                    sized = tmp / "r.jpg"
                    _magick([str(r_use), "-resize", f"{tw}x{th}!", str(sized)])
                    r_use = sized
            log("OpenStitching  SIFT translation")
            try:
                found = _sift_overlap_shift(r_use, t_path, rmask, tmask)
                if not found:
                    raise dual.CamError("not enough overlap SIFT matches")
                log(
                    f"OpenStitching  ol={found['overlap']:.0%} dy={found['dy']:+d} "
                    f"n={found['n']}  flip={'on' if flop else 'off'}"
                )
                info = stitch_files(
                    t_path, r_path, dest,
                    overlap=found["overlap"], flip_r=flop, mode="blend",
                    dy=found["dy"], on_log=on_log, balance=balance,
                )
                info["flip_r"] = flop
                info["mode"] = "open"
                info["engine"] = "sift"
                return info
            except Exception as exc:
                last = exc
                log(f"sift failed: {exc}")
    raise dual.CamError(str(last) if last else "OpenStitching failed")


def stitch_stamp(
    stamp, overlap=OVERLAP, flip_r=False, mode="blend", dy=0, root=None, on_log=None,
    deghost=False, balance=True, crop_inner=True, squeeze=1.0, raw=False, look=True,
):
    root = Path(root or CAPTURES)
    t_path, r_path = find_pair(stamp, root)
    dest = root / f"P_{stamp}.jpg"
    mode = (mode or "blend").strip().lower()
    if mode not in MODES:
        raise dual.CamError("mode is match, blend, cut, open, or hugin")
    images = None
    if raw:
        files = _scan_pairs(root).get(stamp) or {}
        t_nef = (files.get("T") or {}).get("nef")
        r_nef = (files.get("R") or {}).get("nef")
        if t_nef and r_nef:
            # Only the multiband engine takes 16-bit arrays.
            images = develop_pair(
                root / t_nef, root / r_nef, size=_size(t_path), on_log=on_log,
                t_jpeg=t_path, look=look,
            )
            images["look"] = bool(look)
            images["master"] = master_path(root, stamp)
            mode = "hugin"
        elif on_log:
            on_log("raw  no NEF pair for this shot — stitching the camera JPEGs")
    requested = mode
    found = None
    ghost = {}
    t0 = time.monotonic()
    # Independent T/R deghost shifts wreck SIFT on FX; deghost after a
    # geometric fallback instead.
    tmp_ghost = tempfile.TemporaryDirectory() if (deghost and mode not in ("open", "hugin")) else None
    try:
        if tmp_ghost:
            t_path, ghost["T"] = _deghost_path(t_path, tmp_ghost.name, "T", on_log)
            r_path, ghost["R"] = _deghost_path(r_path, tmp_ghost.name, "R", on_log)
        if mode == "hugin":
            if on_log:
                on_log("hugin  SIFT similarity + multiband")
            tw, th = _size(t_path)
            prof = hugin_profile(tw, th)
            if not flip_r and prof.get("flip_r"):
                flip_r = True
            overlap = float(prof.get("overlap", overlap))
            try:
                info = stitch_hugin(
                    t_path, r_path, dest,
                    overlap=overlap, flip_r=flip_r, dy=0, on_log=on_log,
                    balance=balance, lift=False, crop_inner=crop_inner,
                    profile=prof.get("profile", "fxpan65"), images=images,
                )
                images = None
            except dual.CamError as exc:
                if on_log:
                    on_log(f"hugin failed: {exc} — match blend")
                info = stitch_files(
                    t_path, r_path, dest,
                    overlap=overlap, flip_r=flip_r, mode="blend", dy=dy,
                    on_log=on_log, balance=balance,
                )
                info["engine"] = "blend"
                info["hugin_error"] = str(exc)
            info["stamp"] = stamp
            info["mode"] = "blend" if info.get("hugin_error") else "hugin"
            info["phase"] = "done"
            info["error"] = ""
            info["deghost"] = {}
            if found:
                info["rmse"] = round(found["rmse"], 2)
            if info.get("hugin_error"):
                info["message"] = (
                    f"blend  (hugin missed)  ol={info.get('overlap_frac', overlap):.0%}  "
                    f"dy={info.get('dy', dy):+d}  "
                    f"flip={'on' if info.get('flip_r') else 'off'}  "
                    f"{info['width']}×{info['height']}"
                )
            else:
                info["message"] = (
                    (f"raw 16-bit {info.get('look')}  " if info.get("source") == "raw" else "")
                    + f"hugin  {info.get('engine', 'feather')}  "
                    f"ol={info.get('overlap_frac', overlap):.0%}  "
                    + (
                        f"rot={info['rot']:+.2f}°  "
                        if info.get("rot") is not None else
                        f"dy={info.get('dy', dy):+d}  "
                    )
                    + f"flip={'on' if info.get('flip_r') else 'off'}  "
                    f"{info['width']}×{info['height']}"
                )
            _finish_pano(info, dest, stamp, root, squeeze, on_log, t0)
            return info
        if mode == "open":
            if on_log:
                on_log("OpenStitching SIFT  https://github.com/OpenStitching/stitching")
            try:
                info = stitch_open(
                    t_path, r_path, dest,
                    flip_r=flip_r, try_both=not flip_r, on_log=on_log,
                    balance=balance, overlap=overlap,
                )
            except dual.CamError as exc:
                if on_log:
                    on_log(f"open failed: {exc} — geometric blend")
                if deghost:
                    tmp_ghost = tempfile.TemporaryDirectory()
                    t_path, ghost["T"] = _deghost_path(
                        t_path, tmp_ghost.name, "T", on_log)
                    r_path, ghost["R"] = _deghost_path(
                        r_path, tmp_ghost.name, "R", on_log)
                found = find_overlap(t_path, r_path, try_flip=True, on_log=on_log)
                if found["rmse"] <= 0.42:
                    overlap = found["overlap"]
                    flip_r = found["flip_r"]
                    tw, _ = _size(t_path)
                    dy = int(round(found["dy"] * (tw / WORK)))
                info = stitch_files(
                    t_path, r_path, dest,
                    overlap=overlap, flip_r=flip_r, mode="blend", dy=dy,
                    on_log=on_log, balance=balance,
                )
                info["engine"] = "blend"
                info["open_error"] = str(exc)
            info["stamp"] = stamp
            info["mode"] = "blend" if info.get("open_error") else "open"
            info["phase"] = "done"
            info["error"] = ""
            info["deghost"] = {k: v for k, v in ghost.items() if v}
            if info.get("engine") == "blend":
                info["message"] = (
                    f"blend  (open missed)  ol={info.get('overlap_frac', overlap):.0%}  "
                    f"dy={info.get('dy', dy):+d}  "
                    f"flip={'on' if info.get('flip_r') else 'off'}  "
                    f"{info['width']}×{info['height']}"
                )
            else:
                info["message"] = (
                    f"open  {info.get('engine', '')}  "
                    f"ol={info.get('overlap_frac', 0):.0%}  "
                    f"dy={info.get('dy', 0):+d}  "
                    f"flip={'on' if info.get('flip_r') else 'off'}  "
                    f"{info['width']}×{info['height']}"
                )
            _finish_pano(info, dest, stamp, root, squeeze, on_log, t0)
            return info
        if mode == "match":
            if on_log:
                on_log("match overlap + vertical + flop")
            overlap, flip_r, dy, found = _search_align(
                t_path, r_path, overlap, flip_r, dy=dy, on_log=on_log,
            )
            mode = "blend"
        info = stitch_files(
            t_path, r_path, dest,
            overlap=overlap, flip_r=flip_r, mode=mode, dy=dy, on_log=on_log,
            balance=balance,
        )
        info["stamp"] = stamp
        info["mode"] = requested
        info["phase"] = "done"
        info["error"] = ""
        info["deghost"] = {k: v for k, v in ghost.items() if v}
        if found:
            info["rmse"] = round(found["rmse"], 2)
        info["message"] = (
            f"{info['mode']}  ol={info['overlap_frac']:.0%}  dy={info['dy']:+d}  "
            f"flip={'on' if info['flip_r'] else 'off'}  {info['width']}×{info['height']}"
        )
        _finish_pano(info, dest, stamp, root, squeeze, on_log, t0)
        return info
    finally:
        if tmp_ghost:
            tmp_ghost.cleanup()


def queue_status():
    with _queue_lock:
        queued = [item["stamp"] for item in _queue]
    run = None
    with _jobs_lock:
        for job in _jobs.values():
            if job.get("running") and job.get("phase") not in ("queued", "done", "error"):
                run = dict(job)
                break
    nq = len(queued)
    if run:
        msg = (run.get("message") or run.get("phase") or "working").strip()
        line = f"{run.get('mode') or ''}  {run.get('stamp') or ''}  {msg}".strip()
        if nq:
            line += f"  ·  {nq} queued"
        return {
            "running": True, "queued": nq, "stamp": run.get("stamp"),
            "phase": run.get("phase"), "error": run.get("error") or "",
            "message": line,
        }
    if nq:
        return {
            "running": False, "queued": nq, "stamp": queued[0],
            "phase": "queued", "error": "",
            "message": f"{nq} queued  next {queued[0]}",
        }
    return {
        "running": False, "queued": 0, "stamp": "",
        "phase": "", "error": "", "message": "idle",
    }


def _work_running():
    with _jobs_lock:
        return any(
            j.get("running") and j.get("phase") not in ("queued", "done", "error")
            for j in _jobs.values()
        )


def _refresh_queue_logs():
    for i, item in enumerate(_queue):
        ahead = i
        job_put(
            item["stamp"],
            running=True, phase="queued", mode=item["mode"], error="",
            log=("queued  next" if ahead == 0 else f"queued  {ahead} ahead"),
        )


def _run_item(item):
    stamp = item["stamp"]
    try:
        def on_log(msg):
            job_put(stamp, phase="work", log=msg)

        info = stitch_stamp(
            stamp, overlap=item["overlap"], flip_r=item["flip_r"],
            mode=item["mode"], root=item.get("root"), on_log=on_log,
            deghost=item.get("deghost", False),
            balance=item.get("balance", True),
            crop_inner=item.get("crop_inner", True),
            squeeze=item.get("squeeze", 1.0),
            raw=item.get("raw", False),
            look=item.get("look", True),
        )
        job_put(
            stamp, running=False, phase="done", error="",
            **{k: info[k] for k in info
               if k not in ("stamp", "phase", "running", "error", "log")},
            log=info["message"],
        )
    except Exception as exc:
        err = str(exc)
        job_put(stamp, running=False, phase="error", error=err, log=err)
        _write_sidecar(
            Path(item.get("root") or CAPTURES), stamp,
            {"mode": item.get("mode"), "phase": "error", "error": err, "message": err},
        )
    finally:
        _kick_queue()


def _kick_queue():
    with _queue_lock:
        if _work_running() or not _queue:
            return
        item = _queue.pop(0)
        _refresh_queue_logs()
    job_put(
        item["stamp"], running=True, phase="start", error="",
        mode=item["mode"], log=f"start {item['mode']}",
    )
    threading.Thread(target=_run_item, args=(item,), name=f"pano-{item['stamp']}", daemon=True).start()


def start_stitch(stamp, overlap=OVERLAP, flip_r=False, mode="match", root=None,
                 deghost=False, balance=True, crop_inner=True, squeeze=1.0, raw=False,
                 look=True):
    stamp = (stamp or "").strip()
    if not stamp or "/" in stamp or ".." in stamp:
        raise dual.CamError("bad stamp")
    mode = (mode or "match").strip().lower()
    if mode not in MODES:
        raise dual.CamError("mode is match, blend, cut, open, or hugin")
    try:
        squeeze = float(squeeze or 1.0)
    except (TypeError, ValueError) as exc:
        raise dual.CamError("bad squeeze") from exc
    if squeeze < 1.0 or squeeze > 2.5:
        raise dual.CamError("squeeze is 1–2.5")
    item = {
        "stamp": stamp, "overlap": overlap, "flip_r": flip_r, "mode": mode,
        "root": root, "deghost": bool(deghost), "balance": bool(balance),
        "crop_inner": bool(crop_inner), "squeeze": squeeze, "raw": bool(raw),
        "look": bool(look),
    }
    with _queue_lock:
        live = job_get(stamp)
        if live.get("running"):
            raise dual.CamError(f"already stitching {stamp}")
        if any(q["stamp"] == stamp for q in _queue):
            raise dual.CamError(f"already queued {stamp}")
        if _work_running() or _queue:
            _queue.append(item)
            _refresh_queue_logs()
            return job_get(stamp)
        job_put(
            stamp, running=True, phase="start", error="", mode=mode,
            log=f"start {mode}",
        )
    threading.Thread(target=_run_item, args=(item,), name=f"pano-{stamp}", daemon=True).start()
    return job_get(stamp)


def warmup_open():
    def run():
        _venv_site()
        try:
            import cv2  # noqa: F401
            from stitching import AffineStitcher, Stitcher  # noqa: F401
        except ImportError:
            pass

    threading.Thread(target=run, name="open-warmup", daemon=True).start()
