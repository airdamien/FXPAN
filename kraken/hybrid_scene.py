#!/usr/bin/env python3
"""Texture the hybrid object plane with a countryside still.

Kraken maps each object point through the 135/5.6 onto the two toed DX
windows. This samples a photo at those points so one centered DX frame
sits next to the T+R stitch. A second figure compares D7000 vs D7200
sampling on that same field (the window is identical; the pixels are not).
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
DEST_D7200 = hp.OUT.parent / "docs" / "kraken" / "el135_d7200.png"
# 1280×853 still: lone tree on the left, farmhouse / cypresses on the right.
CROP_XY = (330, 270, 1230, 660)
BODIES = (
    ("D7000", 4928, 3264, 16.2),
    ("D7200", 6000, 4000, 24.2),
)
STAR_MM = 8.0


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


def _panel(ax, rgb, extent, title, interpolation="bilinear"):
    ax.imshow(rgb, origin="lower", extent=extent, interpolation=interpolation)
    ax.set_aspect("equal")
    ax.set_title(title, color="0.92", fontsize=11)
    ax.set_xlabel("object X (mm)", color="0.65")
    ax.set_ylabel("object Y (mm)", color="0.65")
    ax.tick_params(colors="0.55")
    for spine in ax.spines.values():
        spine.set_color("0.35")


def _object_plane(ax, img, ext, dx_w, dx_h, st_w, y0):
    ax.imshow(img, origin="upper", extent=ext, interpolation="bilinear")
    ax.add_patch(Rectangle(
        (-dx_w / 2, y0), dx_w, dx_h,
        fill=False, ec="deepskyblue", lw=1.8, label="single DX",
    ))
    ax.add_patch(Rectangle(
        (-st_w / 2, y0), st_w, dx_h,
        fill=False, ec="goldenrod", lw=1.8, label="hybrid stitch",
    ))
    ax.set_aspect("equal")
    pad_x = 0.08 * (ext[1] - ext[0])
    pad_y = 0.06 * (ext[3] - ext[2])
    ax.set_xlim(ext[0] - pad_x, ext[1] + pad_x)
    ax.set_ylim(ext[2] - pad_y, ext[3] + pad_y)
    ax.legend(loc="lower right", frameon=False, labelcolor="white")
    ax.set_title(
        f"{hp.EL_NAME} at {hp.S_OBJ:.0f} mm  ·  object plane  "
        f"(one DX {dx_w:.0f}×{dx_h:.0f} mm,  stitch {st_w:.0f}×{dx_h:.0f} mm)",
        color="0.92", fontsize=11,
    )
    ax.set_xlabel("object X (mm)", color="0.65")
    ax.set_ylabel("object Y (mm)", color="0.65")
    ax.tick_params(colors="0.55")
    for spine in ax.spines.values():
        spine.set_color("0.35")


def _native_xy(px_w, px_h, x0, x1, y0, y1):
    nx = max(2, int(round((x1 - x0) * hp.MAG * px_w / hp.SENSOR_W)))
    ny = max(2, int(round((y1 - y0) * hp.MAG * px_h / hp.SENSOR_H)))
    xs = np.linspace(x0, x1, nx)
    ys = np.linspace(y0, y1, ny)
    return xs, ys


def _siemens(xs, ys, spokes=36):
    gx, gy = np.meshgrid(xs, ys)
    ang = np.arctan2(gy - 0.5 * (ys[0] + ys[-1]), gx - 0.5 * (xs[0] + xs[-1]))
    val = (np.sin(ang * spokes) > 0).astype(np.float32)
    return np.stack([val, val, val], axis=-1)


def _stitch_px(px_w, px_h):
    return int(round(hp.STITCH_W / hp.SENSOR_W * px_w)), px_h


def plot_d7200(img, ext, dx_w, dx_h, st_w, y0, one, hyb, xs_d, ys_d, xs_s, ys_s):
    """Same DX field as el135_scene.png, plus native-pixel Siemens stars."""
    fig = plt.figure(figsize=(12.4, 10.2), facecolor="0.08")
    gs = fig.add_gridspec(
        3, 1, height_ratios=[1.15, 1.0, 1.0],
        hspace=0.38, left=0.06, right=0.98, top=0.93, bottom=0.07,
    )
    gs1 = gs[1].subgridspec(1, 2, width_ratios=[1.0, st_w / dx_w], wspace=0.10)
    gs2 = gs[2].subgridspec(1, 2, wspace=0.18)
    ax0 = fig.add_subplot(gs[0])
    ax1 = fig.add_subplot(gs1[0, 0])
    ax2 = fig.add_subplot(gs1[0, 1])
    ax3 = fig.add_subplot(gs2[0, 0])
    ax4 = fig.add_subplot(gs2[0, 1])
    for ax in (ax0, ax1, ax2, ax3, ax4):
        ax.set_facecolor("black")

    _object_plane(ax0, img, ext, dx_w, dx_h, st_w, y0)
    ax0.add_patch(Rectangle(
        (-STAR_MM / 2, -STAR_MM / 2), STAR_MM, STAR_MM,
        fill=False, ec="tomato", lw=1.2, ls="--", label=f"{STAR_MM:.0f} mm star",
    ))
    ax0.legend(loc="lower right", frameon=False, labelcolor="white")

    _panel(ax1, one, [xs_d[0], xs_d[-1], ys_d[0], ys_d[-1]],
           f"single DX  ·  {hp.SINGLE_FOV:.1f}°  ·  D7000 = D7200 window")
    _panel(ax2, hyb, [xs_s[0], xs_s[-1], ys_s[0], ys_s[-1]],
           f"hybrid T+R  ·  {hp.PANO_FOV:.1f}°  ·  {st_w / dx_w:.2f}×")

    for ax, (name, pw, ph, mp) in zip((ax3, ax4), BODIES):
        xs, ys = _native_xy(pw, ph, -STAR_MM / 2, STAR_MM / 2, -STAR_MM / 2, STAR_MM / 2)
        star = _siemens(xs, ys)
        sw, sh = _stitch_px(pw, ph)
        pitch = hp.SENSOR_W / pw * 1000.0
        _panel(
            ax, star, [xs[0], xs[-1], ys[0], ys[-1]],
            f"{name}  {mp:g} MP  ·  {pw}×{ph}  ·  {pitch:.1f} µm   "
            f"stitch {sw}×{sh}",
            interpolation="nearest",
        )

    fig.text(
        0.50, 0.012,
        "DX window is the same (23.6×15.6 mm). Stars are native photosites on "
        f"{STAR_MM:.0f}×{STAR_MM:.0f} mm of object.  "
        "scene: Radek Hloch / CC BY-SA 4.0",
        ha="center", color="0.45", fontsize=8,
    )
    DEST_D7200.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(DEST_D7200, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(DEST_D7200)


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

    _object_plane(ax0, img, ext, dx_w, dx_h, st_w, y0)
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
    plot_d7200(img, ext, dx_w, dx_h, st_w, y0, one, hyb, xs_d, ys_d, xs_s, ys_s)


if __name__ == "__main__":
    main()
