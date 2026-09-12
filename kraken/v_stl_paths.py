#!/usr/bin/env python3
"""Rays on the V print STLs.

stls/v/chassis.stl + mirror_tray.stl. Plastic is absorb. Two 45° first-surface
mirrors at the knife: +X field → R (+X), −X field → L (−X). Incoming from
the lens (−Y).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
import pyvista as pv

ROOT = Path(__file__).resolve().parents[1]
SCAD = ROOT / "openscad" / "WATCH_ME.scad"
STL_DIR = ROOT / "stls" / "v"
OUT = Path(__file__).resolve().parent / "preview_v_stl_paths.png"
DOCS = ROOT / "docs" / "kraken" / "v_stl_paths.png"
OSC = Path("/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD")
KNIFE = 1.0
Y0 = -58.0


def export_stls():
    STL_DIR.mkdir(parents=True, exist_ok=True)
    osc = str(OSC if OSC.exists() else "openscad")
    for part in ("chassis", "mirror_tray"):
        dest = STL_DIR / f"{part}.stl"
        if dest.exists() and dest.stat().st_size > 1000:
            continue
        print(f"export {part} -> {dest}")
        subprocess.run(
            [osc, "-o", str(dest), "--export-format", "binstl",
             "-D", f'PART="{part}"', str(SCAD)],
            check=True,
        )


def _continue(meshes, origin, direction, tmax=130.0):
    d = np.asarray(direction, dtype=float)
    n = np.linalg.norm(d)
    if n < 1e-9:
        return origin
    d = d / n
    start = origin + d * 0.35
    stop = origin + d * tmax
    best = None
    for mesh in meshes:
        try:
            hits, _ = mesh.ray_trace(start, stop)
        except Exception:
            continue
        if len(hits):
            dist = np.linalg.norm(hits[0] - origin)
            if best is None or dist < best[0]:
                best = (dist, hits[0])
    return best[1] if best is not None else stop


def _fan(meshes, side):
    """side +1 = R (+X), −1 = L (−X). Plane n = (side, −1, 0)/√2."""
    n = np.array([side, -1.0, 0.0], dtype=float)
    n /= np.linalg.norm(n)
    outgoing = np.array([side, 0.0, 0.0], dtype=float)
    xs = np.linspace(KNIFE, 18.0, 8) * side
    zs = np.array([-6.0, 0.0, 6.0])
    paths = []
    for x0 in xs:
        for z0 in zs:
            src = np.array([x0, Y0, z0], dtype=float)
            din = np.array([0.0, 1.0, 0.0])
            denom = float(np.dot(din, n))
            if abs(denom) < 1e-9:
                continue
            t = float(np.dot(-src, n) / denom)
            if t < 0.2:
                continue
            hit = src + t * din
            if abs(hit[2]) > 26.0:
                continue
            end = _continue(meshes, hit, outgoing)
            paths.append(np.vstack([src, hit, end]))
    return paths


def _mirrors():
    right = pv.Box(bounds=(-1.5, 1.5, 0.0, 50.0, -25.0, 25.0))
    right.rotate_z(-45, inplace=True)
    left = pv.Box(bounds=(-1.5, 1.5, 0.0, 50.0, -25.0, 25.0))
    left.rotate_z(45, inplace=True)
    return left, right


def _draw(plotter, chassis, tray, rays_l, rays_r):
    box = chassis.clip(normal=(0, 0, 1), origin=(0, 0, 10), invert=True)
    plotter.add_mesh(box, color=[0.42, 0.44, 0.47], opacity=0.18,
                     smooth_shading=True, show_edges=False)
    plotter.add_mesh(tray, color=[0.18, 0.40, 0.72], opacity=0.38,
                     smooth_shading=True, show_edges=False)
    left, right = _mirrors()
    plotter.add_mesh(left, color=[0.90, 0.75, 0.20], opacity=0.50,
                     smooth_shading=True)
    plotter.add_mesh(right, color=[0.90, 0.75, 0.20], opacity=0.50,
                     smooth_shading=True)
    for pts in rays_l:
        plotter.add_mesh(pv.lines_from_points(pts), color=[0.15, 0.40, 0.90],
                         line_width=2.2, opacity=0.95)
    for pts in rays_r:
        plotter.add_mesh(pv.lines_from_points(pts), color=[0.90, 0.18, 0.14],
                         line_width=2.2, opacity=0.95)
    plotter.add_axes(line_width=2)


def render(chassis, tray, rays_l, rays_r, dest):
    plotter = pv.Plotter(off_screen=True, window_size=(1800, 900), shape=(1, 2))
    plotter.set_background("white")
    plotter.subplot(0, 0)
    _draw(plotter, chassis, tray, rays_l, rays_r)
    plotter.camera_position = [(0, 0, 170), (0, 5, 0), (0, 1, 0)]
    plotter.add_text("top  ·  lens −Y  ·  L −X  ·  R +X", font_size=10,
                     color="black", position="upper_left")
    plotter.subplot(0, 1)
    _draw(plotter, chassis, tray, rays_l, rays_r)
    plotter.camera_position = [(-30, -130, 115), (0, 8, 0), (0, 0, 1)]
    plotter.add_text("V knife on chassis + tray STL", font_size=10,
                     color="black", position="upper_left")
    dest.parent.mkdir(parents=True, exist_ok=True)
    plotter.screenshot(str(dest))
    plotter.close()


def main():
    export_stls()
    chassis_p = STL_DIR / "chassis.stl"
    tray_p = STL_DIR / "mirror_tray.stl"
    for p in (chassis_p, tray_p):
        print(p, f"{p.stat().st_size / 1024:.0f} KB")

    chassis = pv.read(str(chassis_p))
    tray = pv.read(str(tray_p))
    meshes = [chassis, tray]
    rays_l = _fan(meshes, -1)
    rays_r = _fan(meshes, 1)
    print(f"L paths={len(rays_l)}  R paths={len(rays_r)}")
    if rays_l:
        print("L end", np.round(rays_l[len(rays_l) // 2][-1], 2))
    if rays_r:
        print("R end", np.round(rays_r[len(rays_r) // 2][-1], 2))

    render(chassis, tray, rays_l, rays_r, OUT)
    render(chassis, tray, rays_l, rays_r, DOCS)
    print(OUT)
    print(DOCS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
