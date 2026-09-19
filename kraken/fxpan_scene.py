#!/usr/bin/env python3
"""Countryside: FXPAN 65 + EL180 vs anamorphic adapters on the taking lens.

Afocal squeeze in front of the 180. 1.33x / 1.5x / 2x are the adapters that
actually fit this job (Sirui/SLR Magic, Kowa/Iscorama, ISCO Ultra-Star
attachment). Not the Ultra-Star HD Plus 60 mm integrated projector lens —
that is a 60 mm f/2.1 with BFL 36 mm for a 21 mm Scope gate, not a front
adapter, and it cannot cover two D800s.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hybrid_paths as hp
import hybrid_scene as hs

DEST = hp.OUT.parent / "docs" / "kraken" / "fxpan_anamorph_scene.png"
SQUEEZES = (1.0, 1.33, 1.5, 2.0)
LABELS = {
    1.0: "FXPAN 65  spherical",
    1.33: "1.33x adapter  (Sirui / SLR Magic)",
    1.5: "1.5x adapter  (Kowa / Iscorama)",
    2.0: "2x adapter  (ISCO Ultra-Star attachment)",
}
COLORS = {
    1.0: "yellowgreen",
    1.33: "deepskyblue",
    1.5: "coral",
    2.0: "tomato",
}


def _hfov(half_mm, s_prime, squeeze=1.0):
    return 2.0 * math.degrees(math.atan(squeeze * half_mm / s_prime))


def _obj_w(half_mm, mag, squeeze=1.0):
    return squeeze * (2.0 * half_mm) / mag


def _sample_stitch(img, ext, f, squeeze, thx, thy, t_frac, r_frac):
    y0, y1 = -f["dx_h"] / 2.0, f["dx_h"] / 2.0
    ny = 280
    st_w = f["st_w"] * squeeze
    nx = max(2, int(round(ny * st_w / f["dx_h"])))
    xs, ys, rgb = hs._sample(img, ext, -st_w / 2, st_w / 2, y0, y1, nx, ny)
    cover = hs._mask(np.asarray(thx) * squeeze, thy, t_frac, r_frac, xs, ys)
    rgb = rgb * (cover > 0.15)[..., None]
    return dict(rgb=rgb, xs=xs, ys=ys, st_w=st_w, y0=y0, y1=y1)


def plot_adapters(img, ext, f, one, grabs, dest):
    scale, unit = 0.001, "m"
    fig = plt.figure(figsize=(14.0, 14.8), facecolor="0.08")
    gs = fig.add_gridspec(
        6, 1, height_ratios=[1.25, 0.72, 1.0, 1.15, 1.25, 1.55],
        hspace=0.42, left=0.06, right=0.98, top=0.955, bottom=0.055,
    )
    axes = [fig.add_subplot(gs[i]) for i in range(6)]
    for ax in axes:
        ax.set_facecolor("black")

    y0 = -f["dx_h"] / 2.0
    boxes = [
        (-f["dx_w"] / 2, y0, f["dx_w"], f["dx_h"], f["color"],
         "one D800 + EL180"),
    ]
    for sq in SQUEEZES:
        w = f["st_w"] * sq
        boxes.append((-w / 2, y0, w, f["dx_h"], COLORS[sq], LABELS[sq]))
    hs._object_plane(
        axes[0], img, ext, boxes,
        "EL-Nikkor 180/5.6 at 50 m  ·  FXPAN 65 with an afocal adapter on the front",
        unit=unit, scale=scale,
    )
    hs._panel(
        axes[1], one["rgb"],
        [one["xs"][0], one["xs"][-1], one["ys"][0], one["ys"][-1]],
        f"one D800  ·  {_hfov(f['sw'] / 2, hp.S_PRIME):.1f}°  ·  "
        f"{_obj_w(f['sw'] / 2, f['mag']) * scale:.1f}×"
        f"{f['dx_h'] * scale:.1f} m",
        unit=unit, scale=scale,
    )
    for ax, sq in zip(axes[2:], SQUEEZES):
        g = grabs[sq]
        deg = _hfov(f["st"] / 2, hp.S_PRIME, sq)
        span = _obj_w(f["st"] / 2, f["mag"], sq) * scale
        aspect = (f["st"] / f["sh"]) * sq
        hs._panel(
            ax, g["rgb"],
            [g["xs"][0], g["xs"][-1], g["ys"][0], g["ys"][-1]],
            f"{LABELS[sq]}  ·  {deg:.1f}°  ·  {span:.1f} m  ·  {aspect:.2f}:1",
            unit=unit, scale=scale,
        )
    fig.text(
        0.50, 0.012,
        "Same Tuscany still as el180_d800_scene.png. Adapters are afocal cylinders "
        "on the 180 (76 mm barrel, 32 mm pupil at f/5.6). 180 mm is long enough that "
        "even 2x should clear two FX windows.  scene: Radek Hloch / CC BY-SA 4.0",
        ha="center", color="0.45", fontsize=8,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


def main():
    extra = hp.helicoid_extra(180.0, hs.S_OBJ_180)
    f = hs._setup(
        hs.D800, "EL-Nikkor 180/5.6", 180.0,
        s_obj=hs.S_OBJ_180, extra=extra,
    )
    raw = hs._photo(hs.SCENE)
    ext = hs._extent_fit(raw, f["st_w"] * 2.0 * 1.12, f["dx_h"] * 1.4)
    sys_t = hp.transmit_system(focal=True)
    thx, thy, t_frac, r_frac, _ = hp.trace_frames(sys_t)
    y0, y1 = -f["dx_h"] / 2.0, f["dx_h"] / 2.0
    ny = 280
    nx = max(2, int(round(ny * f["dx_w"] / f["dx_h"])))
    xs, ys, rgb = hs._sample(
        raw, ext, -f["dx_w"] / 2, f["dx_w"] / 2, y0, y1, nx, ny,
    )
    one = dict(rgb=rgb, xs=xs, ys=ys)
    grabs = {
        sq: _sample_stitch(raw, ext, f, sq, thx, thy, t_frac, r_frac)
        for sq in SQUEEZES
    }
    plot_adapters(raw, ext, f, one, grabs, DEST)
    px_st = int(round(f["st"] / f["sw"] * f["px_w"]))
    print(
        f"PATH={hp.PATH_TOTAL:.1f} mm  helicoid +{extra:.1f} mm  "
        f"stitch {f['st']:.2f} mm"
    )
    print(
        f"{'squeeze':>8}  {'HFOV':>6}  {'field m':>8}  {'mm/px':>6}  aspect"
    )
    print(
        f"{'single':>8}  {_hfov(f['sw'] / 2, hp.S_PRIME):6.2f}  "
        f"{_obj_w(f['sw'] / 2, f['mag']) / 1000:8.2f}  "
        f"{_obj_w(f['sw'] / 2, f['mag']) / f['px_w']:6.2f}  "
        f"{f['sw'] / f['sh']:.2f}:1  {f['px_w']}x{f['px_h']}"
    )
    for sq in SQUEEZES:
        w = _obj_w(f["st"] / 2, f["mag"], sq)
        print(
            f"{sq:8g}  {_hfov(f['st'] / 2, hp.S_PRIME, sq):6.2f}  "
            f"{w / 1000:8.2f}  {w / px_st:6.2f}  "
            f"{(f['st'] / f['sh']) * sq:.2f}:1  {px_st}x{f['px_h']}"
        )
    hp.apply_helicoid(0.0)


if __name__ == "__main__":
    main()
