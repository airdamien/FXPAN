"""List downloaded T/R JPEG pairs and stitch a hybrid pano.

T is image −X (left), R is image +X (right). Designed overlap is 0.20
(openscad/hybrid/params.scad). The reflect path is mirrored unless flip_r
is off. Uses ImageMagick (`magick`) already on this Mac.
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path

import dual

MAGICK = os.environ.get("MAGICK", "magick")
CAPTURES = Path(__file__).resolve().parent.parent / "captures"
OVERLAP = 0.20
PAIR_RE = re.compile(r"^(T|R)_(.+)\.(jpe?g)$", re.I)
PANO_RE = re.compile(r"^P_(.+)\.(jpe?g)$", re.I)
SAFE = re.compile(r"^[\w.-]+$")


def _magick(args, timeout=180):
    try:
        proc = subprocess.run(
            [MAGICK, *args], capture_output=True, text=True, timeout=timeout
        )
    except FileNotFoundError as exc:
        raise dual.CamError("ImageMagick `magick` not found") from exc
    if proc.returncode:
        err = (proc.stderr or proc.stdout or "magick failed").strip()
        raise dual.CamError(err.split("\n")[-1])
    return proc.stdout


def _size(path):
    w, h = _magick(["identify", "-format", "%w %h", str(path)]).split()
    return int(w), int(h)


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
    rows = []
    for stamp in stamps:
        have = sides.get(stamp) or {}
        rows.append(
            {
                "stamp": stamp,
                "t": have.get("T"),
                "r": have.get("R"),
                "pano": panos.get(stamp),
                "ready": bool(have.get("T") and have.get("R")),
            }
        )
    rows.sort(key=lambda row: (row["ready"], row["stamp"]), reverse=True)
    return rows


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


def thumb(name, width, root=None):
    root = Path(root or CAPTURES)
    src = resolve(name, root)
    width = max(80, min(1280, int(width)))
    dest_dir = root / ".thumbs"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{width}_{src.name}"
    if dest.exists() and dest.stat().st_mtime >= src.stat().st_mtime:
        return dest
    _magick([str(src), "-thumbnail", f"{width}x{width}", "-quality", "70", str(dest)])
    return dest


def serve(name, width=None, root=None):
    if width:
        return thumb(name, width, root)
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


def stitch_files(t_path, r_path, dest, overlap=OVERLAP, flip_r=True):
    overlap = float(overlap)
    if overlap < 0.05 or overlap > 0.45:
        raise dual.CamError("overlap 0.05–0.45")
    w, h = _size(t_path)
    rw, rh = _size(r_path)
    ol = max(1, min(w - 1, int(round(w * overlap))))
    x = w - ol
    out_w = w + w - ol
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        r_use = tmp / "r.jpg"
        args = [str(r_path), "-colorspace", "sRGB"]
        if flip_r:
            args += ["-flop"]
        if (rw, rh) != (w, h):
            args += ["-resize", f"{w}x{h}!"]
        _magick(args + [str(r_use)])
        t_use = tmp / "t.jpg"
        _magick([str(t_path), "-colorspace", "sRGB", str(t_use)])
        _magick([str(t_use), "-crop", f"{ol}x{h}+{x}+0", "+repage", str(tmp / "tol.png")])
        _magick([str(r_use), "-crop", f"{ol}x{h}+0+0", "+repage", str(tmp / "rol.png")])
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
                str(tmp / "tol.png"),
                str(tmp / "rol.png"),
                str(tmp / "mask.png"),
                "-compose",
                "over",
                "-composite",
                str(tmp / "ol.png"),
            ]
        )
        _magick(
            [
                str(t_use),
                "-background",
                "black",
                "-extent",
                f"{out_w}x{h}",
                str(tmp / "canvas.jpg"),
            ]
        )
        _magick(
            [
                str(tmp / "canvas.jpg"),
                str(r_use),
                "-geometry",
                f"+{x}+0",
                "-composite",
                str(tmp / "ol.png"),
                "-geometry",
                f"+{x}+0",
                "-composite",
                "-quality",
                "92",
                str(dest),
            ]
        )
    return {"file": dest.name, "width": out_w, "height": h, "overlap": ol}


def stitch_stamp(stamp, overlap=OVERLAP, flip_r=True, root=None):
    root = Path(root or CAPTURES)
    t_path, r_path = find_pair(stamp, root)
    dest = root / f"P_{stamp}.jpg"
    info = stitch_files(t_path, r_path, dest, overlap=overlap, flip_r=flip_r)
    info["stamp"] = stamp
    return info
