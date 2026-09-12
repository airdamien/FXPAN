#!/usr/bin/env python3
"""Sharp T + shadowgraph R of a supersonic bullet (one printed shim).

The 135/5.6 images a blank card at s. The slug sits on that conjugate.
Shocks are a BK7 ExtraShape sag (Gladstone–Dale stand-in). A perfect
image of a phase object is just the silhouette — that is T. R is the
same tube with +0.6 mm of path (0.5+0.2 from shims.stl). That is
~7.5 mm of object-side defocus; ray bunching at the Mach cone is the
shadowgraph.

Kraken supplies MAG / s / s′ and checks the walk on a coarse grid.
The published plate is the same map at photosite density (a 0.3 mm
ridge is thinner than a 97-wide Kraken field). Writes
docs/kraken/shadowgraph_bullet.png.
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hybrid_paths as hp

DEST = hp.OUT.parent / "docs" / "kraken"
REF = DEST / "settles_bullet.jpg"
WAVE = hp.WAVE
SHIM = 0.60
N_BK7 = 1.517
# Side-on, nose toward −X so the 135 flips it Settles-style (nose left).
NOSE = -6.0
BODY_L = 14.0
BODY_R = 1.7
MACH = 2.05
SHOCK_A = 0.070
SHOCK_W = 0.22
WAKE_A = 0.014


def _in_bullet(x, y):
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    t = (x - NOSE) / BODY_L
    rad = np.where(
        (t >= 0.0) & (t <= 1.0),
        BODY_R * np.sqrt(np.clip(t, 0.0, 1.0)),
        0.0,
    )
    nose = (x < NOSE) & (x > NOSE - BODY_R) & (
        y * y + (x - NOSE) ** 2 < (0.92 * BODY_R) ** 2
    )
    return ((t >= 0.0) & (t <= 1.0) & (np.abs(y) <= rad)) | nose


def bullet_sag(x, y, E):
    """Higher n inside the Mach cone (dense shocked air), tanh shock, weak wake."""
    a, w, mu, a_w, x0, bl, _br = [float(v) for v in E[:7]]
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    behind = x >= x0
    cone = np.tan(mu) * np.maximum(x - x0, 0.0)
    inside = 0.5 * (1.0 + np.tanh((cone - np.abs(y)) / max(w, 1e-6)))
    cone2 = 0.70 * cone
    inside2 = 0.18 * 0.5 * (1.0 + np.tanh((cone2 - np.abs(y)) / max(1.6 * w, 1e-6)))
    base = x0 + bl
    wx = np.clip((x - base) / 36.0, 0.0, 1.0)
    wake = (
        a_w * wx * np.exp(-(y ** 2) / (2.0 * 0.9 ** 2))
        * np.sin(0.85 * (x - base))
        * (1.0 + 0.35 * np.sin(1.8 * (x - base) + 2.0 * y))
    )
    return np.where(behind, a * (inside + inside2) + wake, 0.0)


def _E():
    return np.array(
        [SHOCK_A, SHOCK_W, np.arcsin(1.0 / MACH), WAKE_A, NOSE, BODY_L, BODY_R]
    )


def _aim(src, pup):
    d = np.asarray(pup, dtype=float) - np.asarray(src, dtype=float)
    n = np.linalg.norm(d)
    if n < 1e-9:
        return [0.0, 0.0, 1.0]
    return (d / n).tolist()


def camera(shim=0.0, z_plate=8.0):
    """Phase plate almost on the card — the conjugate-bullet case."""
    plate = 2.0
    obj = hp.Kos.surf()
    obj.Thickness = z_plate
    obj.Glass = "AIR"
    obj.Diameter = 220
    obj.Drawing = 0
    front = hp.Kos.surf()
    front.Thickness = plate
    front.Glass = "BK7"
    front.Diameter = 180
    front.Name = "flow"
    front.ExtraData = [bullet_sag, _E()]
    back = hp.Kos.surf()
    back.Thickness = hp.S_OBJ - z_plate - plate
    back.Glass = "AIR"
    back.Diameter = 180
    lens = hp.Kos.surf()
    lens.Name = "EL"
    lens.Thin_Lens = hp.EL_F
    lens.Diameter = hp.EL_EPD
    lens.Thickness = hp.S_PRIME + float(shim)
    lens.Glass = "AIR"
    ima = hp.Kos.surf()
    ima.Name = "T"
    ima.Glass = "AIR"
    ima.Diameter = 80
    return hp._quiet_system([obj, front, back, lens, ima])


def _hit(sys_t, src):
    sys_t.Trace(src, _aim(src, [0.0, 0.0, hp.S_OBJ]), WAVE)
    try:
        names = list(sys_t.NAME)
    except TypeError:
        return None
    if "T" not in names:
        return None
    ost = hp._ost(sys_t)
    if len(ost) < 1:
        return None
    return float(ost[-1][0]), float(ost[-1][1])


def kraken_check():
    """Few Kraken rays: object-side defocus z = shim / MAG²."""
    sys0 = camera(0.0)
    sys1 = camera(SHIM)
    z_obj = SHIM / (hp.MAG ** 2)
    mu = np.arcsin(1.0 / MACH)
    x = NOSE + 10.0
    y = 10.0 * np.tan(mu) + 0.8
    h0, h1 = _hit(sys0, [float(x), float(y), 0.0]), _hit(sys1, [float(x), float(y), 0.0])
    eps = 0.04
    dsdx = (
        float(bullet_sag(x + eps, y, _E())) - float(bullet_sag(x - eps, y, _E()))
    ) / (2.0 * eps)
    thx = (N_BK7 - 1.0) * dsdx
    pred = -hp.MAG * z_obj * thx
    dkr = (h1[0] - h0[0]) if (h0 and h1) else float("nan")
    print(
        f"Kraken Δx on cone = {dkr:.4f} mm   "
        f"paraxial MAG·z·θ = {pred:.4f} mm   "
        f"z_obj={z_obj:.1f} mm",
        flush=True,
    )
    return z_obj


def shadow_maps(z_obj, nx=760, ny=500):
    x_max = hp.HALF_W / hp.MAG
    y_max = hp.HALF_H / hp.MAG
    ox = np.linspace(-x_max, x_max, nx)
    oy = np.linspace(-y_max, y_max, ny)
    OY, OX = np.meshgrid(oy, ox, indexing="ij")
    sag = bullet_sag(OX, OY, _E())
    dsdx = np.gradient(sag, ox, axis=1)
    dsdy = np.gradient(sag, oy, axis=0)
    thx = (N_BK7 - 1.0) * dsdx
    thy = (N_BK7 - 1.0) * dsdy
    # Image-plane map. Lens flip so nose (−X object) lands on the left.
    Xi = -hp.MAG * (OX + z_obj * thx)
    Yi = -hp.MAG * (OY + z_obj * thy)
    dxi_dy, dxi_dx = np.gradient(Xi, oy, ox)
    dyi_dy, dyi_dx = np.gradient(Yi, oy, ox)
    det = dxi_dx * dyi_dy - dxi_dy * dyi_dx
    det = np.where(np.abs(det) < 1e-8, 1e-8, det)
    I = 1.0 / np.abs(det)
    body = _in_bullet(OX, OY)
    live = ~body
    I = np.where(body, 0.0, I / np.median(I[live]) * 0.58)
    T = np.where(body, 0.0, 0.58)
    lo, hi = np.percentile(I[live], (1.5, 99.6))
    I = np.clip((I - lo) / (hi - lo + 1e-9), 0.0, 1.0)
    I = np.where(body, 0.0, I)
    ext = (-x_max * hp.MAG, x_max * hp.MAG, -y_max * hp.MAG, y_max * hp.MAG)
    return T, I, ext


def _panel(ax, img, extent, title, interpolation="bilinear"):
    ax.imshow(
        img, origin="lower", extent=extent, cmap="gray",
        vmin=0.0, vmax=1.0, interpolation=interpolation,
    )
    ax.set_aspect("equal")
    ax.set_title(title, color="0.92", fontsize=10)
    ax.set_xlabel("image X (mm)", color="0.55", fontsize=8)
    ax.set_ylabel("image Y (mm)", color="0.55", fontsize=8)
    ax.tick_params(colors="0.5", labelsize=7)
    ax.set_facecolor("black")
    for spine in ax.spines.values():
        spine.set_color("0.35")


def main():
    hp.apply_chassis(46.5, 23.6, 15.6)
    hp.apply_lens("EL-Nikkor 135/5.6", 135.0, 5.6)
    print(
        f"{hp.EL_NAME}  s={hp.S_OBJ:.1f}  s′={hp.S_PRIME:.1f}  "
        f"m={hp.MAG:.3f}  shim={SHIM} mm  M={MACH}",
        flush=True,
    )
    z_obj = kraken_check()
    sharp, shadow, ext = shadow_maps(z_obj)

    fig, axes = plt.subplots(1, 3, figsize=(12.6, 4.2), facecolor="0.08")
    fig.subplots_adjust(left=0.05, right=0.99, top=0.84, bottom=0.16, wspace=0.16)
    _panel(axes[0], sharp, ext, "T  ·  conjugate  ·  shim 0")
    _panel(
        axes[1], shadow, ext, f"R  ·  shadowgraph  ·  shim +{SHIM:.1f} mm",
        interpolation="nearest",
    )
    if REF.exists():
        ref = np.asarray(plt.imread(REF))
        axes[2].imshow(ref, cmap="gray" if ref.ndim == 2 else None)
        axes[2].set_title("Settles  ·  collimated lab", color="0.92", fontsize=10)
    axes[2].set_axis_off()
    axes[2].set_facecolor("0.08")
    fig.suptitle(
        "Same 50/50 pair, one shim on R  ·  "
        f"object defocus {z_obj:.1f} mm  ·  M={MACH:g}",
        color="0.92",
        fontsize=12,
    )
    fig.text(
        0.50,
        0.02,
        "T is a phase-blind image of the card: only the slug.  "
        "R is 0.6 mm longer (z′ = shim / m²). Kraken checked the walk; "
        "the plate is that map at DX sampling. Not a knife. Not the hybrid toe.",
        ha="center",
        color="0.55",
        fontsize=8,
    )
    DEST.mkdir(parents=True, exist_ok=True)
    dest = DEST / "shadowgraph_bullet.png"
    fig.savefig(dest, dpi=160, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


if __name__ == "__main__":
    main()
