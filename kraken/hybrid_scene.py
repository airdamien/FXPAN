#!/usr/bin/env python3
"""Texture the hybrid and V object planes with a countryside still.

Kraken maps each object point through the 135/5.6 onto the two toed
hybrid windows. The V uses the hard-knife look-across in params.scad
(no plate). Figures: D7000 DX, V, V-vs-hybrid, 5D Mk III, A7,
D7000-vs-5D3, D7000-vs-A7, D7000-vs-D7200 stars.
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
DEST_5D3 = hp.OUT.parent / "docs" / "kraken" / "el135_5d3_scene.png"
DEST_CMP = hp.OUT.parent / "docs" / "kraken" / "el135_d7000_5d3.png"
DEST_A7 = hp.OUT.parent / "docs" / "kraken" / "el135_a7_scene.png"
DEST_A7_CMP = hp.OUT.parent / "docs" / "kraken" / "el135_d7000_a7.png"
DEST_V = hp.OUT.parent / "docs" / "kraken" / "el135_v_scene.png"
DEST_V_CMP = hp.OUT.parent / "docs" / "kraken" / "el135_v_hybrid.png"
# 1280×853 still: lone tree on the left, farmhouse / cypresses on the right.
CROP_XY = (330, 270, 1230, 660)
BODIES = (
    ("D7000", 4928, 3264, 16.2),
    ("D7200", 6000, 4000, 24.2),
)
# flange mm, sensor mm, native pixels
D7000 = dict(name="D7000", flange=46.5, sw=23.6, sh=15.6,
             px_w=4928, px_h=3264, mp=16.2, color="deepskyblue", stitch="steelblue")
FF5D3 = dict(name="5D Mk III", flange=44.0, sw=36.0, sh=24.0,
             px_w=5760, px_h=3840, mp=22.3, color="coral", stitch="goldenrod")
A7 = dict(name="A7", flange=18.0, sw=35.8, sh=23.9,
          px_w=6000, px_h=4000, mp=24.3, color="mediumorchid", stitch="gold")
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


def _extent_fit(img, need_w, need_h):
    h, w = img.shape[:2]
    aspect = w / float(h)
    obj_h = max(need_h, need_w / aspect)
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


def _object_plane(ax, img, ext, boxes, title):
    ax.imshow(img, origin="upper", extent=ext, interpolation="bilinear")
    for x, y, w, h, ec, label in boxes:
        ax.add_patch(Rectangle(
            (x, y), w, h, fill=False, ec=ec, lw=1.8, label=label,
        ))
    ax.set_aspect("equal")
    pad_x = 0.08 * (ext[1] - ext[0])
    pad_y = 0.06 * (ext[3] - ext[2])
    ax.set_xlim(ext[0] - pad_x, ext[1] + pad_x)
    ax.set_ylim(ext[2] - pad_y, ext[3] + pad_y)
    ax.legend(loc="lower right", frameon=False, labelcolor="white")
    ax.set_title(title, color="0.92", fontsize=11)
    ax.set_xlabel("object X (mm)", color="0.65")
    ax.set_ylabel("object Y (mm)", color="0.65")
    ax.tick_params(colors="0.55")
    for spine in ax.spines.values():
        spine.set_color("0.35")


def _native_xy(px_w, px_h, sw, sh, x0, x1, y0, y1, mag):
    nx = max(2, int(round((x1 - x0) * mag * px_w / sw)))
    ny = max(2, int(round((y1 - y0) * mag * px_h / sh)))
    xs = np.linspace(x0, x1, nx)
    ys = np.linspace(y0, y1, ny)
    return xs, ys


def _siemens(xs, ys, spokes=36):
    gx, gy = np.meshgrid(xs, ys)
    ang = np.arctan2(gy - 0.5 * (ys[0] + ys[-1]), gx - 0.5 * (xs[0] + xs[-1]))
    val = (np.sin(ang * spokes) > 0).astype(np.float32)
    return np.stack([val, val, val], axis=-1)


def _stitch_px(px_w, px_h, st_w, sw):
    return int(round(st_w / sw * px_w)), px_h


def _setup(body):
    hp.apply_chassis(body["flange"], body["sw"], body["sh"])
    hp.apply_lens("EL-Nikkor 135/5.6", 135.0, 5.6)
    return dict(
        name=body["name"],
        sw=hp.SENSOR_W, sh=hp.SENSOR_H, st=hp.STITCH_W,
        mag=hp.MAG, s_obj=hp.S_OBJ,
        dx_w=hp.SENSOR_W / hp.MAG, dx_h=hp.SENSOR_H / hp.MAG,
        st_w=hp.STITCH_W / hp.MAG,
        fov=hp.SINGLE_FOV, pano=hp.PANO_FOV,
        px_w=body["px_w"], px_h=body["px_h"], mp=body["mp"],
        color=body["color"], stitch=body["stitch"],
        pitch=body["sw"] / body["px_w"] * 1000.0,
    )


def _grab(img, ext, f):
    y0, y1 = -f["dx_h"] / 2.0, f["dx_h"] / 2.0
    ny = 320
    nx_st = max(2, int(round(ny * f["st_w"] / f["dx_h"])))
    nx_dx = max(2, int(round(ny * f["dx_w"] / f["dx_h"])))
    xs_d, ys_d, one = _sample(
        img, ext, -f["dx_w"] / 2, f["dx_w"] / 2, y0, y1, nx_dx, ny,
    )
    xs_s, ys_s, hyb = _sample(
        img, ext, -f["st_w"] / 2, f["st_w"] / 2, y0, y1, nx_st, ny,
    )
    sys_t = hp.transmit_system(focal=True)
    thx, thy, t_frac, r_frac, counts = hp.trace_frames(sys_t)
    cover = _mask(thx, thy, t_frac, r_frac, xs_s, ys_s)
    hyb = hyb * (cover > 0.15)[..., None]
    return dict(one=one, hyb=hyb, xs_d=xs_d, ys_d=ys_d, xs_s=xs_s, ys_s=ys_s,
                y0=y0, counts=counts)


def _boxes(f, extra=()):
    y0 = -f["dx_h"] / 2.0
    rows = [
        (-f["dx_w"] / 2, y0, f["dx_w"], f["dx_h"], f["color"],
         f"single {f['name']}"),
        (-f["st_w"] / 2, y0, f["st_w"], f["dx_h"], f["stitch"],
         f"{f['name']} stitch"),
    ]
    rows.extend(extra)
    return rows


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

    _object_plane(
        ax0, img, ext,
        [
            (-dx_w / 2, y0, dx_w, dx_h, "deepskyblue", "single DX"),
            (-st_w / 2, y0, st_w, dx_h, "goldenrod", "hybrid stitch"),
            (-STAR_MM / 2, -STAR_MM / 2, STAR_MM, STAR_MM, "tomato",
             f"{STAR_MM:.0f} mm star"),
        ],
        f"{hp.EL_NAME} at {hp.S_OBJ:.0f} mm  ·  object plane  "
        f"(one DX {dx_w:.0f}×{dx_h:.0f} mm,  stitch {st_w:.0f}×{dx_h:.0f} mm)",
    )

    _panel(ax1, one, [xs_d[0], xs_d[-1], ys_d[0], ys_d[-1]],
           f"single DX  ·  {hp.SINGLE_FOV:.1f}°  ·  D7000 = D7200 window")
    _panel(ax2, hyb, [xs_s[0], xs_s[-1], ys_s[0], ys_s[-1]],
           f"hybrid T+R  ·  {hp.PANO_FOV:.1f}°  ·  {st_w / dx_w:.2f}×")

    for ax, (name, pw, ph, mp) in zip((ax3, ax4), BODIES):
        xs, ys = _native_xy(pw, ph, hp.SENSOR_W, hp.SENSOR_H,
                            -STAR_MM / 2, STAR_MM / 2, -STAR_MM / 2, STAR_MM / 2,
                            hp.MAG)
        star = _siemens(xs, ys)
        sw, sh = _stitch_px(pw, ph, hp.STITCH_W, hp.SENSOR_W)
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


def _v_geom(f, overlap_frac=None):
    """Hard V: each full DX frame looks across the knife by OVERLAP_FRAC.

    L covers [-dx_w + ol, +ol], R covers [-ol, +dx_w - ol].
    Stitch is  (2 - 2×overlap) × one frame — 1.6× at the default 0.20.
    Unique halves stay full brightness (no 50/50).
    """
    ol = f["dx_w"] * (hp.OVERLAP_FRAC if overlap_frac is None else overlap_frac)
    l0, l1 = -f["dx_w"] + ol, ol
    r0, r1 = -ol, f["dx_w"] - ol
    st_w = r1 - l0
    st_img = st_w * f["mag"]
    pano = 2.0 * np.degrees(np.arctan((st_img / 2.0) / hp.PATH_TOTAL))
    return dict(
        l0=l0, l1=l1, r0=r0, r1=r1, st0=l0, st1=r1,
        st_w=st_w, st=st_img, ol=ol, pano=pano,
        px_st=int(round(st_img / f["sw"] * f["px_w"])),
    )


def _v_grab(img, ext, f, g):
    y0, y1 = -f["dx_h"] / 2.0, f["dx_h"] / 2.0
    ny = 320

    def samp(x0, x1):
        nx = max(2, int(round(ny * (x1 - x0) / f["dx_h"])))
        return _sample(img, ext, x0, x1, y0, y1, nx, ny)

    xs_l, ys, left = samp(g["l0"], g["l1"])
    xs_r, _, right = samp(g["r0"], g["r1"])
    xs_s, _, st = samp(g["st0"], g["st1"])
    return dict(left=left, right=right, hyb=st, xs_l=xs_l, xs_r=xs_r,
                xs_s=xs_s, ys_d=ys, y0=y0)


def _v_boxes(f, g):
    y0 = -f["dx_h"] / 2.0
    return [
        (g["l0"], y0, f["dx_w"], f["dx_h"], "coral", "V L  (across knife)"),
        (g["r0"], y0, f["dx_w"], f["dx_h"], "mediumseagreen", "V R  (across knife)"),
        (g["st0"], y0, g["st_w"], f["dx_h"], "goldenrod", "V stitch  1.6×"),
    ]


def plot_v_scene(img, ext, f, g, grab, dest):
    fig = plt.figure(figsize=(12.4, 10.4), facecolor="0.08")
    gs = fig.add_gridspec(
        3, 1, height_ratios=[1.15, 1.0, 1.05],
        hspace=0.36, left=0.06, right=0.98, top=0.93, bottom=0.07,
    )
    gs1 = gs[1].subgridspec(1, 2, wspace=0.10)
    ax0 = fig.add_subplot(gs[0])
    ax1 = fig.add_subplot(gs1[0, 0])
    ax2 = fig.add_subplot(gs1[0, 1])
    ax3 = fig.add_subplot(gs[2])
    for ax in (ax0, ax1, ax2, ax3):
        ax.set_facecolor("black")
    _object_plane(
        ax0, img, ext, _v_boxes(f, g),
        f"{hp.EL_NAME} at {f['s_obj']:.0f} mm  ·  V knife  "
        f"(one DX {f['dx_w']:.0f}×{f['dx_h']:.0f} mm,  "
        f"stitch {g['st_w']:.0f}×{f['dx_h']:.0f} mm)",
    )
    _panel(ax1, grab["left"],
           [grab["xs_l"][0], grab["xs_l"][-1], grab["ys_d"][0], grab["ys_d"][-1]],
           f"V L  ·  looks {hp.OVERLAP_FRAC * 100:.0f}% across the knife")
    _panel(ax2, grab["right"],
           [grab["xs_r"][0], grab["xs_r"][-1], grab["ys_d"][0], grab["ys_d"][-1]],
           f"V R  ·  looks {hp.OVERLAP_FRAC * 100:.0f}% across the knife")
    _panel(ax3, grab["hyb"],
           [grab["xs_s"][0], grab["xs_s"][-1], grab["ys_d"][0], grab["ys_d"][-1]],
           f"V L+R stitch  ·  {g['pano']:.1f}°  ·  {g['st_w'] / f['dx_w']:.2f}×  ·  "
           f"full brightness")
    fig.text(
        0.50, 0.012,
        "Hard field split, not a 50/50. Unique halves keep a stop. Overlap is "
        f"{g['ol']:.0f} mm of object / {g['ol'] * f['mag']:.1f} mm on the sensor "
        f"(~{int(round(g['ol'] * f['mag'] / f['sw'] * f['px_w']))} px).  "
        "scene: Radek Hloch / CC BY-SA 4.0",
        ha="center", color="0.45", fontsize=8,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


def plot_v_hybrid(img, ext, f, vg, vgrab, hgrab, dest):
    fig = plt.figure(figsize=(13.0, 12.6), facecolor="0.08")
    gs = fig.add_gridspec(
        4, 1, height_ratios=[1.2, 1.0, 1.05, 0.9],
        hspace=0.40, left=0.06, right=0.98, top=0.94, bottom=0.06,
    )
    gs1 = gs[1].subgridspec(1, 2, wspace=0.10)
    gs2 = gs[2].subgridspec(1, 2, width_ratios=[vg["st_w"] / f["dx_w"],
                                               f["st_w"] / f["dx_w"]], wspace=0.10)
    gs3 = gs[3].subgridspec(1, 2, wspace=0.18)
    ax0 = fig.add_subplot(gs[0])
    ax1 = fig.add_subplot(gs1[0, 0])
    ax2 = fig.add_subplot(gs1[0, 1])
    ax3 = fig.add_subplot(gs2[0, 0])
    ax4 = fig.add_subplot(gs2[0, 1])
    ax5 = fig.add_subplot(gs3[0, 0])
    ax6 = fig.add_subplot(gs3[0, 1])
    for ax in (ax0, ax1, ax2, ax3, ax4, ax5, ax6):
        ax.set_facecolor("black")
    _object_plane(
        ax0, img, ext,
        _v_boxes(f, vg) + _boxes(f) + [
            (-STAR_MM / 2, -STAR_MM / 2, STAR_MM, STAR_MM, "tomato",
             f"{STAR_MM:.0f} mm star"),
        ],
        f"{hp.EL_NAME}  ·  V knife vs hybrid L on the same countryside",
    )
    _panel(ax1, vgrab["left"],
           [vgrab["xs_l"][0], vgrab["xs_l"][-1], vgrab["ys_d"][0], vgrab["ys_d"][-1]],
           f"V L  ·  left half + {hp.OVERLAP_FRAC * 100:.0f}%")
    _panel(ax2, vgrab["right"],
           [vgrab["xs_r"][0], vgrab["xs_r"][-1], vgrab["ys_d"][0], vgrab["ys_d"][-1]],
           f"V R  ·  right half + {hp.OVERLAP_FRAC * 100:.0f}%")
    _panel(ax3, vgrab["hyb"],
           [vgrab["xs_s"][0], vgrab["xs_s"][-1], vgrab["ys_d"][0], vgrab["ys_d"][-1]],
           f"V stitch  {vg['st']:.1f} mm  ·  {vg['pano']:.1f}°  ·  "
           f"{vg['st_w'] / f['dx_w']:.2f}×  ·  full stop")
    _panel(ax4, hgrab["hyb"],
           [hgrab["xs_s"][0], hgrab["xs_s"][-1], hgrab["ys_s"][0], hgrab["ys_s"][-1]],
           f"hybrid stitch  {f['st']:.1f} mm  ·  {f['pano']:.1f}°  ·  "
           f"{f['st_w'] / f['dx_w']:.2f}×  ·  −1 stop")
    for ax, st_img, label, px_st in (
        (ax5, vg["st"], "V", vg["px_st"]),
        (ax6, f["st"], "hybrid L", int(round(f["st"] / f["sw"] * f["px_w"]))),
    ):
        xs, ys = _native_xy(
            f["px_w"], f["px_h"], f["sw"], f["sh"],
            -STAR_MM / 2, STAR_MM / 2, -STAR_MM / 2, STAR_MM / 2, f["mag"],
        )
        _panel(
            ax, _siemens(xs, ys), [xs[0], xs[-1], ys[0], ys[-1]],
            f"{label}  D7000  {f['mp']:g} MP  ·  {f['pitch']:.1f} µm   "
            f"stitch {px_st}×{f['px_h']}",
            interpolation="nearest",
        )
    fig.text(
        0.50, 0.012,
        "Same D7000s, same 135, same 173.5 mm path. V is a hard knife (1.6×, full "
        "brightness). Hybrid is two toed DX windows on a 50/50 (1.8×, −1 stop).  "
        f"Stars are native photosites on {STAR_MM:.0f}×{STAR_MM:.0f} mm of object.  "
        "scene: Radek Hloch / CC BY-SA 4.0",
        ha="center", color="0.45", fontsize=8,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


def _save_scene(img, ext, f, grab, dest, single_label):
    fig = plt.figure(figsize=(12.4, 7.8), facecolor="0.08")
    gs = fig.add_gridspec(
        2, 2, height_ratios=[1.12, 1.0],
        width_ratios=[1.0, f["st_w"] / f["dx_w"]],
        hspace=0.34, wspace=0.10, left=0.06, right=0.98, top=0.90, bottom=0.10,
    )
    ax0 = fig.add_subplot(gs[0, :])
    ax1 = fig.add_subplot(gs[1, 0])
    ax2 = fig.add_subplot(gs[1, 1])
    for ax in (ax0, ax1, ax2):
        ax.set_facecolor("black")
    _object_plane(
        ax0, img, ext, _boxes(f),
        f"{hp.EL_NAME} at {f['s_obj']:.0f} mm  ·  object plane  "
        f"(one {f['name']} {f['dx_w']:.0f}×{f['dx_h']:.0f} mm,  "
        f"stitch {f['st_w']:.0f}×{f['dx_h']:.0f} mm)",
    )
    _panel(ax1, grab["one"],
           [grab["xs_d"][0], grab["xs_d"][-1], grab["ys_d"][0], grab["ys_d"][-1]],
           f"{single_label}  ·  {f['fov']:.1f}°")
    _panel(ax2, grab["hyb"],
           [grab["xs_s"][0], grab["xs_s"][-1], grab["ys_s"][0], grab["ys_s"][-1]],
           f"hybrid T+R stitch  ·  {f['pano']:.1f}°  ·  {f['st_w'] / f['dx_w']:.2f}×")
    fig.text(
        0.50, 0.015,
        "scene: Radek Hloch / CC BY-SA 4.0  ·  Wikimedia File:Landscape of Tuscany 3.jpg",
        ha="center", color="0.45", fontsize=8,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


def plot_compare(img, ext, a, ga, b, gb, dest, note):
    fig = plt.figure(figsize=(13.0, 13.2), facecolor="0.08")
    gs = fig.add_gridspec(
        4, 1, height_ratios=[1.2, 1.0, 1.0, 0.95],
        hspace=0.42, left=0.06, right=0.98, top=0.95, bottom=0.06,
    )
    gs1 = gs[1].subgridspec(1, 2, width_ratios=[1.0, a["st_w"] / a["dx_w"]], wspace=0.10)
    gs2 = gs[2].subgridspec(1, 2, width_ratios=[1.0, b["st_w"] / b["dx_w"]], wspace=0.10)
    gs3 = gs[3].subgridspec(1, 2, wspace=0.18)
    ax0 = fig.add_subplot(gs[0])
    ax1 = fig.add_subplot(gs1[0, 0])
    ax2 = fig.add_subplot(gs1[0, 1])
    ax3 = fig.add_subplot(gs2[0, 0])
    ax4 = fig.add_subplot(gs2[0, 1])
    ax5 = fig.add_subplot(gs3[0, 0])
    ax6 = fig.add_subplot(gs3[0, 1])
    for ax in (ax0, ax1, ax2, ax3, ax4, ax5, ax6):
        ax.set_facecolor("black")

    _object_plane(
        ax0, img, ext,
        _boxes(a) + _boxes(b) + [
            (-STAR_MM / 2, -STAR_MM / 2, STAR_MM, STAR_MM, "tomato",
             f"{STAR_MM:.0f} mm star"),
        ],
        f"{hp.EL_NAME}  ·  {a['name']} vs {b['name']} on the same countryside",
    )
    _panel(ax1, ga["one"],
           [ga["xs_d"][0], ga["xs_d"][-1], ga["ys_d"][0], ga["ys_d"][-1]],
           f"{a['name']} single  {a['sw']:.1f}×{a['sh']:.1f} mm  ·  {a['fov']:.1f}°")
    _panel(ax2, ga["hyb"],
           [ga["xs_s"][0], ga["xs_s"][-1], ga["ys_s"][0], ga["ys_s"][-1]],
           f"{a['name']} stitch  {a['st']:.1f} mm  ·  {a['pano']:.1f}°  ·  "
           f"{a['st_w'] / a['dx_w']:.2f}×")
    _panel(ax3, gb["one"],
           [gb["xs_d"][0], gb["xs_d"][-1], gb["ys_d"][0], gb["ys_d"][-1]],
           f"{b['name']} single  {b['sw']:.1f}×{b['sh']:.1f} mm  ·  {b['fov']:.1f}°")
    _panel(ax4, gb["hyb"],
           [gb["xs_s"][0], gb["xs_s"][-1], gb["ys_s"][0], gb["ys_s"][-1]],
           f"{b['name']} stitch  {b['st']:.1f} mm  ·  {b['pano']:.1f}°  ·  "
           f"{b['st_w'] / b['dx_w']:.2f}×")

    for ax, f in ((ax5, a), (ax6, b)):
        xs, ys = _native_xy(
            f["px_w"], f["px_h"], f["sw"], f["sh"],
            -STAR_MM / 2, STAR_MM / 2, -STAR_MM / 2, STAR_MM / 2, f["mag"],
        )
        star = _siemens(xs, ys)
        sw, sh = _stitch_px(f["px_w"], f["px_h"], f["st"], f["sw"])
        _panel(
            ax, star, [xs[0], xs[-1], ys[0], ys[-1]],
            f"{f['name']}  {f['mp']:g} MP  ·  {f['px_w']}×{f['px_h']}  ·  "
            f"{f['pitch']:.1f} µm   stitch {sw}×{sh}",
            interpolation="nearest",
        )

    fig.text(
        0.50, 0.012,
        note + f"  Stars are native photosites on {STAR_MM:.0f}×{STAR_MM:.0f} mm of object.  "
        "scene: Radek Hloch / CC BY-SA 4.0",
        ha="center", color="0.45", fontsize=8,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


def main():
    if not SCENE.is_file():
        raise SystemExit(f"missing scene still: {SCENE}")

    raw = _photo(SCENE)
    x0, y0c, x1, y1c = CROP_XY
    crop = raw[y0c:y1c, x0:x1]

    dx = _setup(D7000)
    ext_dx = _extent(crop)
    g_dx = _grab(crop, ext_dx, dx)
    _save_scene(crop, ext_dx, dx, g_dx, DEST, "single D7000 DX")
    print(
        f"{hp.EL_NAME}  D7000  T-only={g_dx['counts']['left']}  "
        f"overlap={g_dx['counts']['overlap']}  R-only={g_dx['counts']['right']}"
    )
    plot_d7200(
        crop, ext_dx, dx["dx_w"], dx["dx_h"], dx["st_w"], g_dx["y0"],
        g_dx["one"], g_dx["hyb"], g_dx["xs_d"], g_dx["ys_d"],
        g_dx["xs_s"], g_dx["ys_s"],
    )

    vg = _v_geom(dx)
    g_v = _v_grab(crop, ext_dx, dx, vg)
    plot_v_scene(crop, ext_dx, dx, vg, g_v, DEST_V)
    print(
        f"{hp.EL_NAME}  V  stitch={vg['st']:.1f} mm  object={vg['st_w']:.0f} mm  "
        f"pano={vg['pano']:.1f} deg  overlap={vg['ol'] * dx['mag']:.1f} mm  "
        f"px={vg['px_st']}x{dx['px_h']}"
    )
    plot_v_hybrid(crop, ext_dx, dx, vg, g_v, g_dx, DEST_V_CMP)

    ff = _setup(FF5D3)
    ext_ff = _extent(raw)
    g_ff = _grab(raw, ext_ff, ff)
    _save_scene(raw, ext_ff, ff, g_ff, DEST_5D3, "single 5D Mk III FF")
    print(
        f"{hp.EL_NAME}  5D3  T-only={g_ff['counts']['left']}  "
        f"overlap={g_ff['counts']['overlap']}  R-only={g_ff['counts']['right']}"
    )

    ext_cmp = _extent_fit(raw, ff["st_w"], ff["dx_h"])
    dx = _setup(D7000)
    g_dx_c = _grab(raw, ext_cmp, dx)
    ff = _setup(FF5D3)
    g_ff_c = _grab(raw, ext_cmp, ff)
    plot_compare(
        raw, ext_cmp, dx, g_dx_c, ff, g_ff_c, DEST_CMP,
        "Same Tuscany still. D7000 is 23.6×15.6 / 4.8 µm; 5D Mk III is 36×24 / 6.25 µm.",
    )

    a7 = _setup(A7)
    ext_a7 = _extent(raw)
    g_a7 = _grab(raw, ext_a7, a7)
    _save_scene(raw, ext_a7, a7, g_a7, DEST_A7, "single A7 FF")
    print(
        f"{hp.EL_NAME}  A7  T-only={g_a7['counts']['left']}  "
        f"overlap={g_a7['counts']['overlap']}  R-only={g_a7['counts']['right']}"
    )
    ext_a7c = _extent_fit(raw, a7["st_w"], a7["dx_h"])
    dx = _setup(D7000)
    g_dx_a = _grab(raw, ext_a7c, dx)
    a7 = _setup(A7)
    g_a7_c = _grab(raw, ext_a7c, a7)
    plot_compare(
        raw, ext_a7c, dx, g_dx_a, a7, g_a7_c, DEST_A7_CMP,
        "Same still. D7000 PATH=173.5 mm / 4.8 µm; A7 PATH=145 mm (E 18 mm) / 6.0 µm. "
        "135 focuses ~2 m on the A7 fork.",
    )


if __name__ == "__main__":
    main()
