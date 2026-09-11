#!/usr/bin/env python3
"""Texture the hybrid object plane with a countryside still.

Kraken maps each object point through the 135/5.6 onto the two toed DX
windows. This samples a photo at those points so one centered D7000 frame
sits next to the T+R stitch.
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle
from scipy.interpolate import RegularGridInterpolator
from scipy.ndimage import map_coordinates

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hybrid_paths as hp

# CC BY-SA 4.0 Radek Hloch — Wikimedia File:Landscape_of_Tuscany_3.jpg
SCENE = hp.OUT.parent / "docs" / "kraken" / "countryside.jpg"
DEST = hp.OUT.parent / "docs" / "kraken" / "el135_scene.png"
# 1280×853 still: lone tree on the left, farmhouse / cypresses on the right.
CROP_XY = (330, 270, 1230, 660)


def _photo(path):
    img = np.asarray(plt.imread(path), dtype=np.float32)
    if img.max() > 1.5:
        img = img / 255.0
    if img.ndim == 2:
        img = np.stack([img, img, img], axis=-1)
    return np.clip(img[..., :3], 0.0, 1.0)


def _extent(img):
    h, w = img.shape[:2]
    aspect = w / float(h)
    obj_h = max(hp.SENSOR_H / hp.MAG, (hp.STITCH_W / hp.MAG) / aspect)
    obj_w = aspect * obj_h
    return np.array([-obj_w / 2.0, obj_w / 2.0, -obj_h / 2.0, obj_h / 2.0])


def _sample(img, ext, x0, x1, y0, y1, nx, ny):
    xs = np.linspace(x0, x1, nx)
    ys = np.linspace(y0, y1, ny)
    gx, gy = np.meshgrid(xs, ys)
    u = (gx - ext[0]) / (ext[1] - ext[0]) * (img.shape[1] - 1)
    v = (ext[3] - gy) / (ext[3] - ext[2]) * (img.shape[0] - 1)
    rgb = np.stack(
        [
            map_coordinates(img[..., c], [v, u], order=1, mode="constant", cval=0.0)
            for c in range(3)
        ],
        axis=-1,
    )
    return xs, ys, np.clip(rgb, 0.0, 1.0)


def _mask(thx, thy, t_frac, r_frac, xs, ys):
    fn = RegularGridInterpolator(
        (thy, thx), t_frac + r_frac, bounds_error=False, fill_value=0.0
    )
    gy, gx = np.meshgrid(ys, xs, indexing="ij")
    return fn(np.stack([gy, gx], axis=-1))


def _panel(ax, rgb, extent, title):
    ax.imshow(rgb, origin="lower", extent=extent, interpolation="bilinear")
    ax.set_aspect("equal")
    ax.set_title(title, color="0.92", fontsize=11)
    ax.set_xlabel("object X (mm)", color="0.65")
    ax.set_ylabel("object Y (mm)", color="0.65")
    ax.tick_params(colors="0.55")
    for spine in ax.spines.values():
        spine.set_color("0.35")


def main():
    if not SCENE.is_file():
        raise SystemExit(f"missing scene still: {SCENE}")

    hp.apply_lens("EL-Nikkor 135/5.6", 135.0, 5.6)
    sys_t = hp.transmit_system(focal=True)
    thx, thy, t_frac, r_frac, counts = hp.trace_frames(sys_t)

    img = _photo(SCENE)
    x0, y0c, x1, y1c = CROP_XY
    img = img[y0c:y1c, x0:x1]
    ext = _extent(img)
    dx_w = hp.SENSOR_W / hp.MAG
    dx_h = hp.SENSOR_H / hp.MAG
    st_w = hp.STITCH_W / hp.MAG
    y0, y1 = -dx_h / 2.0, dx_h / 2.0
    ny = 320
    nx_st = max(2, int(round(ny * st_w / dx_h)))
    nx_dx = max(2, int(round(ny * dx_w / dx_h)))

    xs_d, ys_d, one = _sample(img, ext, -dx_w / 2, dx_w / 2, y0, y1, nx_dx, ny)
    xs_s, ys_s, hyb = _sample(img, ext, -st_w / 2, st_w / 2, y0, y1, nx_st, ny)
    cover = _mask(thx, thy, t_frac, r_frac, xs_s, ys_s)
    hyb = hyb * (cover > 0.15)[..., None]

    fig = plt.figure(figsize=(12.4, 7.8), facecolor="0.08")
    gs = fig.add_gridspec(
        2, 2, height_ratios=[1.12, 1.0], width_ratios=[1.0, st_w / dx_w],
        hspace=0.34, wspace=0.10, left=0.06, right=0.98, top=0.90, bottom=0.10,
    )
    ax0 = fig.add_subplot(gs[0, :])
    ax1 = fig.add_subplot(gs[1, 0])
    ax2 = fig.add_subplot(gs[1, 1])
    for ax in (ax0, ax1, ax2):
        ax.set_facecolor("black")

    ax0.imshow(img, origin="upper", extent=ext, interpolation="bilinear")
    ax0.add_patch(Rectangle(
        (-dx_w / 2, y0), dx_w, dx_h,
        fill=False, ec="deepskyblue", lw=1.8, label="single DX",
    ))
    ax0.add_patch(Rectangle(
        (-st_w / 2, y0), st_w, dx_h,
        fill=False, ec="goldenrod", lw=1.8, label="hybrid stitch",
    ))
    ax0.set_aspect("equal")
    pad_x = 0.08 * (ext[1] - ext[0])
    pad_y = 0.06 * (ext[3] - ext[2])
    ax0.set_xlim(ext[0] - pad_x, ext[1] + pad_x)
    ax0.set_ylim(ext[2] - pad_y, ext[3] + pad_y)
    ax0.legend(loc="lower right", frameon=False, labelcolor="white")
    ax0.set_title(
        f"{hp.EL_NAME} at {hp.S_OBJ:.0f} mm  ·  object plane  "
        f"(one DX {dx_w:.0f}×{dx_h:.0f} mm,  stitch {st_w:.0f}×{dx_h:.0f} mm)",
        color="0.92", fontsize=11,
    )
    ax0.set_xlabel("object X (mm)", color="0.65")
    ax0.set_ylabel("object Y (mm)", color="0.65")
    ax0.tick_params(colors="0.55")
    for spine in ax0.spines.values():
        spine.set_color("0.35")

    _panel(ax1, one, [xs_d[0], xs_d[-1], ys_d[0], ys_d[-1]],
           f"single D7000 DX  ·  {hp.SINGLE_FOV:.1f}°")
    _panel(ax2, hyb, [xs_s[0], xs_s[-1], ys_s[0], ys_s[-1]],
           f"hybrid T+R stitch  ·  {hp.PANO_FOV:.1f}°  ·  {st_w / dx_w:.2f}×")

    fig.text(
        0.50, 0.015,
        "scene: Radek Hloch / CC BY-SA 4.0  ·  Wikimedia File:Landscape of Tuscany 3.jpg",
        ha="center", color="0.45", fontsize=8,
    )

    DEST.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(DEST, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(
        f"{hp.EL_NAME}  scene  T-only={counts['left']}  overlap={counts['overlap']}  "
        f"R-only={counts['right']}"
    )
    print(DEST)


if __name__ == "__main__":
    main()
