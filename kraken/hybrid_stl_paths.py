#!/usr/bin/env python3
"""Non-sequential KrakenOS trace against the hybrid print STLs.

Exports stls/hybrid/chassis.stl and hybrid_tray.stl if needed. Plastic is
ABSORB. A 45° Kraken mirror stands in for the 50/50 (R fan). The T fan goes
through the empty slot. Rays are drawn back on the OpenSCAD meshes.
"""

from __future__ import annotations

import contextlib
import io
import subprocess
import sys
from pathlib import Path

import numpy as np
import pyvista as pv

import KrakenOS as Kos

ROOT = Path(__file__).resolve().parents[1]
SCAD = ROOT / "openscad" / "hybrid" / "WATCH_ME.scad"
STL_DIR = ROOT / "stls" / "hybrid"
OUT = Path(__file__).resolve().parent / "preview_stl_paths.png"
OSC = Path("/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD")
WAVE = 0.55


def export_stls():
    STL_DIR.mkdir(parents=True, exist_ok=True)
    osc = str(OSC if OSC.exists() else "openscad")
    for part in ("chassis", "hybrid_tray"):
        dest = STL_DIR / f"{part}.stl"
        if dest.exists() and dest.stat().st_size > 1000:
            continue
        print(f"export {part} -> {dest}")
        subprocess.run(
            [osc, "-o", str(dest), "--export-format", "binstl",
             "-D", f'PART="{part}"', str(SCAD)],
            check=True,
        )


def quiet_system(surfaces):
    with contextlib.redirect_stdout(io.StringIO()):
        system = Kos.system(surfaces, Kos.Setup())
    system.NsLimit = 16
    system.energy_probability = 0
    return system


def rx90(path):
    mesh = pv.read(str(path))
    mesh.rotate_x(90, inplace=True)
    return mesh


def to_openscad(pts):
    """Kraken frame after Rx(90) on the STLs → OpenSCAD (X right, −Y lens, Z up)."""
    p = np.atleast_2d(np.asarray(pts, dtype=float))
    return np.column_stack([p[:, 0], p[:, 2], -p[:, 1]])


def stl_surf(mesh, name, glass="ABSORB"):
    s = Kos.surf()
    s.Name = name
    s.Solid_3d_stl = mesh
    s.Glass = glass
    s.Diameter = 220
    s.Thickness = 0.0
    s.AxisMove = 0
    s.Drawing = 1
    return s


def make_system(chassis_m, tray_m, reflect=True):
    obj = Kos.surf()
    obj.Thickness = 0.0
    obj.Glass = "AIR"
    obj.Diameter = 0.01
    obj.Drawing = 0
    obj.AxisMove = 0
    surfaces = [obj, stl_surf(chassis_m, "c"), stl_surf(tray_m, "t")]
    if reflect:
        plate = Kos.surf()
        plate.Name = "plate"
        plate.Glass = "MIRROR"
        plate.Diameter = 70
        plate.Thickness = 0.0
        plate.AxisMove = 0
        plate.TiltY = -45  # sit on the real slot (Kraken x=z = OpenSCAD x=y)
        plate.Drawing = 0
        surfaces.append(plate)
    catch = Kos.surf()
    catch.Name = "T"
    catch.Glass = "ABSORB"
    catch.Diameter = 90
    catch.DespZ = 90
    catch.AxisMove = 0
    catch.Drawing = 0
    surfaces.append(catch)
    return quiet_system(surfaces)


def _xyz(system):
    pts = np.asarray(system.XYZ, dtype=float)
    if pts.size == 0:
        return np.zeros((0, 3))
    return np.atleast_2d(pts)


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


def trace_fan(system, meshes, xs, ys, z0=-58.0, reflect=False):
    paths = []
    for x0 in xs:
        for y0 in ys:
            system.NsTrace([float(x0), float(y0), z0], [0.0, 0.0, 1.0], WAVE)
            xyz = _xyz(system)
            if len(xyz) < 2:
                continue
            names = []
            try:
                names = [str(n) for n in system.NAME]
            except TypeError:
                names = []
            if reflect and names and names[-1] == "plate":
                # Slot is on x=z; coating toward the lens folds +Z → +X (side port).
                nxt = _continue(meshes, xyz[-1], [1.0, 0.0, 0.0])
                xyz = np.vstack([xyz, nxt])
            paths.append(xyz)
    return paths


def _draw_scene(plotter, chassis, tray, rays_t, rays_r):
    box = chassis.clip(normal=(0, 0, 1), origin=(0, 0, 10), invert=True)
    plotter.add_mesh(box, color=[0.42, 0.44, 0.47], opacity=0.18,
                     smooth_shading=True, show_edges=False)
    plotter.add_mesh(tray, color=[0.18, 0.40, 0.72], opacity=0.38,
                     smooth_shading=True, show_edges=False)
    plate = pv.Box(bounds=(-0.5, 0.5, -25, 25, -25, 25))
    plate.rotate_z(-45, inplace=True)
    plotter.add_mesh(plate, color=[0.90, 0.75, 0.20], opacity=0.50,
                     smooth_shading=True)
    for pts in rays_t:
        plotter.add_mesh(pv.lines_from_points(pts), color=[0.15, 0.40, 0.90],
                         line_width=2.2, opacity=0.95)
    for pts in rays_r:
        plotter.add_mesh(pv.lines_from_points(pts), color=[0.90, 0.18, 0.14],
                         line_width=2.2, opacity=0.95)
    plotter.add_axes(line_width=2)


def render(chassis, tray, rays_t, rays_r, dest):
    plotter = pv.Plotter(off_screen=True, window_size=(1800, 900), shape=(1, 2))
    plotter.set_background("white")
    plotter.subplot(0, 0)
    _draw_scene(plotter, chassis, tray, rays_t, rays_r)
    plotter.camera_position = [(0, 0, 170), (0, 5, 0), (0, 1, 0)]
    plotter.add_text("top  ·  lens −Y  ·  T +Y  ·  R +X", font_size=10,
                     color="black", position="upper_left")
    plotter.subplot(0, 1)
    _draw_scene(plotter, chassis, tray, rays_t, rays_r)
    plotter.camera_position = [(70, -90, 95), (5, 10, 0), (0, 0, 1)]
    plotter.add_text("Kraken NS on chassis + tray STL", font_size=10,
                     color="black", position="upper_left")
    dest.parent.mkdir(parents=True, exist_ok=True)
    plotter.screenshot(str(dest))
    plotter.close()


def main():
    export_stls()
    chassis_p = STL_DIR / "chassis.stl"
    tray_p = STL_DIR / "hybrid_tray.stl"
    for p in (chassis_p, tray_p):
        print(p, f"{p.stat().st_size / 1024:.0f} KB")

    chassis_k = rx90(chassis_p)
    tray_k = rx90(tray_p)
    meshes = [chassis_k, tray_k]
    sys_t = make_system(chassis_k, tray_k, reflect=False)
    sys_r = make_system(chassis_k, tray_k, reflect=True)

    xs = np.linspace(-14, 14, 8)
    ys = np.array([-6.0, 0.0, 6.0])
    rays_t = [to_openscad(p) for p in trace_fan(sys_t, meshes, xs, ys, reflect=False)]
    rays_r = [to_openscad(p) for p in trace_fan(sys_r, meshes, xs, ys, reflect=True)]
    print(f"T paths={len(rays_t)}  R paths={len(rays_r)}")
    if rays_t:
        print("T end", np.round(rays_t[len(rays_t) // 2][-1], 2))
    if rays_r:
        print("R end", np.round(rays_r[len(rays_r) // 2][-1], 2))

    render(pv.read(str(chassis_p)), pv.read(str(tray_p)), rays_t, rays_r, OUT)
    print(OUT)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
