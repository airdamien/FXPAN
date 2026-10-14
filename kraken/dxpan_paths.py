#!/usr/bin/env python3
"""DXPAN 65 against the integrated chassis in openscad/dxpan.

Two D7000 sensors, one EL-Nikkor 180/5.6, a 50 x 50 x 1 mm plate at 45 deg.
The imaging is traced unfolded (KrakenOS is exact there). The fold only
enters as the plate's foreshortening and the opposite shift senses.

The R bore is a circle with a flat on the lens side: 2.6 mm of wall, because
the tube axis sits 14.8 mm off the lens seat and a full Ø38 would break
through it. That flat is in the trace.
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fxpan_paths as fx

# --- openscad/dxpan/params.scad + dx_body.scad --------------------------------
EL_FOCAL = 180.0
EL_FFD = 158.5
FLANGE_F = 46.5
SENSOR_W = 23.6
SENSOR_H = 15.6
SENSOR_PX_W = 4928
SENSOR_PX_H = 3264
OVERLAP = 0.20
SHIFT = SENSOR_W / 2.0 * (1.0 - OVERLAP)          # 9.44
STITCH_W = SENSOR_W * (2.0 - OVERLAP)             # 42.48
STITCH_PX = round(SENSOR_PX_W * (2.0 - OVERLAP))

BS_W = BS_H = 50.0
BS_THICK = 1.0
BS_N = 1.52
TUBE_ID = 38.0
F_BORE = 44.0
F_REV_THROAT = 44.0
F_STL_THROAT = 40.0
F_FMOUNT_STACK = 3.0
F_REV_STACK = 8.0
CAM_RECESS = 2.5
PORT_PATCH_T = 4.0
BOX_XY = 70.0
DX_HELI_BODY = 16.58
DX_HELI_EXT = 9.5          # extension at which the path is  the design infinity
DX_LENS = 24.25            # lens seat, from the plate
DX_TUBE_GAIN = 39.0 - DX_LENS
DX_FACE = 33.0
R_WALL = 2.6               # lens-side wall; the bore is flat inside this
# Distance from the R axis to that flat. A full circle is r = 19.
R_CHORD = (DX_LENS - SHIFT) - R_WALL               # 12.21

BS_T_COMP = BS_THICK * (
    BS_N / np.cos(np.arcsin(np.sin(np.radians(45.0)) / BS_N))
    - 1.0 / np.cos(np.radians(45.0))
)
BS_FOCUS_MID = (0.336 + 0.605) / 2.0
R_FOCUS_PULL = BS_T_COMP + BS_FOCUS_MID

DX_PRINTED = (
    EL_FFD - BOX_XY - 2 * PORT_PATCH_T - (DX_HELI_BODY + DX_HELI_EXT)
    - F_FMOUNT_STACK + CAM_RECESS - FLANGE_F
)
TUBE_R = DX_PRINTED - R_FOCUS_PULL
TUBE_T = DX_PRINTED - BS_T_COMP


def dx_reg(tube):
    return (BOX_XY / 2 + PORT_PATCH_T + tube + F_FMOUNT_STACK
            - CAM_RECESS + DX_TUBE_GAIN)


REG_R = dx_reg(TUBE_R)
REG_T = dx_reg(TUBE_T)
# Lens flange to plate at the design infinity extension, then on to the sensor.
LENS_TO_PLATE = DX_LENS + DX_HELI_BODY + DX_HELI_EXT
PLATE_TO_SENSOR_R = REG_R + FLANGE_F
PLATE_TO_SENSOR_T = REG_T + FLANGE_F
PATH_R = LENS_TO_PLATE + PLATE_TO_SENSOR_R
PATH_T = LENS_TO_PLATE + PLATE_TO_SENSOR_T
# Use the transmit leg for the shared plate station. The two differ by 0.5 mm.
D_PLATE = PLATE_TO_SENSOR_T
D_WALL = D_PLATE - DX_FACE

WAVE = fx.WAVE
S_OBJ = fx.S_OBJ
FSTOPS = (5.6, 8.0, 11.0, 16.0)
DOCS = fx.DOCS
EPS = 1e-6

_, STRETCH_U, STRETCH_V = fx.fold_basis()
# Recompute senses at the DX shift. fx.fold_senses() is frozen at 14.40.
_n, _, _ = fx.fold_basis()
_u = np.array([1.0, 0.0, 0.0])
_u_r = fx.reflect(_u, _n)
U_OF_R = float(np.dot(np.array([0.0, -SHIFT, 0.0]), _u_r))
U_OF_T = float(np.dot(np.array([SHIFT, 0.0, 0.0]), _u))
AXIS_R = round(U_OF_R, 9)
AXIS_T = round(U_OF_T, 9)


def plate_passes(at):
    x, y = at(D_PLATE)
    return (abs(x) * STRETCH_U <= BS_W / 2 + EPS
            and abs(y) * STRETCH_V <= BS_H / 2 + EPS)


def bore_passes(at, axis, throat, chord=False):
    for d, dia in ((D_WALL, TUBE_ID),
                   (FLANGE_F + 2.0, TUBE_ID),
                   (FLANGE_F, throat)):
        x, y = at(d)
        if np.hypot(x - axis, y) > dia / 2 + EPS:
            return False
        # The flat is on the lens side of R, which is the outer field.
        if chord and d > FLANGE_F and (axis - x) > R_CHORD + EPS:
            return False
    return True


def field_grid(nu=33, nv=9):
    edges = [-STITCH_W / 2, STITCH_W / 2,
             AXIS_R + SENSOR_W / 2, AXIS_T - SENSOR_W / 2]
    us = np.unique(np.round(np.concatenate([
        np.linspace(-STITCH_W / 2, STITCH_W / 2, nu),
        edges,
        [-STITCH_W / 2 - 2, STITCH_W / 2 + 2],
    ]), 6))
    vs = np.unique(np.round(np.concatenate([
        np.linspace(-SENSOR_H / 2, SENSOR_H / 2, nv),
        [-SENSOR_H / 2 - 1.0, SENSOR_H / 2 + 1.0],
    ]), 6))
    return us, vs


def on_window(x, y, axis):
    return abs(x - axis) <= SENSOR_W / 2 + EPS and abs(y) <= SENSOR_H / 2 + EPS


def trace(fstop, throat=F_STL_THROAT):
    s = fx.system(fstop)
    mag = fx.S_PRIME / S_OBJ
    us, vs = field_grid()
    pupils = fx.pupil_disc(fstop)
    n_p = len(pupils)
    z_lens = S_OBJ
    r_frac = np.zeros((len(vs), len(us)))
    t_frac = np.zeros_like(r_frac)
    stops = {"stop": 0, "plate": 0, "bore_r": 0, "bore_t": 0, "chord": 0}
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
                at = fx._segment(s) if reached else None
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
                    if bore_passes(at, AXIS_R, throat, chord=True):
                        n_r += 1
                    elif wanted:
                        stops["bore_r"] += 1
                if on_window(xi, yi, AXIS_T):
                    if bore_passes(at, AXIS_T, throat, chord=False):
                        n_t += 1
                    elif wanted:
                        stops["bore_t"] += 1
            r_frac[iv, iu] = n_r / n_p
            t_frac[iv, iu] = n_t / n_p
    return us, vs, r_frac, t_frac, stops


def measure(us, vs, r_frac, t_frac):
    in_v = np.abs(vs) <= SENSOR_H / 2 + EPS
    mid = np.argmin(np.abs(vs))
    win_r = np.abs(us - AXIS_R) <= SENSOR_W / 2 + EPS
    win_t = np.abs(us - AXIS_T) <= SENSOR_W / 2 + EPS
    frame = min(float(r_frac[np.ix_(in_v, win_r)].min()),
                float(t_frac[np.ix_(in_v, win_t)].min()))
    mid_min = min(float(r_frac[mid, win_r].min()),
                  float(t_frac[mid, win_t].min()))
    lit = np.clip(r_frac[mid] + t_frac[mid], 0.0, 1.0) >= 0.999
    span = float(us[lit].max() - us[lit].min()) if lit.any() else 0.0
    ov = (r_frac[mid] >= 0.999) & (t_frac[mid] >= 0.999)
    overlap = float(us[ov].max() - us[ov].min()) if ov.any() else 0.0
    return {"frame": frame, "mid": mid_min, "span": span, "overlap": overlap,
            "r_frame": float(r_frac[np.ix_(in_v, win_r)].min()),
            "t_frame": float(t_frac[np.ix_(in_v, win_t)].min())}


def bundle_r(ym, fstop, d):
    return ym * (EL_FOCAL - d) / EL_FOCAL + (EL_FOCAL / fstop) / 2 * (d / EL_FOCAL)


def need_clear(fstop, d, ym=STITCH_W / 2):
    return 2 * bundle_r(ym, fstop, d)


def need_bore_2d(fstop, b, shift=SHIFT):
    al, be = (EL_FOCAL - b) / EL_FOCAL, b / EL_FOCAL
    cu = SENSOR_W / 2 * al + shift * be
    cv = SENSOR_H / 2 * al
    return 2 * (np.hypot(cu, cv) + (EL_FOCAL / fstop) / 2 * be)


def plot_frames(us, vs, r_frac, t_frac, fstop, dest):
    extent = [us[0], us[-1], vs[0], vs[-1]]
    fig, axes = plt.subplots(2, 1, figsize=(9.2, 4.6), sharex=True)
    for ax, frac, rgb, name, axis in (
        (axes[0], t_frac, (0.45, 0.70, 0.95), "T  transmit", AXIS_T),
        (axes[1], r_frac, (0.95, 0.55, 0.40), "R  reflect", AXIS_R),
    ):
        ax.imshow(np.clip(frac[..., None] * np.asarray(rgb), 0, 1),
                  origin="lower", extent=extent, aspect="auto")
        ax.axvline(axis, color="white", ls=":", lw=0.8)
        ax.set_ylabel("v (mm)")
        ax.set_title(f"{name}   axis u = {axis:+.2f} mm", fontsize=9)
    axes[1].set_xlabel("field u (mm at the sensor)")
    fig.suptitle(
        f"DXPAN 65 at f/{fstop:g}  —  {STITCH_W:.2f} x {SENSOR_H} mm field, "
        f"50 mm plate, R wall flat at {R_CHORD:.1f} mm"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def plot_pano(us, vs, r_frac, t_frac, fstop, dest):
    both = np.clip(r_frac + t_frac, 0.0, 1.0)
    hue = (us - us[0]) / (us[-1] - us[0])
    stripe = plt.cm.turbo(np.broadcast_to(hue, both.shape))[..., :3]
    img = np.clip(stripe * both[..., None], 0.0, 1.0)
    fig, ax = plt.subplots(figsize=(10.2, 2.8))
    ax.imshow(img, origin="lower", extent=[us[0], us[-1], vs[0], vs[-1]],
              aspect="auto")
    for e in (-STITCH_W / 2, STITCH_W / 2):
        ax.axvline(e, color="white", ls="--", lw=1.0)
    ax.set_xlabel("stitched field u (mm)")
    ax.set_ylabel("v (mm)")
    ax.set_title(
        f"DXPAN 65 stitch at f/{fstop:g}  —  {STITCH_W:.2f} x {SENSOR_H} mm, "
        f"{STITCH_W / SENSOR_H:.2f}:1, {STITCH_PX} x {SENSOR_PX_H}"
    )
    fig.tight_layout()
    fig.savefig(dest, dpi=160)
    plt.close(fig)


def plot_compare(dx, fx_us, fx_vs, fx_r, fx_t, dest):
    """DXPAN and FXPAN stitches at the same f-number, same colour scale."""
    us, vs, r, t, fstop = dx
    fig, axes = plt.subplots(2, 1, figsize=(10.4, 5.2))
    for ax, (uus, vvs, rr, tt, title) in zip(axes, (
        (us, vs, r, t,
         f"DXPAN  {STITCH_W:.1f} x {SENSOR_H} mm   50x50 plate   f/{fstop:g}"),
        (fx_us, fx_vs, fx_r, fx_t,
         f"FXPAN  {fx.STITCH_W:.1f} x {fx.SENSOR_H} mm   50x75 plate   f/{fstop:g}"),
    )):
        both = np.clip(rr + tt, 0.0, 1.0)
        ax.imshow(both, origin="lower", cmap="magma", vmin=0, vmax=1,
                  extent=[uus[0], uus[-1], vvs[0], vvs[-1]], aspect="auto")
        ax.set_title(title, fontsize=10)
        ax.set_ylabel("v (mm)")
    axes[1].set_xlabel("stitched field u (mm)")
    fig.suptitle("Field illumination — DXPAN against FXPAN")
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def plot_layout(dest):
    fig, ax = plt.subplots(figsize=(8.2, 7.2))
    seat = DX_LENS
    ax.plot([-DX_FACE, DX_FACE, DX_FACE, -36, -36, -DX_FACE],
            [-seat, -seat, DX_FACE, DX_FACE, -seat, -seat],
            color="0.55", lw=1.2, label="chassis")
    span = (BS_W / 2) / np.sqrt(2)
    ax.plot([-span, span], [span, -span], color="goldenrod", lw=5,
            solid_capstyle="butt", label="50x50 plate")
    ax.plot([0, 0], [-seat - 30, 0], color="0.45", lw=1, ls="--")
    ax.plot([0, 0], [0, PLATE_TO_SENSOR_T], color="steelblue", lw=1, ls="--")
    ax.plot([0, PLATE_TO_SENSOR_R], [0, 0], color="indianred", lw=1, ls="--")
    for fstop, style in ((5.6, "-"), (11.0, ":")):
        r = need_clear(fstop, D_PLATE) / 2
        ax.plot([-r, r], [r, -r], color="crimson", ls=style, lw=1.3,
                label=f"plate needs {2 * r:.1f} mm at f/{fstop:g}")
    ax.plot([SHIFT, SHIFT],
            [PLATE_TO_SENSOR_T - 8, PLATE_TO_SENSOR_T + 8],
            color="steelblue", lw=4, solid_capstyle="butt",
            label=f"T axis +{SHIFT:.2f}")
    ax.plot([PLATE_TO_SENSOR_R - 8, PLATE_TO_SENSOR_R + 8],
            [-SHIFT, -SHIFT],
            color="indianred", lw=4, solid_capstyle="butt",
            label=f"R axis -{SHIFT:.2f}")
    ax.set_aspect("equal")
    ax.set_xlabel("X (mm)   R to +X")
    ax.set_ylabel("Y (mm)   lens to −Y, T to +Y")
    ax.set_title("DXPAN 65 — plan. Lens seat at 24.3 mm, tubes carry the rest.")
    ax.legend(loc="upper right", frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(dest, dpi=140)
    plt.close(fig)


def main():
    DOCS.mkdir(parents=True, exist_ok=True)
    fx.check_kraken_is_exact()
    print("DXPAN 65 — focus and field")
    print(f"  lens flange to plate at +{DX_HELI_EXT:.2f} mm extension: "
          f"{LENS_TO_PLATE:.2f} mm")
    print(f"  plate to R sensor {PLATE_TO_SENSOR_R:.2f}   "
          f"plate to T sensor {PLATE_TO_SENSOR_T:.2f}")
    print(f"  mechanical path R {PATH_R:.2f}   T {PATH_T:.2f}   "
          f"target {EL_FFD:.2f}")
    print(f"  +{DX_HELI_EXT:.2f} mm is the mirror-image station "
          f"(path {EL_FFD:.2f} with the unshortened tube).")
    print(f"  T mechanical {PATH_T:.2f} puts the paraxial transmit image "
          f"at {PATH_T + BS_T_COMP:.2f} (glass {BS_T_COMP:.3f}).")
    print(f"  R mechanical {PATH_R:.2f} is {EL_FFD - PATH_R:.3f} mm "
          f"inside paraxial.")
    print(f"  T's sensor is {PATH_T - PATH_R:.3f} mm farther from the plate "
          f"than R's — the least-confusion offset ({BS_FOCUS_MID:.3f}).")
    print(f"  another {R_FOCUS_PULL:.3f} mm of extension, to "
          f"+{DX_HELI_EXT + R_FOCUS_PULL:.2f} mm, puts R on paraxial "
          f"infinity and T on the circle of least confusion together.")
    print(f"  a 17–31 mm helicoid has 14 mm of travel, so +{DX_HELI_EXT + R_FOCUS_PULL:.1f} "
          f"is inside it, with about {14 - (DX_HELI_EXT + R_FOCUS_PULL):.1f} mm "
          f"left for closer focus.")
    print(f"  shift R {U_OF_R:+.2f}   T {U_OF_T:+.2f}   "
          f"{'opposite' if U_OF_R * U_OF_T < 0 else 'SAME SIDE'}")
    print(f"  R chord: flat {R_CHORD:.2f} mm off the axis "
          f"(full bore r {TUBE_ID/2:.1f})")

    print("\nplate and bores (geometry, frame corner)")
    print(f"  plate presents {BS_W / np.sqrt(2):.2f} mm across the fold, "
          f"{BS_H:.1f} mm along it")
    for fstop in FSTOPS:
        across = need_clear(fstop, D_PLATE)
        along = 2 * bundle_r(SENSOR_H / 2, fstop, D_PLATE)
        wall = need_bore_2d(fstop, D_WALL)
        flange = need_bore_2d(fstop, FLANGE_F)
        print(f"  f/{fstop:<4g}  plate across {across:5.2f}/35.4"
              f"{' !' if across > BS_W/np.sqrt(2) else '  '}  "
              f"along {along:5.2f}/{BS_H:.0f}  "
              f"wall {wall:5.2f}/{TUBE_ID:.0f}  "
              f"flange {flange:5.2f}/{F_STL_THROAT:.0f} printed"
              f" ({F_REV_THROAT:.0f} metal)")

    print("\ntrace")
    results = {}
    for fstop in FSTOPS:
        us, vs, r, t, stops = trace(fstop)
        m = measure(us, vs, r, t)
        results[fstop] = (us, vs, r, t, stops, m)
        print(f"  f/{fstop:<4g}  frame {m['frame']:.3f}  "
              f"R {m['r_frame']:.3f}  T {m['t_frame']:.3f}  "
              f"mid {m['mid']:.3f}  span {m['span']:.2f}  "
              f"overlap {m['overlap']:.2f}  "
              f"stopped plate {stops['plate']}  "
              f"R {stops['bore_r']}  T {stops['bore_t']}")

    # FXPAN at f/5.6 and f/11 for the comparison figure. Its own trace.
    print("\nFXPAN trace for the comparison")
    fx5 = fx.trace(5.6)
    fx11 = fx.trace(11.0)
    m5 = fx.measure(*fx5[:4])
    m11 = fx.measure(*fx11[:4])
    print(f"  FXPAN f/5.6  frame {m5['frame']:.3f}  span {m5['span']:.2f}  "
          f"overlap {m5['overlap']:.2f}")
    print(f"  FXPAN f/11   frame {m11['frame']:.3f}  span {m11['span']:.2f}  "
          f"overlap {m11['overlap']:.2f}")

    us, vs, r, t, _, _ = results[5.6]
    plot_frames(us, vs, r, t, 5.6, DOCS / "dxpan_frames.png")
    us, vs, r, t, _, _ = results[11.0]
    plot_pano(us, vs, r, t, 11.0, DOCS / "dxpan_pano.png")
    plot_compare((us, vs, r, t, 11.0), fx11[0], fx11[1], fx11[2], fx11[3],
                 DOCS / "dxpan_vs_fxpan.png")
    plot_layout(DOCS / "dxpan_paths.png")
    for name in ("dxpan_frames.png", "dxpan_pano.png", "dxpan_vs_fxpan.png",
                 "dxpan_paths.png"):
        print(DOCS / name)


if __name__ == "__main__":
    main()
