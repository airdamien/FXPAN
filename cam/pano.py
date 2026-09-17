"""List downloaded T/R JPEG pairs and stitch a hybrid pano.

After R flop, R is image −X (left) and T is image +X (right) — same order
as LIVE PREVIEW. Designed overlap is 0.20 (openscad/hybrid/params.scad).
Match searches overlap, vertical shift, and whether R needs a flop.
Uses ImageMagick (`magick`) already on this Mac.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import shutil
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
PAIR_RE = re.compile(r"^(T|R)_(.+)\.(jpe?g)$", re.I)
PANO_RE = re.compile(r"^P_(.+)\.(jpe?g)$", re.I)
SAFE = re.compile(r"^[\w.-]+$")
DAY_RE = re.compile(r"^(\d{8})_")
MODES = ("match", "blend", "cut", "open")
WORK = 360

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
            "deghost",
        )
        if k in info
    }
    path.write_text(json.dumps(keep, indent=2) + "\n")


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
    if root.is_dir():
        for path in root.iterdir():
            m = PAIR_RE.match(path.name)
            if m and m.group(2) == stamp:
                have[m.group(1).upper()] = path.name
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
    sides = {}
    panos = {}
    if not root.is_dir():
        return []
    for path in root.iterdir():
        if not path.is_file():
            continue
        m = PAIR_RE.match(path.name)
        if m:
            sides.setdefault(m.group(2), {})[m.group(1).upper()] = path.name
            continue
        m = PANO_RE.match(path.name)
        if m:
            panos[m.group(1)] = path.name
    stamps = set(sides) | set(panos)
    locked = protected_set(root)
    rows = []
    for stamp in stamps:
        have = sides.get(stamp) or {}
        rows.append(
            {
                "stamp": stamp,
                "t": have.get("T"),
                "r": have.get("R"),
                "pano": panos.get(stamp),
                "pano_mtime": _mtime(root / panos[stamp]) if panos.get(stamp) else 0,
                "ready": bool(have.get("T") and have.get("R")),
                "protected": stamp in locked,
                "exif": pair_exif(root, stamp, have),
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
            if not path.is_file() or path.suffix.lower() not in (".jpg", ".jpeg"):
                continue
            m = PAIR_RE.match(path.name) or PANO_RE.match(path.name)
            if not m:
                continue
            stamp = m.group(2) if PAIR_RE.match(path.name) else m.group(1)
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
    left = False
    if Path(root).is_dir():
        for path in Path(root).iterdir():
            m = PAIR_RE.match(path.name) or PANO_RE.match(path.name)
            if not m:
                continue
            got = m.group(2) if PAIR_RE.match(path.name) else m.group(1)
            if got == stamp:
                left = True
                break
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
        _magick([str(src), "-thumbnail", f"{width}x{width}", "-quality", "70", str(tmp)])
        tmp.replace(dest)
    finally:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
    return dest


def serve(name, width=None, root=None):
    if width:
        try:
            return thumb(name, width, root)
        except dual.CamError:
            pass
    return resolve(name, root)


def find_pair(stamp, root=None):
    root = Path(root or CAPTURES)
    if not stamp or "/" in stamp or ".." in stamp:
        raise dual.CamError("bad stamp")
    have = {}
    if root.is_dir():
        for path in root.iterdir():
            m = PAIR_RE.match(path.name)
            if m and m.group(2) == stamp:
                have[m.group(1).upper()] = path
    if "T" not in have or "R" not in have:
        raise dual.CamError(f"need T and R JPEGs for {stamp}")
    return have["T"], have["R"]


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


def _search_shift(t, r, on_log=None):
    best = (1e9, 0.20, 0)
    for pct in range(10, 37, 3):
        ol = max(4, int(round(t.w * pct / 100)))
        max_dy = min(8, t.h // 24)
        for dy in range(-max_dy, max_dy + 1, 2):
            s = _score_ol(t, r, ol, dy)
            if s < best[0]:
                best = (s, pct / 100, dy)
                if on_log:
                    on_log(f"search ol={pct}% dy={dy:+d}  {s:.1f}")
    pct0 = int(round(best[1] * 100))
    dy0 = best[2]
    max_dy = min(8, t.h // 24)
    for pct in range(max(10, pct0 - 3), min(38, pct0 + 4)):
        ol = max(4, int(round(t.w * pct / 100)))
        for dy in range(max(-max_dy, dy0 - 3), min(max_dy, dy0 + 3) + 1):
            s = _score_ol(t, r, ol, dy)
            if s < best[0]:
                best = (s, pct / 100, dy)
    return best


def find_overlap(t_path, r_path, try_flip=True, on_log=None):
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
            rmse, frac, dy = _search_shift(t, r, on_log=log)
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


def stitch_files(
    t_path, r_path, dest, overlap=OVERLAP, flip_r=False, mode="blend", dy=0, on_log=None,
    balance=True,
):
    def log(msg):
        if on_log:
            on_log(msg)

    mode = (mode or "blend").strip().lower()
    if mode not in MODES:
        raise dual.CamError("mode is match, blend, or cut")
    overlap = float(overlap)
    if overlap < 0.05 or overlap > 0.50:
        raise dual.CamError("overlap 0.05–0.50")
    dy = int(dy)
    w, h = _size(t_path)
    rw, rh = _size(r_path)
    ol = max(1, min(w - 1, int(round(w * overlap))))
    x = w - ol
    out_w = w + w - ol
    ty = max(0, -dy)
    ry = max(0, dy)
    out_h = h + abs(dy)
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    log(f"compose {mode}  ol={ol}px ({overlap:.0%}) dy={dy:+d} flip={'on' if flip_r else 'off'}")
    with tempfile.TemporaryDirectory() as tmp:
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
        _magick([str(r_use), "-crop", f"{ol}x{h}+{x}+0", "+repage", str(tmp / "rol.png")])
        _magick([str(t_use), "-crop", f"{ol}x{h}+0+0", "+repage", str(tmp / "tol.png")])
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
            if ol <= 1:
                _magick(["-size", f"{ol}x{h}", "xc:#808080", str(tmp / "mask.png")])
            else:
                _magick(
                    [
                        "-size",
                        f"{ol}x{h}",
                        "xc:",
                        "-sparse-color",
                        "barycentric",
                        f"0,0 black {ol - 1},0 white",
                        str(tmp / "mask.png"),
                    ]
                )
            _magick(
                [
                    str(tmp / "rol.png"),
                    str(tmp / "tol.png"),
                    str(tmp / "mask.png"),
                    "-compose",
                    "over",
                    "-composite",
                    str(tmp / "ol.png"),
                ]
            )
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
                    f"+{x}+{ty}",
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
        if "T" in want and row["t"]:
            names.append(row["t"])
        if "R" in want and row["r"]:
            names.append(row["r"])
        if "P" in want and row["pano"]:
            names.append(row["pano"])
        break
    else:
        raise dual.CamError("missing pair")
    count = 0
    for name in names:
        count += _unlink_named(root, name)
    left = False
    if root.is_dir():
        for path in root.iterdir():
            m = PAIR_RE.match(path.name) or PANO_RE.match(path.name)
            if not m:
                continue
            got = m.group(2) if PAIR_RE.match(path.name) else m.group(1)
            if got == stamp:
                left = True
                break
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


def _overlap_feature_masks(w, h, overlap, tmp):
    import cv2
    import numpy as np

    band = max(int(w * overlap * 1.5), int(w * 0.22))
    band = min(band, w // 2)
    tmask = np.zeros((h, w), np.uint8)
    tmask[:, :band] = 255
    rmask = np.zeros((h, w), np.uint8)
    rmask[:, w - band :] = 255
    tp, rp = Path(tmp) / "tmask.png", Path(tmp) / "rmask.png"
    cv2.imwrite(str(tp), tmask)
    cv2.imwrite(str(rp), rmask)
    return tp, rp, band


def stitch_open(t_path, r_path, dest, flip_r=False, try_both=True, on_log=None,
                balance=True, overlap=OVERLAP):
    """Feature-match stitch via OpenStitching (OpenCV). https://github.com/OpenStitching/stitching"""
    def log(msg):
        if on_log:
            on_log(msg)

    log("OpenStitching  loading…")
    _venv_site()
    try:
        import cv2
        from stitching import AffineStitcher
        from stitching.stitching_error import StitchingError
    except ImportError as exc:
        raise dual.CamError(
            "OpenStitching missing.  cd cam && python3 -m venv .venv && "
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
                _magick([str(r_path), "-flop", str(r_use)])
                log("OpenStitching  R flopped")
            else:
                log("OpenStitching  R as-shot")
            comp = "channel" if balance else "no"
            if balance:
                log("balance OpenStitching channel (warped overlap)")
            log("OpenStitching  affine sift")
            try:
                stitcher = AffineStitcher(
                    detector="sift",
                    nfeatures=6000,
                    confidence_threshold=0.05,
                    match_conf=0.3,
                    compensator=comp,
                    nr_feeds=3 if balance else 1,
                    crop=False,
                    medium_megapix=0.8,
                )
                img = stitcher.stitch(
                    [str(r_use), str(t_path)],
                    feature_masks=[str(rmask), str(tmask)],
                )
                if img is None or getattr(img, "size", 0) == 0:
                    raise StitchingError("empty panorama")
                if balance:
                    img, note = _match_seam_img(img)
                    if note:
                        log(note)
                if not cv2.imwrite(
                    str(dest), img, [int(cv2.IMWRITE_JPEG_QUALITY), 92]
                ):
                    raise dual.CamError("OpenStitching write failed")
                w, h = _size(dest)
                if w < int(tw * 1.15):
                    raise StitchingError(
                        f"affine too narrow {w}×{h} (need a wide T+R pano)"
                    )
                log(f"OpenStitching  affine  {w}×{h}  flip={'on' if flop else 'off'}")
                return {
                    "file": dest.name,
                    "width": w,
                    "height": h,
                    "overlap": 0,
                    "overlap_frac": 0,
                    "dy": 0,
                    "flip_r": flop,
                    "mode": "open",
                    "engine": "affine",
                }
            except Exception as exc:
                last = exc
                log(f"affine failed: {exc}")
    raise dual.CamError(str(last) if last else "OpenStitching failed")


def stitch_stamp(
    stamp, overlap=OVERLAP, flip_r=False, mode="blend", dy=0, root=None, on_log=None,
    deghost=False, balance=True,
):
    root = Path(root or CAPTURES)
    t_path, r_path = find_pair(stamp, root)
    dest = root / f"P_{stamp}.jpg"
    mode = (mode or "blend").strip().lower()
    if mode not in MODES:
        raise dual.CamError("mode is match, blend, cut, or open")
    requested = mode
    found = None
    ghost = {}
    # Independent T/R deghost shifts wreck SIFT on FX; deghost after a
    # geometric fallback instead.
    tmp_ghost = tempfile.TemporaryDirectory() if (deghost and mode != "open") else None
    try:
        if tmp_ghost:
            t_path, ghost["T"] = _deghost_path(t_path, tmp_ghost.name, "T", on_log)
            r_path, ghost["R"] = _deghost_path(r_path, tmp_ghost.name, "R", on_log)
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
                    f"flip={'on' if info.get('flip_r') else 'off'}  "
                    f"{info['width']}×{info['height']}"
                )
            _write_sidecar(root, stamp, info)
            return info
        if mode == "match":
            if on_log:
                on_log("match overlap + vertical + flop")
            found = find_overlap(t_path, r_path, try_flip=True, on_log=on_log)
            if found["rmse"] > 0.42:
                if on_log:
                    on_log(
                        f"match weak ({found['rmse']:.2f}) — keep ol={overlap:.0%} "
                        f"flip={'on' if flip_r else 'off'}"
                    )
            else:
                overlap = found["overlap"]
                flip_r = found["flip_r"]
                tw, _ = _size(t_path)
                dy = int(round(found["dy"] * (tw / WORK)))
                if on_log:
                    on_log(
                        f"best ol={overlap:.0%} dy={dy:+d} "
                        f"flip={'on' if flip_r else 'off'}  {found['rmse']:.1f}"
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
        _write_sidecar(root, stamp, info)
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
                 deghost=False, balance=True):
    stamp = (stamp or "").strip()
    if not stamp or "/" in stamp or ".." in stamp:
        raise dual.CamError("bad stamp")
    mode = (mode or "match").strip().lower()
    if mode not in MODES:
        raise dual.CamError("mode is match, blend, cut, or open")
    item = {
        "stamp": stamp, "overlap": overlap, "flip_r": flip_r, "mode": mode,
        "root": root, "deghost": bool(deghost), "balance": bool(balance),
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
