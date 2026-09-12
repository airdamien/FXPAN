#!/usr/bin/env python3
"""Ray-trace the dual chassis as a vapor camera (KrakenOS).

Same 135/5.6 thin lens and D7000 windows as hybrid_paths.py. A BK7
ExtraShape column stands in for a heat-gun jet (sag stronger than a
candle so the pixels move at this grid). Writes:

  docs/kraken/schlieren_paths.png     chief rays through the jet
  docs/kraken/schlieren_windows.png   hybrid toe vs same-image + knife
  docs/kraken/schlieren_bos.png       speckle BOS on the same-image pair
"""

from __future__ import annotations

import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.interpolate import griddata
from scipy.ndimage import map_coordinates

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hybrid_paths as hp

DEST = hp.OUT.parent / "docs" / "kraken"
WAVE = hp.WAVE
# Peak sag (mm) and 1/e width. Heat-gun scale, not room air.
PLUME_A = 0.12
PLUME_SIG = 8.0
PLATE_T = 2.0
PLUME_Z = 220.0  # mm in front of the card; long lever to the 135.


def _aim(src, pup):
    d = np.asarray(pup, dtype=float) - np.asarray(src, dtype=float)
    n = np.linalg.norm(d)
    if n < 1e-9:
        return [0.0, 0.0, 1.0]
    return (d / n).tolist()


def _plume_sag(x, y, E):
    a, sig = float(E[0]), float(E[1])
    return a * np.exp(-(np.asarray(x) ** 2) / (2.0 * sig * sig))


def camera(plume=True):
    """Object → optional BK7 column → 135 thin lens → DX image."""
    gap0 = PLUME_Z
    gap1 = hp.S_OBJ - gap0 - PLATE_T
    obj = hp.Kos.surf()
    obj.Thickness = gap0
    obj.Glass = "AIR"
    obj.Diameter = 220
    obj.Drawing = 0
    front = hp.Kos.surf()
    front.Thickness = PLATE_T
    front.Glass = "BK7"
    front.Diameter = 180
    front.Name = "plume"
    if plume:
        front.ExtraData = [_plume_sag, np.array([PLUME_A, PLUME_SIG])]
    back = hp.Kos.surf()
    back.Thickness = gap1
    back.Glass = "AIR"
    back.Diameter = 180
    lens = hp.Kos.surf()
    lens.Name = "EL"
    lens.Thin_Lens = hp.EL_F
    lens.Diameter = hp.EL_EPD
    lens.Thickness = hp.S_PRIME
    lens.Glass = "AIR"
    ima = hp.Kos.surf()
    ima.Name = "T"
    ima.Glass = "AIR"
    ima.Diameter = 80
    return hp._quiet_system([obj, front, back, lens, ima])


def pupil_xy(n=5):
    if n <= 1:
        return [(0.0, 0.0)]
    r = 0.72 * (hp.EL_EPD / 2.0)
    xs = np.linspace(-r, r, n)
    return [(x, y) for x in xs for y in xs if x * x + y * y <= r * r + 1e-9]


def _hit(sys_t, src, pup, knife=False):
    sys_t.Trace(src, _aim(src, [pup[0], pup[1], hp.S_OBJ]), WAVE)
    try:
        names = list(sys_t.NAME)
    except TypeError:
        return None
    if "T" not in names:
        return None
    xyz = hp._xyz(sys_t)
    if len(xyz) < 2:
        return None
    if knife and float(xyz[-2][0]) > 0.0:
        return None
    ost = hp._ost(sys_t)
    if len(ost) < 1:
        return None
    return float(ost[-1][0]), float(ost[-1][1])


def _speckle(seed=1, n=384):
    rng = np.random.RandomState(seed)
    z = rng.rand(n, n).astype(np.float32)
    return np.stack([z, z, z], axis=-1)


SPECKLE = _speckle()
SCENE_RGB = None
SCENE_EXT = None


def load_scene():
    global SCENE_RGB, SCENE_EXT
    path = hp.OUT.parent / "docs" / "kraken" / "countryside.jpg"
    img = np.asarray(plt.imread(path), dtype=np.float32)
    if img.max() > 1.5:
        img = img / 255.0
    img = np.clip(img[..., :3], 0.0, 1.0)
    # Same crop as hybrid_scene.py (tree left, farmhouse right).
    crop = img[270:660, 330:1230]
    h, w = crop.shape[:2]
    need_w = hp.STITCH_W / hp.MAG
    need_h = hp.SENSOR_H / hp.MAG
    obj_h = max(need_h, need_w * h / w)
    obj_w = obj_h * w / h
    SCENE_RGB = crop
    SCENE_EXT = np.array([-obj_w / 2.0, obj_w / 2.0, -obj_h / 2.0, obj_h / 2.0])


def _texture(kind, ox, oy):
    """ox, oy mesh in mm → RGB."""
    if kind == "scene":
        ext = SCENE_EXT
        rgb = SCENE_RGB
        u = (ox - ext[0]) / (ext[1] - ext[0]) * (rgb.shape[1] - 1)
        v = (ext[3] - oy) / (ext[3] - ext[2]) * (rgb.shape[0] - 1)
        out = np.stack(
            [
                map_coordinates(rgb[..., c], [v, u], order=1, mode="constant", cval=0.0)
                for c in range(3)
            ],
            axis=-1,
        )
        return np.clip(out, 0.0, 1.0).astype(np.float32)
    u = (ox / 80.0 + 0.5) * (SPECKLE.shape[1] - 1)
    v = (0.5 - oy / 56.0) * (SPECKLE.shape[0] - 1)
    out = np.stack(
        [
            map_coordinates(SPECKLE[..., c], [v, u], order=1, mode="wrap")
            for c in range(3)
        ],
        axis=-1,
    )
    return np.clip(out, 0.0, 1.0).astype(np.float32)


def _window(shift):
    return (-hp.HALF_W - shift, hp.HALF_W - shift, -hp.HALF_H, hp.HALF_H)


def trace_field(sys_t, ox, oy, knife=False, n_pup=1):
    """Kraken: object grid → mean image (x, y) and pupil-pass weight."""
    pupils = pupil_xy(n_pup)
    ny, nx = len(oy), len(ox)
    xi = np.full((ny, nx), np.nan)
    yi = np.full((ny, nx), np.nan)
    wt = np.zeros((ny, nx))
    for iy, y in enumerate(oy):
        for ix, x in enumerate(ox):
            src = [float(x), float(y), 0.0]
            sx = sy = n = 0.0
            for pup in pupils:
                hit = _hit(sys_t, src, pup, knife=knife)
                if hit is None:
                    continue
                sx += hit[0]
                sy += hit[1]
                n += 1.0
            if n:
                xi[iy, ix] = sx / n
                yi[iy, ix] = sy / n
                wt[iy, ix] = n / len(pupils)
    oxm = ox[None, :]
    oym = oy[:, None]
    xi = np.where(np.isfinite(xi), xi, -oxm * hp.MAG)
    yi = np.where(np.isfinite(yi), yi, -oym * hp.MAG)
    return xi, yi, wt


def render(field, kind, shift=0.0, wt_obj=None, nx=240, ny=160):
    """Inverse-warp a texture onto a sensor window through the Kraken map.

    Geometry comes from `field`. If `wt_obj` is set (the knife map), transmission
    is looked up in object space so a pupil cutoff is not turned into a field cut.
    """
    from scipy.interpolate import RegularGridInterpolator

    ox, oy, xi, yi, wt = field
    OY, OX = np.meshgrid(oy, ox, indexing="ij")
    x0, x1, y0, y1 = _window(shift)
    sx = np.linspace(x0, x1, nx)
    sy = np.linspace(y0, y1, ny)
    SX, SY = np.meshgrid(sx, sy)
    pts = np.column_stack([xi.ravel(), yi.ravel()])
    ox_s = griddata(pts, OX.ravel(), (SX, SY), method="linear")
    oy_s = griddata(pts, OY.ravel(), (SX, SY), method="linear")
    miss = ~np.isfinite(ox_s)
    ox_s = np.where(miss, 0.0, ox_s)
    oy_s = np.where(miss, 0.0, oy_s)
    if wt_obj is None:
        w = np.ones(ox_s.shape)
    else:
        _, _, _, _, wt_o = wt_obj
        fw = RegularGridInterpolator(
            (oy, ox), wt_o, bounds_error=False, fill_value=0.0
        )
        w = fw(np.stack([oy_s, ox_s], axis=-1))
    w = np.where(miss, 0.0, w)
    rgb = _texture(kind, ox_s, oy_s)
    rgb[miss] = 0.0
    rgb = (rgb * w[..., None]).astype(np.float32)
    local = (-hp.HALF_W, hp.HALF_W, -hp.HALF_H, hp.HALF_H)
    return rgb, local, w


def _gray(img):
    return img.mean(axis=-1)


def _diff(a, b):
    d = _gray(a) - _gray(b)
    lo, hi = np.percentile(d, (2, 98))
    if hi - lo < 1e-6:
        hi = lo + 1e-6
    v = np.clip((d - lo) / (hi - lo), 0.0, 1.0)
    return np.stack([v, v, v], axis=-1)


def _panel(ax, img, extent, title):
    ax.imshow(img, origin="lower", extent=extent, interpolation="nearest")
    ax.set_aspect("equal")
    ax.set_title(title, color="0.92", fontsize=10)
    ax.set_xlabel("image X (mm)", color="0.55", fontsize=8)
    ax.set_ylabel("image Y (mm)", color="0.55", fontsize=8)
    ax.tick_params(colors="0.5", labelsize=7)
    for spine in ax.spines.values():
        spine.set_color("0.35")
    ax.set_facecolor("black")


def _signed_dx(clear_f, plume_f, ext, shape):
    from scipy.interpolate import RegularGridInterpolator

    ox, oy, xi0, _, _ = clear_f
    _, _, xi1, _, _ = plume_f
    fd = RegularGridInterpolator(
        (oy, ox), xi1 - xi0, bounds_error=False, fill_value=np.nan
    )
    ys = np.linspace(ext[2], ext[3], shape[0])
    xs = np.linspace(ext[0], ext[1], shape[1])
    sy, sx = np.meshgrid(ys, xs, indexing="ij")
    return fd(np.stack([-sy / hp.MAG, -sx / hp.MAG], axis=-1))


def plot_windows(ht, hr, st, ext_h, ext_s, clear_f, plume_f, dest):
    fig, axes = plt.subplots(2, 3, figsize=(12.4, 7.4), facecolor="0.08")
    fig.subplots_adjust(left=0.05, right=0.99, top=0.88, bottom=0.10, wspace=0.18, hspace=0.38)
    _panel(axes[0, 0], ht, ext_h, "hybrid T  ·  toed −X window")
    _panel(axes[0, 1], hr, ext_h, "hybrid R  ·  toed +X window")
    _panel(axes[0, 2], _diff(ht, hr), ext_h, "hybrid T − R  ·  different scenes")
    _panel(axes[1, 0], st, ext_s, "same-image T  ·  brightfield")
    _panel(axes[1, 1], st, ext_s, "same-image R  ·  same pixels")
    dx = _signed_dx(clear_f, plume_f, ext_s, st.shape[:2])
    v = np.nanpercentile(np.abs(dx), 98)
    axes[1, 2].imshow(
        dx, origin="lower", extent=ext_s, cmap="RdBu_r",
        vmin=-v, vmax=v, interpolation="bilinear",
    )
    axes[1, 2].set_aspect("equal")
    axes[1, 2].set_title("same-image knife  ·  Kraken Δx (mm)", color="0.92", fontsize=10)
    axes[1, 2].set_xlabel("image X (mm)", color="0.55", fontsize=8)
    axes[1, 2].set_ylabel("image Y (mm)", color="0.55", fontsize=8)
    axes[1, 2].tick_params(colors="0.5", labelsize=7)
    for spine in axes[1, 2].spines.values():
        spine.set_color("0.35")
    for ax in axes.ravel():
        ax.set_facecolor("black")
        ax.axvline(0.0, color="goldenrod", lw=0.6, alpha=0.45)
    fig.suptitle(
        f"{hp.EL_NAME}  ·  D7000 DX  ·  jet at z={PLUME_Z:.0f} mm  ·  "
        f"object {hp.S_OBJ:.0f} mm",
        color="0.92",
        fontsize=13,
    )
    fig.text(
        0.50,
        0.015,
        "Top: current hybrid (4.6° toe) — subtract is two different halves.  "
        "Bottom: bsplit arms (toe=0) — same pixels, so a knife (here linearized from the ray walk) sees the jet.",
        ha="center",
        color="0.55",
        fontsize=8,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


def plot_bos(ref, flow, ext, clear_f, plume_f, dest):
    ox, oy, xi0, yi0, _ = clear_f
    _, _, xi1, yi1, _ = plume_f
    xs = ox[2:-2:2]
    ys = oy[2:-2:2]
    gx, gy, dx, dy = [], [], [], []
    ixs = [int(np.argmin(np.abs(ox - x))) for x in xs]
    iys = [int(np.argmin(np.abs(oy - y))) for y in ys]
    for iy in iys:
        for ix in ixs:
            if not (np.isfinite(xi0[iy, ix]) and np.isfinite(xi1[iy, ix])):
                continue
            gx.append(xi0[iy, ix])
            gy.append(yi0[iy, ix])
            dx.append(xi1[iy, ix] - xi0[iy, ix])
            dy.append(yi1[iy, ix] - yi0[iy, ix])
    shift_mag = np.hypot(dx, dy) if dx else np.array([0.0])

    fig, axes = plt.subplots(1, 3, figsize=(12.4, 4.0), facecolor="0.08")
    fig.subplots_adjust(left=0.05, right=0.99, top=0.84, bottom=0.16, wspace=0.20)
    _panel(axes[0], ref, ext, "same-image  ·  speckle, no plume")
    _panel(axes[1], flow, ext, "same-image  ·  speckle + plume")
    dmap = np.hypot(xi1 - xi0, yi1 - yi0)
    from scipy.interpolate import RegularGridInterpolator
    fd = RegularGridInterpolator((oy, ox), dmap, bounds_error=False, fill_value=np.nan)
    ys = np.linspace(ext[2], ext[3], ref.shape[0])
    xs = np.linspace(ext[0], ext[1], ref.shape[1])
    SY, SX = np.meshgrid(ys, xs, indexing="ij")
    heat = fd(np.stack([-SY / hp.MAG, -SX / hp.MAG], axis=-1))
    im = axes[2].imshow(
        heat, origin="lower", extent=ext, cmap="inferno",
        interpolation="bilinear",
    )
    axes[2].set_aspect("equal")
    axes[2].set_title("Kraken |Δ| on the sensor (mm)", color="0.92", fontsize=10)
    axes[2].set_xlabel("image X (mm)", color="0.55", fontsize=8)
    axes[2].set_ylabel("image Y (mm)", color="0.55", fontsize=8)
    axes[2].tick_params(colors="0.5", labelsize=7)
    for spine in axes[2].spines.values():
        spine.set_color("0.35")
    axes[2].set_facecolor("black")
    cb = fig.colorbar(im, ax=axes[2], fraction=0.046, pad=0.02)
    cb.set_label("shift (mm)", color="0.7")
    cb.ax.yaxis.set_tick_params(color="0.5")
    plt.setp(plt.getp(cb.ax.axes, "yticklabels"), color="0.6")
    if gx:
        axes[2].quiver(
            gx, gy, dx, dy,
            color="white", angles="xy", scale_units="xy",
            scale=0.12, width=0.004, pivot="tail",
        )
        axes[2].set_xlim(ext[0], ext[1])
        axes[2].set_ylim(ext[2], ext[3])
    fig.suptitle(
        "Background-oriented schlieren on toe=0  ·  one taking lens, both bodies see this",
        color="0.92",
        fontsize=12,
    )
    fig.text(
        0.50,
        0.02,
        "Correlate each body against its own still. Do not stitch first — "
        "the hybrid toe would look like flow. Quiver is Kraken chief-ray walk.",
        ha="center",
        color="0.55",
        fontsize=8,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)
    if len(shift_mag):
        print(
            f"BOS chief-ray |Δ|  mean={np.mean(shift_mag):.3f} mm  "
            f"max={np.max(shift_mag):.3f} mm"
        )


def plot_paths(dest):
    clear, plume = camera(False), camera(True)
    fig, (ax, ax2) = plt.subplots(
        1, 2, figsize=(11.2, 4.6), facecolor="0.08",
        gridspec_kw={"width_ratios": [1.35, 1.0]},
    )
    for a in (ax, ax2):
        a.set_facecolor("0.08")
        a.tick_params(colors="0.5")
        for spine in a.spines.values():
            spine.set_color("0.35")
    z_pl = PLUME_Z
    xs = np.array([-24, -16, -8, 0, 8, 16, 24], dtype=float)
    hits_c, hits_p = [], []
    for x0 in xs:
        src = [float(x0), 0.0, 0.0]
        d = _aim(src, [0.0, 0.0, hp.S_OBJ])
        clear.Trace(src, d, WAVE)
        plume.Trace(src, d, WAVE)
        c = hp._xyz(clear)
        p = hp._xyz(plume)
        if len(c) >= 2:
            ax.plot(c[:, 0], c[:, 2], color="0.45", lw=0.9)
            hits_c.append(float(c[-1][0]))
        if len(p) >= 2:
            ax.plot(p[:, 0], p[:, 2], color="tomato", lw=1.1)
            hits_p.append(float(p[-1][0]))
    ax.axhline(z_pl, color="goldenrod", lw=2.0, label="plume plate")
    ax.axhline(hp.S_OBJ, color="0.75", lw=1.2, label="135 thin lens")
    ax.axhline(hp.S_OBJ + hp.S_PRIME, color="steelblue", lw=2.0, label="sensor")
    ax.set_xlabel("X (mm)", color="0.65")
    ax.set_ylabel("Z (mm)  object at 0", color="0.65")
    ax.set_title("chief rays  ·  X stretched", color="0.92")
    ax.legend(loc="lower right", frameon=False, labelcolor="0.8")
    ax.set_xlim(-32, 32)
    ax.set_ylim(-20, hp.S_OBJ + hp.S_PRIME + 30)
    yy = np.arange(len(hits_c))
    ax2.hlines(yy, hits_c, hits_p, color="0.45", lw=1.0)
    ax2.plot(hits_c, yy, "o", color="0.65", label="clear")
    ax2.plot(hits_p, yy, "o", color="tomato", label="plume")
    ax2.set_yticks(yy)
    ax2.set_yticklabels([f"{x:.0f} mm" for x in xs], color="0.6")
    ax2.set_xlabel("image X (mm)", color="0.65")
    ax2.set_title("sensor walk", color="0.92")
    ax2.legend(loc="best", frameon=False, labelcolor="0.8")
    ax2.axvline(0.0, color="goldenrod", lw=0.7, alpha=0.5)
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(dest, dpi=140, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)


def object_axes():
    x_max = (hp.STITCH_W / 2.0) / hp.MAG + 8.0
    y_max = (hp.SENSOR_H / 2.0) / hp.MAG + 4.0
    return np.linspace(-x_max, x_max, 33), np.linspace(-y_max, y_max, 23)


def main():
    hp.apply_chassis(46.5, 23.6, 15.6)
    hp.apply_lens("EL-Nikkor 135/5.6", 135.0, 5.6)
    print(
        f"{hp.EL_NAME}  s={hp.S_OBJ:.1f} mm  s'={hp.S_PRIME:.1f} mm  "
        f"m={hp.MAG:.3f}  toe shift={hp.SHIFT:.2f} mm",
        flush=True,
    )
    load_scene()
    plot_paths(DEST / "schlieren_paths.png")

    ox, oy = object_axes()
    print("Kraken field: clear / plume…", flush=True)
    clear_f = (ox, oy, *trace_field(camera(False), ox, oy))
    plume_f = (ox, oy, *trace_field(camera(True), ox, oy))

    ht, ext_h, _ = render(plume_f, "scene", shift=+hp.SHIFT)
    hr, _, _ = render(plume_f, "scene", shift=-hp.SHIFT)
    st, ext_s, _ = render(plume_f, "scene", shift=0.0)
    plot_windows(ht, hr, st, ext_h, ext_s, clear_f, plume_f, DEST / "schlieren_windows.png")

    ref, ext_b, _ = render(clear_f, "speckle", shift=0.0)
    flow, _, _ = render(plume_f, "speckle", shift=0.0)
    plot_bos(ref, flow, ext_b, clear_f, plume_f, DEST / "schlieren_bos.png")


if __name__ == "__main__":
    main()
