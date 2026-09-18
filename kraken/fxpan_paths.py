#!/usr/bin/env python3
"""Trace FXPAN 65 in KrakenOS and check it against openscad/fxpan/params.scad.

Two D800 sensors behind one EL-Nikkor 180/5.6 and a 75 x 75 x 1 mm 50/50
plate at 45 deg. Each sensor takes one half of the field; the two frames
stitch to 64.80 x 23.9 mm. This script answers three questions:

  1. Does anything clip between f/5.6 and f/16?
  2. Does the stitch really span 64.80 mm at 20% overlap?
  3. Are the two shift senses opposite, so the sensors sample opposite
     halves of the field rather than the same one?

Writes docs/kraken/fxpan_*.png and exits non-zero if any answer is no.

A note on how the fold is handled, because it is not how the other
kraken scripts do it. KrakenOS's tilted-surface convention does not give
the right answer for either a 45 deg fold mirror or a tilted plate:

    obj -> thin lens f=180 -> image at 180        field 5 deg -> 15.748 mm
    obj -> thin lens f=180 -> 45 deg mirror       field 5 deg -> -3.674 mm
                              (AxisMove=2)        (should be 15.748)

The flat case is exact; the folded one is not, and a tilted 1 mm plate
with +45/-45 surfaces puts the axial ray 55 mm off centre instead of
0.303 mm. So reflect_system() in hybrid_paths.py draws a fold that does
not trace, and anything quantitative built on it would be wrong.

A plane fold is a rigid motion: it cannot change an image, only where
the image sits. So the imaging here is traced unfolded, where KrakenOS
is exact, and the fold enters only where it actually matters:

  - at the plate, as the 1/sqrt(2) foreshortening of the stitch axis
    (fold_basis() derives it from the real reflection matrix), and
  - in the sense of each camera's shift (fold_senses()).

Round bores are unaffected: a reflection preserves distance from the
axis, so the arm and flange apertures are tested in unfolded
coordinates directly.
"""

from __future__ import annotations

import contextlib
import io
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

import KrakenOS as Kos

# --- openscad/fxpan/params.scad ----------------------------------------------
EL_FOCAL = 180.0
FLANGE_F = 46.5
SENSOR_W = 36.0
SENSOR_H = 23.9
SENSOR_PX_W = 7360
SENSOR_PX_H = 4912
OVERLAP_FRAC = 0.20

BS_SIZE = 75.0
BS_THICK = 1.0
BS_N = 1.52

BOX_XY = 92.0
PORT_PATCH_T = 4.0
D800_PROUD = 13.0     # D800 front panel, past its own F flange
MOUNT_CLEAR = 3.0
F_REV_LEN = 8.0
F_REV_STACK = 8.0
ARM_TUBE = max(F_REV_LEN, D800_PROUD + MOUNT_CLEAR - F_REV_STACK)
TUBE_ID = 46.0
F_BORE = 44.0
F_REV_THROAT = 44.0   # metal M52 -> F reverse ring, the real F throat
F_STL_THROAT = 38.0   # printed bayonet mesh

EL180_M62_LEN = 8.0
EL180_HELI_MIN, EL180_HELI_MAX, EL180_HELI_MALE = 17.0, 31.0, 8.0

SHIFT = SENSOR_W / 2.0 * (1.0 - OVERLAP_FRAC)      # 14.40
STITCH_W = SENSOR_W * (2.0 - OVERLAP_FRAC)         # 64.80
STITCH_PX = round(SENSOR_PX_W * (2.0 - OVERLAP_FRAC))

D_PLATE_TO_MOUNT = BOX_XY / 2 + PORT_PATCH_T + ARM_TUBE + F_REV_STACK   # 66.0
D_PLATE_TO_SENSOR = D_PLATE_TO_MOUNT + FLANGE_F                         # 112.5
D_BOXWALL_TO_SENSOR = D_PLATE_TO_SENSOR - BOX_XY / 2                    # 66.5
D_LENS_TO_PLATE = EL_FOCAL - D_PLATE_TO_SENSOR                          # 67.5
# Air between the chassis face and the F register. The shell now stops at the
# cookie face, so this is the arm tube plus the reverse ring and nothing else,
# and it is what a D800's protruding front panel has to fit into.
MOUNT_STANDOFF = ARM_TUBE + F_REV_STACK                                 # 16.0

WAVE = 0.55
S_OBJ = 50_000.0
FSTOPS = (5.6, 8.0, 11.0, 16.0)

OUT = Path(__file__).resolve().parent
DOCS = OUT.parent / "docs" / "kraken"


# --- the fold, from the reflection matrix itself ------------------------------
def reflect(d, n):
    d = np.asarray(d, float)
    n = np.asarray(n, float)
    n = n / np.linalg.norm(n)
    return d - 2.0 * np.dot(d, n) * n


def fold_basis():
    """Plate normal, and the stitch axis foreshortening it costs.

    Chassis frame: lens on -Y looking +Y, reflect leg out +X, vertical +Z.
    The plate normal is whatever sends +Y to +X. The stitch axis is the
    sensors' horizontal, and cam/pano.py needs a horizontal seam, so it
    is the chassis X of the incoming beam -- which is exactly the
    direction the tilted plate foreshortens.
    """
    n = np.array([-1.0, 1.0, 0.0]) / np.sqrt(2.0)
    assert np.allclose(reflect([0, 1, 0], n), [1, 0, 0]), "plate does not fold +Y to +X"
    u = np.array([1.0, 0.0, 0.0])   # stitch axis, incoming beam
    v = np.array([0.0, 0.0, 1.0])   # vertical
    assert np.allclose(reflect(v, n), v), "fold is not in the horizontal plane"
    # In-plane extent the plate presents per mm of beam offset along u, v.
    # A beam offset e lands on the plate at e / |e_perp to n|.
    stretch_u = 1.0 / np.sqrt(1.0 - np.dot(u, n) ** 2)
    stretch_v = 1.0 / np.sqrt(1.0 - np.dot(v, n) ** 2)
    return n, stretch_u, stretch_v


def fold_senses():
    """Where each camera's bore offset lands on the incoming stitch axis.

    params.scad puts cam_axis("R") at chassis [0, -s] and cam_axis("T") at
    [s, 0]. Those are on different faces, so "opposite" is not obvious by
    inspection -- push each one back through the fold and compare.
    """
    n, _, _ = fold_basis()
    u = np.array([1.0, 0.0, 0.0])
    # Reflect leg: the incoming stitch axis u becomes this in the R leg.
    u_r = reflect(u, n)
    # R's bore sits at chassis [0, -s]: project onto u_r to read its u.
    u_of_r = float(np.dot(np.array([0.0, -SHIFT, 0.0]), u_r))
    # Transmit leg is unfolded, so u is still u.
    u_of_t = float(np.dot(np.array([SHIFT, 0.0, 0.0]), u))
    return u_of_r, u_of_t


# --- KrakenOS: the unfolded 180 mm system ------------------------------------
def _quiet(surfaces):
    with contextlib.redirect_stdout(io.StringIO()):
        return Kos.system(surfaces, Kos.Setup())


def system(fstop):
    """Object at 50 m, thin lens f=180 stopped to f/N, sensor at 180 mm.

    The lens Diameter is the aperture stop, so KrakenOS drops rays that
    miss it and never reports them at the image.
    """
    obj = Kos.surf()
    obj.Thickness = S_OBJ
    obj.Glass = "AIR"
    obj.Diameter = 2.2 * STITCH_W / (EL_FOCAL / S_OBJ)
    obj.Drawing = 0
    obj.Name = "object"
    lens = Kos.surf()
    lens.Name = "lens"
    lens.Thin_Lens = EL_FOCAL
    lens.Diameter = EL_FOCAL / fstop
    lens.Glass = "AIR"
    lens.Thickness = 1.0 / (1.0 / EL_FOCAL - 1.0 / S_OBJ)
    ima = Kos.surf()
    ima.Name = "sensor"
    ima.Glass = "AIR"
    ima.Diameter = 4.0 * STITCH_W
    return _quiet([obj, lens, ima])


S_PRIME = 1.0 / (1.0 / EL_FOCAL - 1.0 / S_OBJ)   # 180.65 at 50 m


def check_kraken_is_exact():
    """The unfolded system must reproduce s'*tan(theta) before we trust it."""
    s = system(5.6)
    for deg in (2.0, 5.0):
        a = np.radians(deg)
        s.Trace([-S_OBJ * np.tan(a), 0.0, 0.0],
                [np.sin(a), 0.0, np.cos(a)], WAVE)
        got = float(np.atleast_2d(np.asarray(s.OST_XYZ, float))[-1][0])
        want = S_PRIME * np.tan(a)
        if abs(got - want) > 0.01:
            raise SystemExit(
                f"KrakenOS unfolded trace is off at {deg} deg: "
                f"{got:.4f} vs {want:.4f} mm"
            )


def pupil_disc(fstop, rings=4):
    """Hex-ish sampling of the real pupil, so vignetting comes out as a fraction."""
    r_max = 0.995 * (EL_FOCAL / fstop) / 2.0
    pts = [(0.0, 0.0)]
    for i in range(1, rings + 1):
        r = r_max * i / rings
        n = 6 * i
        for k in range(n):
            a = 2 * np.pi * k / n
            pts.append((r * np.cos(a), r * np.sin(a)))
    return pts


def _segment(s):
    """Transverse (x, y) of the traced ray as a function of distance from the sensor."""
    xyz = np.atleast_2d(np.asarray(s.XYZ, float))
    if xyz.shape[0] < 3:
        return None
    p_lens, p_ima = xyz[-2], xyz[-1]
    z_ima = p_ima[2]

    def at(d):
        z = z_ima - d
        dz = p_ima[2] - p_lens[2]
        if abs(dz) < 1e-9:
            return p_lens[0], p_lens[1]
        t = (z - p_lens[2]) / dz
        return (p_lens[0] + t * (p_ima[0] - p_lens[0]),
                p_lens[1] + t * (p_ima[1] - p_lens[1]))

    return at


def on_window(x, y, axis):
    return abs(x - axis) <= SENSOR_W / 2 + EPS and abs(y) <= SENSOR_H / 2 + EPS


# --- the apertures a ray has to survive --------------------------------------
_, STRETCH_U, STRETCH_V = fold_basis()
U_OF_R, U_OF_T = fold_senses()
AXIS_R = round(U_OF_R, 9)      # -14.40: R samples the -u half
AXIS_T = round(U_OF_T, 9)      # +14.40

# A ray landing exactly on a window edge or an aperture rim is on it; without
# this the exact grid points at +-32.4 come out as 70% lit from float noise.
EPS = 1e-6


def plate_passes(at):
    x, y = at(D_PLATE_TO_SENSOR)
    return (abs(x) * STRETCH_U <= BS_SIZE / 2 + EPS
            and abs(y) * STRETCH_V <= BS_SIZE / 2 + EPS)


def bore_passes(at, axis, throat):
    for d, dia in ((D_BOXWALL_TO_SENSOR, TUBE_ID),
                   (FLANGE_F + 2.0, F_BORE),
                   (FLANGE_F, throat)):
        x, y = at(d)
        if np.hypot(x - axis, y) > dia / 2 + EPS:
            return False
    return True


def field_grid(nu=33, nv=9):
    """Sample grid that lands exactly on the edges we are testing.

    Those are the frame edges at +-stitch_w/2 and the overlap seam edges
    at +-(shift - sensor_w/2), plus a few stations past the frame to
    confirm nothing outside it is claimed as lit.
    """
    edges = [-STITCH_W / 2, STITCH_W / 2,
             AXIS_R + SENSOR_W / 2, AXIS_T - SENSOR_W / 2]
    us = np.unique(np.round(np.concatenate([
        np.linspace(-STITCH_W / 2, STITCH_W / 2, nu),
        edges,
        [-STITCH_W / 2 - 3, -STITCH_W / 2 - 1.2,
         STITCH_W / 2 + 1.2, STITCH_W / 2 + 3],
    ]), 6))
    vs = np.unique(np.round(np.concatenate([
        np.linspace(-SENSOR_H / 2, SENSOR_H / 2, nv),
        [-SENSOR_H / 2 - 1.0, SENSOR_H / 2 + 1.0],
    ]), 6))
    return us, vs


def trace(fstop, throat=F_REV_THROAT):
    """Field grid x pupil disc. Returns per-camera illumination fractions."""
    s = system(fstop)
    # u and v are image-plane millimetres, so MAG has to be the real
    # conjugate magnification -- at 50 m that is 180.65/50000, not 180/50000,
    # and using the latter pushes the frame edge 0.12 mm off the sensor.
    mag = S_PRIME / S_OBJ
    us, vs = field_grid()
    pupils = pupil_disc(fstop)
    n_p = len(pupils)
    z_lens = S_OBJ

    r_frac = np.zeros((len(vs), len(us)))
    t_frac = np.zeros_like(r_frac)
    # Only rays aimed inside the 64.80 x 23.9 frame are counted as losses;
    # the grid deliberately reaches past it.
    stops = {"stop": 0, "plate": 0, "bore_r": 0, "bore_t": 0}

    for iu, u in enumerate(us):
        for iv, v in enumerate(vs):
            wanted = abs(u) <= STITCH_W / 2 + 1e-6 and abs(v) <= SENSOR_H / 2 + 1e-6
            src = np.array([-u / mag, -v / mag, 0.0])
            n_r = n_t = 0
            for px, py in pupils:
                aim = np.array([px, py, z_lens]) - src
                aim = aim / np.linalg.norm(aim)
                s.Trace(src.tolist(), aim.tolist(), WAVE)
                try:
                    reached = "sensor" in list(s.NAME)
                except TypeError:
                    reached = False
                at = _segment(s) if reached else None
                if at is None:
                    if wanted:
                        stops["stop"] += 1
                    continue
                if not plate_passes(at):
                    if wanted:
                        stops["plate"] += 1
                    continue
                xi, yi = at(0.0)
                if on_window(xi, yi, AXIS_R):
                    if bore_passes(at, AXIS_R, throat):
                        n_r += 1
                    elif wanted:
                        stops["bore_r"] += 1
                if on_window(xi, yi, AXIS_T):
                    if bore_passes(at, AXIS_T, throat):
                        n_t += 1
                    elif wanted:
                        stops["bore_t"] += 1
            r_frac[iv, iu] = n_r / n_p
            t_frac[iv, iu] = n_t / n_p
    return us, vs, r_frac, t_frac, stops


# --- what the geometry says, for comparison ----------------------------------
def measure(us, vs, r_frac, t_frac):
    """Worst illumination on each window, plus the lit span and the overlap.

    Corner and mid-height are reported separately because they fail at
    different apertures. The stitch axis runs along v = 0 and is never the
    thing that clips; the corners are, because a round bore cares about
    distance from its axis and the frame corner is 21.6 mm out against the
    stitch axis's 18.
    """
    in_v = np.abs(vs) <= SENSOR_H / 2 + EPS
    mid = np.argmin(np.abs(vs))
    win_r = np.abs(us - AXIS_R) <= SENSOR_W / 2 + EPS
    win_t = np.abs(us - AXIS_T) <= SENSOR_W / 2 + EPS
    frame = min(float(r_frac[np.ix_(in_v, win_r)].min()),
                float(t_frac[np.ix_(in_v, win_t)].min()))
    mid_min = min(float(r_frac[mid, win_r].min()),
                  float(t_frac[mid, win_t].min()))
    # Stitch geometry, read along v = 0 so corner vignetting does not hide it.
    lit = np.clip(r_frac[mid] + t_frac[mid], 0.0, 1.0) >= 0.999
    span = float(us[lit].max() - us[lit].min()) if lit.any() else 0.0
    ov = (r_frac[mid] >= 0.999) & (t_frac[mid] >= 0.999)
    overlap = float(us[ov].max() - us[ov].min()) if ov.any() else 0.0
    return {"frame": frame, "mid": mid_min, "span": span, "overlap": overlap}


def need_bore_2d(fstop, b, shift=SHIFT):
    """Corner-aware bore, matching need_bore() in params.scad."""
    al, be = (EL_FOCAL - b) / EL_FOCAL, b / EL_FOCAL
    cu = SENSOR_W / 2 * al + shift * be
    cv = SENSOR_H / 2 * al
    return 2 * (np.hypot(cu, cv) + (EL_FOCAL / fstop) / 2 * be)


def need_bore_1d(fstop, b):
    """The stitch-axis-only version, which is what understated the bore."""
    return 2 * (SENSOR_W / 2 * (EL_FOCAL - b) / EL_FOCAL
                + (b / EL_FOCAL) * ((EL_FOCAL / fstop) / 2 + SHIFT))


def clean_from(b, have):
    """Widest aperture that puts the frame corners through a bore of `have`."""
    floor = need_bore_2d(1e9, b)
    if have <= floor:
        return None
    lo, hi = 1.0, 1e6
    for _ in range(200):
        m = (lo + hi) / 2
        if need_bore_2d(m, b) > have:
            lo = m
        else:
            hi = m
    return hi


def bundle_r(ym, fstop, d):
    return ym * (EL_FOCAL - d) / EL_FOCAL + (EL_FOCAL / fstop) / 2 * (d / EL_FOCAL)


def need_clear(fstop, d):
    return 2 * bundle_r(STITCH_W / 2, fstop, d)


def need_bore(fstop, b):
    return 2 * (SENSOR_W / 2 * (EL_FOCAL - b) / EL_FOCAL
                + (b / EL_FOCAL) * ((EL_FOCAL / fstop) / 2 + SHIFT))


def bs_t_comp():
    ti = np.radians(45.0)
    tt = np.arcsin(np.sin(ti) / BS_N)
    return BS_THICK * (BS_N / np.cos(tt) - 1 / np.cos(ti))


# --- plots -------------------------------------------------------------------
def _chart(us, frac, rgb):
    return np.clip(frac[..., None] * np.asarray(rgb, float), 0.0, 1.0)


def plot_frames(us, vs, r_frac, t_frac, fstop, dest):
    extent = [us[0], us[-1], vs[0], vs[-1]]
    fig, axes = plt.subplots(2, 1, figsize=(9.6, 5.0), sharex=True)
    for ax, frac, rgb, name, axis in (
        (axes[0], t_frac, (0.45, 0.70, 0.95), "T  (transmit, +Y)", AXIS_T),
        (axes[1], r_frac, (0.95, 0.55, 0.40), "R  (reflect, +X)", AXIS_R),
    ):
        ax.imshow(_chart(us, frac, rgb), origin="lower", extent=extent, aspect="auto")
        ax.axvline(axis, color="white", ls=":", lw=0.9)
        ax.set_ylabel("field v (mm)")
        ax.set_title(f"{name}   window centre u = {axis:+.2f} mm", fontsize=9)
    axes[1].set_xlabel("field u on the stitch axis (mm at the sensor)")
    fig.suptitle(
        f"FXPAN 65 at f/{fstop:g}  —  each sensor's illumination across the "
        f"{STITCH_W:.2f} mm field"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def plot_pano(us, vs, r_frac, t_frac, fstop, dest):
    both = np.clip(r_frac + t_frac, 0.0, 1.0)
    hue = (us - us[0]) / (us[-1] - us[0])
    stripe = plt.cm.turbo(np.broadcast_to(hue, both.shape))[..., :3]
    img = np.clip(stripe * both[..., None], 0.0, 1.0)
    fig, ax = plt.subplots(figsize=(10.4, 3.0))
    ax.imshow(img, origin="lower", extent=[us[0], us[-1], vs[0], vs[-1]],
              aspect="auto")
    for e in (-STITCH_W / 2, STITCH_W / 2):
        ax.axvline(e, color="white", ls="--", lw=1.0)
    ax.axvline(0.0, color="white", ls=":", lw=0.7, alpha=0.6)
    ax.set_xlabel("stitched field u (mm)")
    ax.set_ylabel("v (mm)")
    ax.set_title(
        f"FXPAN 65 stitch at f/{fstop:g}  —  {STITCH_W:.2f} x {SENSOR_H} mm, "
        f"{STITCH_W / SENSOR_H:.3f}:1, {STITCH_PX} x {SENSOR_PX_H}"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=160)
    plt.close(fig)


def plot_margins(dest):
    stops = np.linspace(4.0, 22.0, 200)
    fig, axes = plt.subplots(1, 2, figsize=(10.4, 4.2))
    ax = axes[0]
    ax.plot(stops, [need_clear(n, D_PLATE_TO_SENSOR) for n in stops],
            color="black", lw=1.6, label="needed across the fold")
    ax.axhline(BS_SIZE / np.sqrt(2), color="seagreen", lw=1.8,
               label=f"{BS_SIZE:g} mm plate = {BS_SIZE / np.sqrt(2):.2f} mm")
    ax.axhline(50 / np.sqrt(2), color="indianred", lw=1.8, ls="--",
               label=f"50 mm plate = {50 / np.sqrt(2):.2f} mm")
    ax.set_xlabel("f-number")
    ax.set_ylabel("clear aperture in the plate's plane (mm)")
    ax.set_title("Plate", fontsize=10)
    ax.legend(frameon=False, fontsize=8)

    ax = axes[1]
    ax.plot(stops, [need_bore_2d(n, FLANGE_F) for n in stops],
            color="black", lw=1.8, label="frame corner, at the F flange")
    ax.plot(stops, [need_bore_1d(n, FLANGE_F) for n in stops],
            color="black", lw=1.2, ls=":",
            label="stitch axis only (understates it)")
    ax.plot(stops, [need_bore_2d(n, D_BOXWALL_TO_SENSOR) for n in stops],
            color="0.55", lw=1.4, ls="-.", label="frame corner, at the box wall")
    ax.axhline(F_REV_THROAT, color="seagreen", lw=1.8,
               label=f"metal reverse ring {F_REV_THROAT:g} mm")
    ax.axhline(TUBE_ID, color="steelblue", lw=1.4, ls=":",
               label=f"TUBE_ID {TUBE_ID:g} mm")
    ax.axhline(F_STL_THROAT, color="indianred", lw=1.8, ls="--",
               label=f"printed F mesh {F_STL_THROAT:g} mm")
    ring = clean_from(FLANGE_F, F_REV_THROAT)
    if ring:
        ax.axvline(ring, color="seagreen", lw=1.0, alpha=0.5)
        ax.annotate(f"corners clean\nfrom f/{ring:.1f}", (ring, 47.5),
                    fontsize=8, color="seagreen", ha="left")
    ax.set_xlabel("f-number")
    ax.set_ylabel("bore about the camera axis (mm)")
    ax.set_title("Camera leg — the binding constraint", fontsize=10)
    ax.legend(frameon=False, fontsize=8)

    fig.suptitle("FXPAN 65 — what has to pass, against what is there")
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def plot_layout(dest):
    """Plan view of the real folded chassis, with the traced envelope on it."""
    fig, ax = plt.subplots(figsize=(8.4, 7.4))
    half = BOX_XY / 2
    ax.plot([-half, half, half, -half, -half],
            [-half, -half, half, half, -half],
            color="0.75", lw=1.2, label=f"{BOX_XY:g} mm chamber")

    # Folded optical axis: lens in on -Y, transmit on to +Y, reflect out to +X.
    ax.plot([0, 0], [-half - 45, 0], color="0.45", lw=1.0, ls="--")
    ax.plot([0, 0], [0, D_PLATE_TO_SENSOR], color="steelblue", lw=1.0, ls="--")
    ax.plot([0, D_PLATE_TO_SENSOR], [0, 0], color="indianred", lw=1.0, ls="--")
    ax.annotate("EL-Nikkor 180\non an M62 helicoid", (0, -half - 47),
                ha="center", va="top", fontsize=8, color="0.3")

    span = (BS_SIZE / 2) / np.sqrt(2)
    ax.plot([-span, span], [span, -span], color="goldenrod", lw=5.0,
            solid_capstyle="butt",
            label=f"{BS_SIZE:g} mm plate, S1 to the lens ({2 * span:.1f} mm across)")
    # What the bundle actually asks of the plate, drawn just off it so both
    # apertures stay visible against the gold.
    for fstop, off, style in ((5.6, 3.0, "-"), (16.0, 6.0, ":")):
        r = need_clear(fstop, D_PLATE_TO_SENSOR) / 2
        o = off / np.sqrt(2)
        ax.plot([-r + o, r + o], [r + o, -r + o], color="crimson", ls=style,
                lw=1.6, label=f"needs {2 * r:.1f} mm at f/{fstop:g}")

    for name, axis_xy, u_dir, colour in (
        (f"T sensor, axis at x = {SHIFT:+.1f}", (SHIFT, D_PLATE_TO_SENSOR),
         (1, 0), "steelblue"),
        (f"R sensor, axis at y = {-SHIFT:+.1f}", (D_PLATE_TO_SENSOR, -SHIFT),
         (0, 1), "indianred"),
    ):
        cx, cy = axis_xy
        ux, uy = u_dir
        ax.plot([cx - ux * SENSOR_W / 2, cx + ux * SENSOR_W / 2],
                [cy - uy * SENSOR_W / 2, cy + uy * SENSOR_W / 2],
                color=colour, lw=4.0, solid_capstyle="butt", label=name)
        ax.plot([cx], [cy], marker="o", ms=5, color=colour, zorder=5)

    ax.set_aspect("equal")
    ax.set_xlabel("chassis X (mm)   reflect leg +X")
    ax.set_ylabel("chassis Y (mm)   lens −Y, transmit leg +Y")
    ax.set_title("FXPAN 65 — plan view, plate at the origin.  The two sensor "
                 "axes shift in\nopposite senses, so each takes one half of "
                 "the field.", fontsize=10)
    ax.legend(loc="upper right", frameon=False, fontsize=8)
    ax.set_xlim(-half - 15, D_PLATE_TO_SENSOR + 30)
    ax.set_ylim(-half - 62, D_PLATE_TO_SENSOR + 22)
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


# --- report ------------------------------------------------------------------
def main():
    DOCS.mkdir(parents=True, exist_ok=True)
    check_kraken_is_exact()
    fails = []

    print("FXPAN 65 — KrakenOS check against openscad/fxpan/params.scad")
    print(f"  plate {BS_SIZE:g} x {BS_SIZE:g} x {BS_THICK:g} mm, 45 deg, n={BS_N}")
    print(f"  lens flange to plate {D_LENS_TO_PLATE:.1f}, plate to sensor "
          f"{D_PLATE_TO_SENSOR:.1f}, path {EL_FOCAL:.1f} mm")
    print(f"  plate foreshortens the stitch axis by {STRETCH_U:.4f} "
          f"and the vertical by {STRETCH_V:.4f}")
    print("  (unfolded KrakenOS trace reproduces f*tan(theta) to 0.02 mm)")

    # 1. shift senses
    print("\nshift senses")
    print(f"  R bore at chassis [0, {-SHIFT:+.2f}]  ->  field u = {U_OF_R:+.2f} mm")
    print(f"  T bore at chassis [{SHIFT:+.2f}, 0]  ->  field u = {U_OF_T:+.2f} mm")
    if U_OF_R * U_OF_T >= 0:
        fails.append("shift senses are not opposite: both sensors sample the same half")
    else:
        print("  opposite -> the sensors sample opposite halves.  OK")
    print("  R takes one reflection and T none, so exactly one frame is "
          "mirrored; that is flip_r in cam/pano.py.")

    # 2. stitch geometry
    print("\nstitch geometry at 20% overlap")
    print(f"  shift {SHIFT:.2f} mm, span {STITCH_W:.2f} x {SENSOR_H} mm, "
          f"{STITCH_W / SENSOR_H:.4f}:1  (XPan 65/24 = {65 / 24:.4f}:1)")
    print(f"  {STITCH_PX} x {SENSOR_PX_H} = "
          f"{STITCH_PX * SENSOR_PX_H / 1e6:.1f} MP")
    print(f"  field {2 * np.degrees(np.arctan(STITCH_W / 2 / EL_FOCAL)):.1f} x "
          f"{2 * np.degrees(np.arctan(SENSOR_H / 2 / EL_FOCAL)):.1f} deg")

    # 3. can the camera physically go on
    print("\nbody fit")
    print(f"  arm tube {ARM_TUBE:.1f} + reverse ring {F_REV_STACK:.1f} = "
          f"{MOUNT_STANDOFF:.1f} mm from the chassis face to the F register")
    print(f"  a D800 front panel stands {D800_PROUD:.1f} mm past its own "
          f"flange, and the body is wider than the")
    print("  chassis, so there is nowhere to relieve locally -- the standoff "
          "is the whole answer")
    if MOUNT_STANDOFF < D800_PROUD:
        fails.append(
            f"the body cannot be mounted: {MOUNT_STANDOFF:.1f} mm of standoff "
            f"against a {D800_PROUD:.1f} mm front panel"
        )
    elif MOUNT_STANDOFF < D800_PROUD + MOUNT_CLEAR:
        fails.append(
            f"only {MOUNT_STANDOFF - D800_PROUD:.1f} mm to twist the body on, "
            f"want {MOUNT_CLEAR:.1f}"
        )
    else:
        print(f"  {MOUNT_STANDOFF - D800_PROUD:.1f} mm clear to bayonet it "
              "on.  OK")

    # 4. traced clipping, f/5.6 to f/16
    ring_clean = clean_from(FLANGE_F, F_REV_THROAT)
    print("\ntraced illumination through the metal reverse ring "
          f"({F_REV_THROAT:g} mm throat)")
    print("  'corner' is the worst point anywhere on a sensor's 36 x 23.9 "
          "window, 'mid' the worst along")
    print("  the v = 0 stitch axis. 1.000 means nothing is lost there.")
    print(f"  {'f':>5}  {'corner':>7}  {'mid':>7}  {'span':>8}  "
          f"{'overlap':>8}   rays lost inside the frame")
    results = {}
    for fstop in FSTOPS:
        us, vs, r_frac, t_frac, stops = trace(fstop)
        results[fstop] = (us, vs, r_frac, t_frac)
        m = measure(us, vs, r_frac, t_frac)
        by = ", ".join(f"{k} {v}" for k, v in stops.items() if v) or "none"
        print(f"  {fstop:>5g}  {m['frame']:>7.3f}  {m['mid']:>7.3f}  "
              f"{m['span']:>7.2f}m  {m['overlap']:>7.2f}m   {by}")
        # The stitch geometry has to hold at every aperture.
        if abs(m["span"] - STITCH_W) > 0.01:
            fails.append(f"f/{fstop:g}: stitch spans {m['span']:.2f} mm, "
                         f"want {STITCH_W:.2f}")
        if abs(m["overlap"] - SENSOR_W * OVERLAP_FRAC) > 0.01:
            fails.append(
                f"f/{fstop:g}: overlap {m['overlap']:.2f} mm, want "
                f"{SENSOR_W * OVERLAP_FRAC:.2f}"
            )
        # The stitch axis itself must never clip, at any aperture.
        if m["mid"] < 0.999:
            fails.append(f"f/{fstop:g}: the stitch axis clips "
                         f"(worst {m['mid']:.3f})")
        # Corners are only promised from the ring's clean aperture.
        if fstop >= ring_clean and m["frame"] < 0.999:
            fails.append(
                f"f/{fstop:g}: corners not fully lit ({m['frame']:.3f}) "
                f"although f/{ring_clean:.2f} was claimed clean"
            )
        if fstop < ring_clean and m["frame"] >= 0.999:
            fails.append(
                f"f/{fstop:g}: corners are fully lit but f/{ring_clean:.2f} "
                "was claimed as the limit -- the model is too pessimistic"
            )

    print(f"\n  the 44 mm F throat passes the frame CORNERS from "
          f"f/{ring_clean:.2f}. Wide of that the corners")
    print("  lose light while the stitch axis stays clean, so the frame is "
          "fully lit from f/8.4,")
    print("  not from f/5.6. 44 mm is the real Nikon F throat -- no printed "
          "part can beat it, and")
    print(f"  even an unshifted D800 needs "
          f"{need_bore_2d(5.6, FLANGE_F, shift=0.0):.2f} mm there at f/5.6, so "
          "the 14.4 mm")
    print("  shift spends nearly all of the margin a normal camera has.")

    # 4. the printed bayonet, for the record
    print(f"\nsame trace through the printed F mesh ({F_STL_THROAT:g} mm throat)")
    for fstop in (5.6, 11.0, 16.0, 22.0):
        us_p, vs_p, r_p, t_p, stops_p = trace(fstop, throat=F_STL_THROAT)
        m = measure(us_p, vs_p, r_p, t_p)
        lost = stops_p["bore_r"] + stops_p["bore_t"]
        print(f"  f/{fstop:<4g} corner {m['frame']:.3f}  mid {m['mid']:.3f}  "
              f"({lost} rays stopped at the mouth)")
    print(f"  the corner term alone is {need_bore_2d(1e9, FLANGE_F):.2f} mm, so a "
          f"{F_STL_THROAT:g} mm mouth never passes the")
    print("  corners at any aperture. That is why ARM_MOUNT = 0 is the default "
          "and the metal")
    print("  reverse rings are not optional.")

    # 5. the numbers params.scad asserts, checked against the trace
    print("\nstation margins (geometry, matching params.scad)")
    print(f"  {'f':>5}  {'plate':>13}  {'box wall':>13}  {'flange':>13}")
    for fstop in FSTOPS:
        p = need_clear(fstop, D_PLATE_TO_SENSOR)
        w = need_bore_2d(fstop, D_BOXWALL_TO_SENSOR)
        g = need_bore_2d(fstop, FLANGE_F)
        def cell(need, have):
            return f"{need:5.2f}/{have:<5.1f}{'!' if need > have else ' '}"
        print(f"  {fstop:>5g}  {cell(p, BS_SIZE / np.sqrt(2))}  "
              f"{cell(w, TUBE_ID)}  {cell(g, F_REV_THROAT)}")
    plate_margin = BS_SIZE / np.sqrt(2) / need_clear(5.6, D_PLATE_TO_SENSOR) - 1
    print("  '!' marks a station the frame corners do not clear. The plate "
          f"has {plate_margin:.1%} of margin at")
    print("  f/5.6 and only grows; the flange is the one that binds.")
    print(f"  the stitch-axis-only formula would put the flange at "
          f"{need_bore_1d(5.6, FLANGE_F):.2f} mm instead of "
          f"{need_bore_2d(5.6, FLANGE_F):.2f} mm at f/5.6 --")
    print("  a 4.3 mm error, and the reason this check exists.")
    print(f"  bs_t_comp {bs_t_comp():.4f} mm shortens the T arm")
    print("  exit pupil is taken at the lens flange, 180 mm from the sensor. "
          "A real enlarger lens's pupil sits inside the barrel, closer to the "
          "sensor, which shrinks the bundle at the plate -- so these are the "
          "pessimistic numbers.")

    # 6. plots
    # Frames wide open, where the corner loss is visible; pano at f/11, which
    # is what the body actually delivers.
    plot_frames(*results[5.6], 5.6, DOCS / "fxpan_frames.png")
    plot_pano(*results[11.0], 11.0, DOCS / "fxpan_pano.png")
    plot_margins(DOCS / "fxpan_margins.png")
    plot_layout(DOCS / "fxpan_paths.png")
    for p in ("fxpan_paths.png", "fxpan_frames.png", "fxpan_pano.png",
              "fxpan_margins.png"):
        print(DOCS / p)

    if fails:
        print("\nFAILED")
        for f in fails:
            print("  " + f)
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
