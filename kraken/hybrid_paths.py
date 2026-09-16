#!/usr/bin/env python3
"""Trace the hybrid L pano in KrakenOS.

Each DX sensor is aimed at a different half of a stitch_w image
(sensor_shift). Writes kraken/preview_*.png for the El-Nikkor 50/2.8
(close-up, object ~73 mm), docs/kraken/el135_*.png for the 135/5.6
(~0.61 m), and docs/kraken/el180_*.png for the 180/5.6 at 50 m
(infinity helicoid).
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
D_LENS_TO_PLATE_BOX = 55.0
D_LENS_TO_PLATE = D_LENS_TO_PLATE_BOX
D_PLATE_TO_MOUNT = 72.0
PATH_TOTAL = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT + FLANGE_F
PATH_AFTER = D_PLATE_TO_MOUNT + FLANGE_F
SENSOR_W = 23.6
SENSOR_H = 15.6
OVERLAP_FRAC = 0.20
TUBE_ID = 52.0
JUNCTION_BOX = 90.0
WAVE = 0.55

S_PRIME = PATH_TOTAL
EL_NAME = "EL-Nikkor 50/2.8"
EL_F = 51.6
EL_FNUM = 5.6
EL_EPD = EL_F / EL_FNUM
S_OBJ = 1.0 / (1.0 / EL_F - 1.0 / S_PRIME)
MAG = S_PRIME / S_OBJ


def apply_helicoid(extra=0.0):
    """extra mm of helicoid on the stem (6.5 mm → 180 mm at infinity)."""
    global D_LENS_TO_PLATE, PATH_TOTAL, PATH_AFTER, S_PRIME
    D_LENS_TO_PLATE = D_LENS_TO_PLATE_BOX + float(extra)
    PATH_AFTER = D_PLATE_TO_MOUNT + FLANGE_F
    PATH_TOTAL = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT + FLANGE_F
    S_PRIME = PATH_TOTAL


def apply_lens(name, f, fnum, s_obj=None):
    global EL_NAME, EL_F, EL_FNUM, EL_EPD, S_OBJ, MAG, S_PRIME
    global SINGLE_FOV, PANO_FOV
    EL_NAME = name
    EL_F = float(f)
    EL_FNUM = float(fnum)
    EL_EPD = EL_F / EL_FNUM
    if s_obj is None:
        S_PRIME = PATH_TOTAL
        S_OBJ = 1.0 / (1.0 / EL_F - 1.0 / S_PRIME)
    else:
        S_OBJ = float(s_obj)
        S_PRIME = 1.0 / (1.0 / EL_F - 1.0 / S_OBJ)
    MAG = S_PRIME / S_OBJ
    SINGLE_FOV = 2.0 * np.degrees(np.arctan(HALF_W / S_PRIME))
    PANO_FOV = 2.0 * np.degrees(np.arctan(STITCH_W / 2.0 / S_PRIME))


def helicoid_extra(f, s_obj):
    """Helicoid rack so S_PRIME matches the (f, s_obj) conjugate."""
    s_prime = 1.0 / (1.0 / float(f) - 1.0 / float(s_obj))
    return s_prime - (D_LENS_TO_PLATE_BOX + D_PLATE_TO_MOUNT + FLANGE_F)


def obj_unit():
    """Axis scale for object-plane plots (mm, or m when the field is landscape)."""
    if S_OBJ >= 1000.0:
        return 0.001, "m"
    return 1.0, "mm"


def apply_chassis(flange=46.5, sensor_w=23.6, sensor_h=15.6):
    """D7000 DX is the default. 5D Mk III: flange=44, 36×24. A7: flange=18, 35.8×23.9."""
    global FLANGE_F, PATH_TOTAL, PATH_AFTER, S_PRIME
    global SENSOR_W, SENSOR_H, SHIFT, HALF_W, HALF_H, OL_W, STITCH_W
    global SINGLE_FOV, PANO_FOV
    FLANGE_F = float(flange)
    SENSOR_W = float(sensor_w)
    SENSOR_H = float(sensor_h)
    PATH_AFTER = D_PLATE_TO_MOUNT + FLANGE_F
    PATH_TOTAL = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT + FLANGE_F
    S_PRIME = PATH_TOTAL
    SHIFT = SENSOR_W / 2.0 * (1.0 - OVERLAP_FRAC)
    HALF_W = SENSOR_W / 2.0
    HALF_H = SENSOR_H / 2.0
    OL_W = SENSOR_W * OVERLAP_FRAC / 2.0
    STITCH_W = SENSOR_W * (2.0 - OVERLAP_FRAC)
    SINGLE_FOV = 2.0 * np.degrees(np.arctan(HALF_W / PATH_TOTAL))
    PANO_FOV = 2.0 * np.degrees(np.arctan(STITCH_W / 2.0 / PATH_TOTAL))
    apply_lens(EL_NAME, EL_F, EL_FNUM)

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
    sc, unit = obj_unit()
    extent = [thx[0] * sc, thx[-1] * sc, thy[0] * sc, thy[-1] * sc]
    fig, axes = plt.subplots(1, 2, figsize=(9.4, 4.6))
    for ax, img, title in (
        (axes[0], _chart(thx, thy, t_frac), "T / back  (image −X)"),
        (axes[1], _chart(thx, thy, r_frac), "R / side  (image +X)"),
    ):
        ax.imshow(img, origin="lower", extent=extent, aspect="auto")
        ax.set_xlabel(f"object X ({unit})")
        ax.set_ylabel(f"object Y ({unit})")
        ax.set_title(title)
    dist = f"{S_OBJ / 1000.0:.0f} m" if S_OBJ >= 1000.0 else f"{S_OBJ:.0f} mm"
    fig.suptitle(
        f"{EL_NAME}  f={EL_F:g} mm at f/{EL_FNUM:g}  ·  object {dist}  "
        f"(m={MAG:.3f})"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def plot_pano(thx, thy, t_frac, r_frac, dest):
    gx, gy, pano = stitch_pano(thx, thy, t_frac, r_frac)
    sc, unit = obj_unit()
    fig, ax = plt.subplots(figsize=(10.2, 3.4))
    ax.imshow(pano, origin="lower",
              extent=[gx[0] * sc, gx[-1] * sc, gy[0] * sc, gy[-1] * sc],
              aspect="auto")
    ax.axvline(0.0, color="white", ls=":", lw=0.8, alpha=0.7)
    ax.set_xlabel(f"object X ({unit})")
    ax.set_ylabel(f"object Y ({unit})")
    obj_stitch = STITCH_W / MAG
    obj_single = SENSOR_W / MAG
    ax.set_title(
        f"{EL_NAME} stitch  {obj_stitch * sc:.1f} {unit} object / {STITCH_W:.1f} mm image  "
        f"vs one DX {obj_single * sc:.1f} {unit} object"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=160)
    plt.close(fig)


def run_lens(dest_dir, prefix, do_paths=False, require=True):
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    sys_t = transmit_system(focal=True)
    if do_paths:
        rows = trace_fan(reflect_system(), transmit_system(focal=False))
        plot_paths(rows, dest_dir / f"{prefix}paths.png")
        print(dest_dir / f"{prefix}paths.png")

    thx, thy, t_frac, r_frac, counts = trace_frames(sys_t)
    frames = dest_dir / f"{prefix}frames.png"
    pano = dest_dir / f"{prefix}pano.png"
    plot_frames(thx, thy, t_frac, r_frac, frames)
    plot_pano(thx, thy, t_frac, r_frac, pano)

    t_on = thx[t_frac.max(axis=0) > 0.15]
    r_on = thx[r_frac.max(axis=0) > 0.15]
    both = np.concatenate([t_on, r_on]) if len(t_on) + len(r_on) else np.array([0.0])
    span = float(both.max() - both.min()) if both.size else 0.0
    obj_single = SENSOR_W / MAG
    ratio = span / obj_single if obj_single else 0.0
    pano_fov = 2.0 * np.degrees(np.arctan((span / 2.0) / S_OBJ)) if span else 0.0
    mag_s = f"{MAG:.4f}" if MAG < 0.01 else f"{MAG:.2f}"
    sc, unit = obj_unit()
    dist = f"{S_OBJ / 1000.0:.0f} m" if S_OBJ >= 1000.0 else f"{S_OBJ:.1f} mm"
    print(
        f"{EL_NAME}  f={EL_F:g} mm  f/{EL_FNUM:g}  S_OBJ={dist}  "
        f"S_PRIME={S_PRIME:.1f} mm  m={mag_s}"
    )
    print(f"PATH_TOTAL={PATH_TOTAL:.1f} mm  stitch_w={STITCH_W:.1f} mm")
    print(
        "fields: "
        f"T-only={counts['left']}  overlap={counts['overlap']}  "
        f"R-only={counts['right']}  none={counts['none']}"
    )
    print(
        f"object single={obj_single * sc:.2f} {unit}  pano span={span * sc:.2f} {unit}  "
        f"ratio={ratio:.2f}x"
    )
    print(f"object FOV single={SINGLE_FOV:.2f} deg  pano={pano_fov:.2f} deg")
    print(frames)
    print(pano)
    if not require:
        return
    if counts["left"] == 0 or counts["right"] == 0 or counts["overlap"] == 0:
        raise SystemExit("split failed: need unique-left, overlap, and unique-right")
    if ratio < 1.6:
        raise SystemExit(f"not a pano: span/single={ratio:.2f} (need >= 1.6)")


def main():
    apply_lens("EL-Nikkor 50/2.8", 51.6, 5.6)
    run_lens(OUT, "preview_", do_paths=True)
    # Recommended taking lens: same L39 as the 50, 4×5 coverage, ~$80–150 used.
    apply_lens("EL-Nikkor 135/5.6", 135.0, 5.6)
    docs = OUT.parent / "docs" / "kraken"
    run_lens(docs, "el135_", do_paths=True)
    # Landscape: 50 m, helicoid out so PATH = 180.7 mm (∞ is +6.5 mm).
    s_obj_180 = 50_000.0
    apply_helicoid(helicoid_extra(180.0, s_obj_180))
    apply_lens("EL-Nikkor 180/5.6", 180.0, 5.6, s_obj=s_obj_180)
    run_lens(docs, "el180_", do_paths=True)
    apply_helicoid(0.0)
    run_d800_180(docs)


# D800 FX, same F-mount path as D7000. 36×23.9, 7360×4912.
def run_d800_180(docs=None):
    docs = Path(docs) if docs is not None else OUT.parent / "docs" / "kraken"
    s_obj_180 = 50_000.0
    apply_chassis(46.5, 36.0, 23.9)
    apply_helicoid(helicoid_extra(180.0, s_obj_180))
    apply_lens("EL-Nikkor 180/5.6", 180.0, 5.6, s_obj=s_obj_180)
    run_lens(docs, "el180_d800_", do_paths=True)
    apply_helicoid(0.0)
    apply_chassis()


if __name__ == "__main__":
    main()
