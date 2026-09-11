#!/usr/bin/env python3
"""Trace the hybrid L pano in KrakenOS.

Taking lens is the El-Nikkor 50/2.8 Japan (f=51.6 mm) on PATH_TOTAL, so
the object sits at ~73 mm — close-up only. Each DX sensor is aimed at a
different half of a stitch_w image (sensor_shift).
"""

from __future__ import annotations

import contextlib
import io
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

import KrakenOS as Kos

# openscad/hybrid/params.scad
FLANGE_F = 46.5
D_LENS_TO_PLATE = 55.0
D_PLATE_TO_MOUNT = 72.0
PATH_TOTAL = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT + FLANGE_F
PATH_AFTER = D_PLATE_TO_MOUNT + FLANGE_F
SENSOR_W = 23.6
SENSOR_H = 15.6
OVERLAP_FRAC = 0.20
TUBE_ID = 52.0
JUNCTION_BOX = 90.0
WAVE = 0.55

# El-Nikkor 50/2.8 Japan (published 51.6 mm). Cannot reach infinity here.
EL_NAME = "EL-Nikkor 50/2.8"
EL_F = 51.6
EL_FNUM = 5.6
EL_EPD = EL_F / EL_FNUM
S_PRIME = PATH_TOTAL
S_OBJ = 1.0 / (1.0 / EL_F - 1.0 / S_PRIME)
MAG = S_PRIME / S_OBJ

SHIFT = SENSOR_W / 2.0 * (1.0 - OVERLAP_FRAC)
HALF_W = SENSOR_W / 2.0
HALF_H = SENSOR_H / 2.0
OL_W = SENSOR_W * OVERLAP_FRAC / 2.0
STITCH_W = SENSOR_W * (2.0 - OVERLAP_FRAC)
SINGLE_FOV = 2.0 * np.degrees(np.arctan(HALF_W / PATH_TOTAL))
PANO_FOV = 2.0 * np.degrees(np.arctan(STITCH_W / 2.0 / PATH_TOTAL))

OUT = Path(__file__).resolve().parent


def on_t(x, y):
    return abs(x + SHIFT) <= HALF_W and abs(y) <= HALF_H


def on_r(x, y):
    return abs(x - SHIFT) <= HALF_W and abs(y) <= HALF_H


def _quiet_system(surfaces):
    with contextlib.redirect_stdout(io.StringIO()):
        return Kos.system(surfaces, Kos.Setup())


def _xyz(system):
    pts = np.asarray(system.XYZ, dtype=float)
    if pts.size == 0:
        return np.zeros((0, 3))
    return np.atleast_2d(pts)


def _ost(system):
    pts = np.asarray(system.OST_XYZ, dtype=float)
    if pts.size == 0:
        return np.zeros((0, 3))
    return np.atleast_2d(pts)


def reflect_system():
    obj = Kos.surf()
    obj.Thickness = D_LENS_TO_PLATE
    obj.Glass = "AIR"
    obj.Diameter = 80
    obj.Drawing = 0
    plate = Kos.surf()
    plate.Name = "plate"
    plate.Glass = "MIRROR"
    plate.Diameter = 70
    plate.TiltY = 45
    plate.AxisMove = 2
    plate.Thickness = PATH_AFTER
    plate.Color = [0.85, 0.65, 0.15]
    ima = Kos.surf()
    ima.Name = "R"
    ima.Glass = "AIR"
    ima.Diameter = 40
    return _quiet_system([obj, plate, ima])


def transmit_system(focal=True):
    """El-Nikkor 50/2.8 at the finite conjugate this chassis forces."""
    obj = Kos.surf()
    obj.Thickness = S_OBJ if focal else 0.0
    obj.Glass = "AIR"
    obj.Diameter = 80
    obj.Drawing = 0
    obj.Name = "object"
    lens = Kos.surf()
    lens.Name = "EL-Nikkor"
    if focal:
        lens.Thin_Lens = EL_F
        lens.Diameter = EL_EPD
        lens.Thickness = S_PRIME
    else:
        lens.Diameter = TUBE_ID
        lens.Thickness = PATH_TOTAL
    lens.Glass = "AIR"
    ima = Kos.surf()
    ima.Name = "T"
    ima.Glass = "AIR"
    ima.Diameter = 80
    return _quiet_system([obj, lens, ima])


def classify(x_knife):
    return "plate"


def knife_x(xyz, z_knife=D_LENS_TO_PLATE):
    """Where a T-path ray crosses the knife plane."""
    if len(xyz) < 2:
        return float("nan")
    p0, p1 = xyz[0], xyz[-1]
    dz = p1[2] - p0[2]
    if abs(dz) < 1e-9:
        return p0[0]
    t = (z_knife - p0[2]) / dz
    return p0[0] + t * (p1[0] - p0[0])


def trace_fan(sys_r, sys_t):
    """Collimated +Z fan at the knife — path figure."""
    xs = np.array([-18, -12, -8, -4, -1.5, 1.5, 4, 7, 11, 16], dtype=float)
    rows = []
    for x0 in xs:
        sys_t.Trace([float(x0), 0.0, 0.0], [0.0, 0.0, 1.0], WAVE)
        kind = classify(x0)
        t_xyz = _xyz(sys_t)
        r_xyz = None
        sys_r.Trace([float(x0), 0.0, 0.0], [0.0, 0.0, 1.0], WAVE)
        r_xyz = _xyz(sys_r)
        rows.append((kind, x0, t_xyz, r_xyz))
    return rows


def plot_paths(rows, dest):
    fig, ax = plt.subplots(figsize=(8.2, 7.2))
    half = JUNCTION_BOX / 2.0
    z0 = D_LENS_TO_PLATE
    box_x = [-half, half, half, -half, -half]
    box_z = [z0 - half, z0 - half, z0 + half, z0 + half, z0 - half]
    ax.plot(box_x, box_z, color="0.75", lw=1.0)

    # TiltY=+45: plate through the knife, +X half toward the lens, fold to +X.
    span = 50.0 / np.sqrt(2.0)
    ax.plot([0.0, span], [z0, z0 - span], color="goldenrod", lw=2.2, label="50/50 plate")

    port = 20.0
    ax.plot(
        [PATH_AFTER, PATH_AFTER],
        [z0 - port, z0 + port],
        color="crimson",
        lw=2.4,
        label="R sensor",
    )
    ax.plot(
        [-port, port],
        [PATH_TOTAL, PATH_TOTAL],
        color="steelblue",
        lw=2.4,
        label="T sensor",
    )

    colors = {"plate": "goldenrod"}
    seen = set()
    for kind, x0, t_xyz, r_xyz in rows:
        c = colors[kind]
        lab = kind if kind not in seen else None
        seen.add(kind)
        if r_xyz is not None and len(r_xyz) >= 2:
            ax.plot(r_xyz[:, 0], r_xyz[:, 2], color=c, lw=0.9, alpha=0.85, label=lab)
        if len(t_xyz) >= 2:
            ax.plot(t_xyz[:, 0], t_xyz[:, 2], color=c, lw=0.9, alpha=0.4, ls="--")

    ax.set_aspect("equal")
    ax.set_xlabel("X (mm)  side camera +X")
    ax.set_ylabel("Z (mm)  lens at 0, back camera +Z")
    ax.set_title(f"hybrid L  —  one 50/50 at z={z0:.0f} mm")
    ax.legend(loc="lower right", frameon=False)
    ax.set_xlim(-55, PATH_AFTER + 25)
    ax.set_ylim(-15, PATH_TOTAL + 20)
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def _pupil_pts():
    r = 0.70 * (EL_EPD / 2.0)
    return [(0.0, 0.0), (r, 0.0), (-r, 0.0), (0.0, r), (0.0, -r)]


def _aim(src, pup):
    d = np.asarray(pup, dtype=float) - np.asarray(src, dtype=float)
    n = np.linalg.norm(d)
    if n < 1e-9:
        return [0.0, 0.0, 1.0]
    return (d / n).tolist()


def trace_frames(sys_t):
    """Object-plane grid through the El-Nikkor; DX windows at ±sensor_shift."""
    x_max = (STITCH_W / 2.0) / MAG + 1.0
    y_max = (SENSOR_H / 2.0) / MAG + 0.4
    xs = np.linspace(-x_max, x_max, 29)
    ys = np.linspace(-y_max, y_max, 11)
    t_frac = np.zeros((len(ys), len(xs)))
    r_frac = np.zeros_like(t_frac)
    counts = {"left": 0, "overlap": 0, "right": 0, "none": 0}
    pupils = _pupil_pts()
    n_p = len(pupils)
    z_obj = 0.0
    z_lens = S_OBJ
    for ix, x_obj in enumerate(xs):
        for iy, y_obj in enumerate(ys):
            src = [float(x_obj), float(y_obj), z_obj]
            t_w = r_w = 0.0
            n_ok = 0
            for px, py in pupils:
                sys_t.Trace(src, _aim(src, [px, py, z_lens]), WAVE)
                names = sys_t.NAME
                try:
                    hit = "T" in list(names)
                except TypeError:
                    hit = False
                if not hit:
                    continue
                ost = _ost(sys_t)
                if len(ost) < 2:
                    continue
                n_ok += 1
                xi, yi = float(ost[-1][0]), float(ost[-1][1])
                if on_t(xi, yi):
                    t_w += 1.0
                if on_r(xi, yi):
                    r_w += 1.0
            if n_ok == 0:
                counts["none"] += 1
                continue
            t_frac[iy, ix] = t_w / n_p
            r_frac[iy, ix] = r_w / n_p
            ht, hr = t_frac[iy, ix] > 0.15, r_frac[iy, ix] > 0.15
            if ht and hr:
                counts["overlap"] += 1
            elif ht:
                counts["left"] += 1
            elif hr:
                counts["right"] += 1
            else:
                counts["none"] += 1
    return xs, ys, t_frac, r_frac, counts


def _chart(thx, thy, frac):
    hue = (thx - thx[0]) / (thx[-1] - thx[0])
    stripe = plt.cm.turbo(np.broadcast_to(hue, frac.shape))[..., :3]
    return np.clip(stripe * frac[..., None], 0.0, 1.0)


def _upsample(thx, thy, frac, nx=720, ny=240):
    from scipy.interpolate import RegularGridInterpolator

    interp = RegularGridInterpolator((thy, thx), frac, bounds_error=False, fill_value=0.0)
    gy, gx = np.meshgrid(np.linspace(thy[0], thy[-1], ny),
                         np.linspace(thx[0], thx[-1], nx), indexing="ij")
    return interp(np.stack([gy, gx], axis=-1))


def stitch_pano(thx, thy, t_frac, r_frac, nx=720, ny=240):
    """T + R on the same field (what a stitcher gets after aligning the two DX frames)."""
    t_hi = _upsample(thx, thy, t_frac, nx, ny)
    r_hi = _upsample(thx, thy, r_frac, nx, ny)
    gx = np.linspace(thx[0], thx[-1], nx)
    gy = np.linspace(thy[0], thy[-1], ny)
    return gx, gy, _chart(gx, gy, t_hi + r_hi)


def plot_frames(thx, thy, t_frac, r_frac, dest):
    extent = [thx[0], thx[-1], thy[0], thy[-1]]
    fig, axes = plt.subplots(1, 2, figsize=(9.4, 4.6))
    for ax, img, title in (
        (axes[0], _chart(thx, thy, t_frac), "T / back  (image −X)"),
        (axes[1], _chart(thx, thy, r_frac), "R / side  (image +X)"),
    ):
        ax.imshow(img, origin="lower", extent=extent, aspect="auto")
        ax.set_xlabel("object X (mm)")
        ax.set_ylabel("object Y (mm)")
        ax.set_title(title)
    fig.suptitle(
        f"{EL_NAME}  f={EL_F} mm at f/{EL_FNUM:g}  ·  object {S_OBJ:.0f} mm  "
        f"(m={MAG:.2f}, close-up only)"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def plot_pano(thx, thy, t_frac, r_frac, dest):
    gx, gy, pano = stitch_pano(thx, thy, t_frac, r_frac)
    fig, ax = plt.subplots(figsize=(10.2, 3.4))
    ax.imshow(pano, origin="lower", extent=[gx[0], gx[-1], gy[0], gy[-1]], aspect="auto")
    ax.axvline(0.0, color="white", ls=":", lw=0.8, alpha=0.7)
    ax.set_xlabel("object X (mm)")
    ax.set_ylabel("object Y (mm)")
    obj_stitch = STITCH_W / MAG
    obj_single = SENSOR_W / MAG
    ax.set_title(
        f"{EL_NAME} stitch  {obj_stitch:.1f} mm object / {STITCH_W:.1f} mm image  "
        f"vs one DX {obj_single:.1f} mm object"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=160)
    plt.close(fig)


def main():
    sys_r = reflect_system()
    sys_t_fan = transmit_system(focal=False)
    sys_t = transmit_system(focal=True)

    rows = trace_fan(sys_r, sys_t_fan)
    paths = OUT / "preview_paths.png"
    frames = OUT / "preview_frames.png"
    plot_paths(rows, paths)

    thx, thy, t_frac, r_frac, counts = trace_frames(sys_t)
    plot_frames(thx, thy, t_frac, r_frac, frames)
    pano = OUT / "preview_pano.png"
    plot_pano(thx, thy, t_frac, r_frac, pano)

    t_on = thx[t_frac.max(axis=0) > 0.15]
    r_on = thx[r_frac.max(axis=0) > 0.15]
    both = np.concatenate([t_on, r_on]) if len(t_on) + len(r_on) else np.array([0.0])
    span = float(both.max() - both.min()) if both.size else 0.0
    obj_single = SENSOR_W / MAG
    ratio = span / obj_single if obj_single else 0.0
    pano_fov = 2.0 * np.degrees(np.arctan((span / 2.0) / S_OBJ)) if span else 0.0
    print(
        f"{EL_NAME}  f={EL_F} mm  f/{EL_FNUM:g}  S_OBJ={S_OBJ:.1f} mm  "
        f"S_PRIME={S_PRIME:.1f} mm  m={MAG:.2f}"
    )
    print(f"PATH_TOTAL={PATH_TOTAL} mm  stitch_w={STITCH_W:.1f} mm")
    print(
        "fields: "
        f"T-only={counts['left']}  overlap={counts['overlap']}  "
        f"R-only={counts['right']}  none={counts['none']}"
    )
    print(
        f"object single={obj_single:.2f} mm  pano span={span:.2f} mm  "
        f"ratio={ratio:.2f}x"
    )
    print(
        f"object FOV single={SINGLE_FOV:.2f} deg  pano={pano_fov:.2f} deg"
    )
    print(paths)
    print(frames)
    print(pano)
    if counts["left"] == 0 or counts["right"] == 0 or counts["overlap"] == 0:
        raise SystemExit("split failed: need unique-left, overlap, and unique-right")
    if ratio < 1.6:
        raise SystemExit(f"not a pano: span/single={ratio:.2f} (need >= 1.6)")


if __name__ == "__main__":
    main()
