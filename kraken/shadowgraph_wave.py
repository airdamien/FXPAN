#!/usr/bin/env python3
"""Does a Fourier plate or a Fresnel FFT help the bullet shadowgraph?

Same OPD as shadowgraph_scene.py (Kraken ExtraShape / Gladstone–Dale).
Compares: geometric shim, Fresnel at the chassis defocus, Fresnel at a
lab throw, a Zernike phase dot in the Fourier plane, and a Fourier knife.
Writes docs/kraken/shadowgraph_wave.png.
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
import shadowgraph_scene as sg

DEST = hp.OUT.parent / "docs" / "kraken"
LAM = 0.00055  # mm
N1 = sg.N_BK7 - 1.0


def _grid(nx=768, ny=512):
    x_max = hp.HALF_W / hp.MAG
    y_max = hp.HALF_H / hp.MAG
    ox = np.linspace(-x_max, x_max, nx)
    oy = np.linspace(-y_max, y_max, ny)
    OY, OX = np.meshgrid(oy, ox, indexing="ij")
    return ox, oy, OX, OY, (-x_max * hp.MAG, x_max * hp.MAG, -y_max * hp.MAG, y_max * hp.MAG)


def object_field(OX, OY):
    sag = sg.bullet_sag(OX, OY, sg._E())
    amp = np.where(sg._in_bullet(OX, OY), 0.0, 1.0)
    return amp * np.exp(1j * (2.0 * np.pi / LAM) * N1 * sag)


def fresnel(A, dx, dy, z):
    ny, nx = A.shape
    fx = np.fft.fftfreq(nx, dx)
    fy = np.fft.fftfreq(ny, dy)
    FX, FY = np.meshgrid(fx, fy)
    arg = 1.0 - (LAM * FX) ** 2 - (LAM * FY) ** 2
    H = np.zeros_like(arg, dtype=np.complex128)
    ok = arg > 0
    H[ok] = np.exp(2j * np.pi * z / LAM * np.sqrt(arg[ok]))
    return np.fft.ifft2(np.fft.fft2(A) * H)


def fourier_plate(A, kind):
    F = np.fft.fftshift(np.fft.fft2(A))
    ny, nx = A.shape
    cy, cx = ny // 2, nx // 2
    Y, X = np.ogrid[:ny, :nx]
    if kind == "knife":
        F[:, cx:] = 0
    elif kind == "zernike":
        r2 = (X - cx) ** 2 + (Y - cy) ** 2
        F[r2 <= (0.014 * min(nx, ny)) ** 2] *= np.exp(1j * np.pi / 2.0)
    return np.fft.ifft2(np.fft.ifftshift(F))


def _show(I, live=None):
    I = np.asarray(I, dtype=float)
    if live is None:
        live = I > 0.02 * np.max(I)
    if not np.any(live):
        live = np.ones_like(I, dtype=bool)
    lo, hi = np.percentile(I[live], (2, 99.5))
    return np.clip((I - lo) / (hi - lo + 1e-12), 0.0, 1.0)


def _panel(ax, img, extent, title):
    ax.imshow(img, origin="lower", extent=extent, cmap="gray", vmin=0, vmax=1,
              interpolation="nearest")
    ax.set_aspect("equal")
    ax.set_title(title, color="0.92", fontsize=9)
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_facecolor("black")
    for spine in ax.spines.values():
        spine.set_color("0.3")


def main():
    hp.apply_chassis(46.5, 23.6, 15.6)
    hp.apply_lens("EL-Nikkor 135/5.6", 135.0, 5.6)
    z_shim = sg.SHIM / (hp.MAG ** 2)
    z_lab = 250.0
    print(
        f"{hp.EL_NAME}  m={hp.MAG:.3f}  z_shim={z_shim:.1f} mm  "
        f"z_lab={z_lab:.0f} mm  λ={LAM * 1e6:.0f} nm",
        flush=True,
    )

    ox, oy, OX, OY, ext = _grid()
    dx, dy = ox[1] - ox[0], oy[1] - oy[0]
    A = object_field(OX, OY)
    live = ~sg._in_bullet(OX, OY)

    _, geom, _ = sg.shadow_maps(z_shim, nx=len(ox), ny=len(oy))
    I_f0 = _show(np.abs(A) ** 2, live)
    I_fz = _show(np.abs(fresnel(A, dx, dy, z_shim)) ** 2, live)
    I_lab = _show(np.abs(fresnel(A, dx, dy, z_lab)) ** 2, live)
    I_zk = _show(np.abs(fourier_plate(A, "zernike")) ** 2)
    I_kn = _show(np.abs(fourier_plate(A, "knife")) ** 2)

    fig, axes = plt.subplots(2, 3, figsize=(12.4, 7.2), facecolor="0.08")
    fig.subplots_adjust(left=0.03, right=0.99, top=0.90, bottom=0.07, wspace=0.06, hspace=0.18)
    _panel(axes[0, 0], geom, ext, f"geometric shim  ·  z={z_shim:.1f} mm")
    _panel(axes[0, 1], I_fz, ext, f"Fresnel FFT  ·  same z={z_shim:.1f} mm")
    _panel(axes[0, 2], I_lab, ext, f"Fresnel FFT  ·  lab throw {z_lab:.0f} mm")
    _panel(axes[1, 0], I_zk, ext, "Fourier phase dot  ·  Zernike π/2")
    _panel(axes[1, 1], I_kn, ext, "Fourier knife  ·  half-plane")
    if sg.REF.exists():
        axes[1, 2].imshow(plt.imread(sg.REF))
        axes[1, 2].set_title("Settles  ·  collimated spark", color="0.92", fontsize=9)
    axes[1, 2].set_axis_off()
    axes[1, 2].set_facecolor("0.08")
    fig.suptitle(
        "Same Kraken OPD  ·  wave plate vs Fresnel vs the 0.6 mm shim",
        color="0.92",
        fontsize=13,
    )
    fig.text(
        0.50,
        0.012,
        "Chassis z is too short for Settles lines. A phase dot helps weak phase, not a Mach cone.  "
        "The knife is schlieren. The lab throw is a different illuminator, not a printed plate.",
        ha="center",
        color="0.55",
        fontsize=8,
    )
    dest = DEST / "shadowgraph_wave.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(dest, dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(dest)
    print(f"focus energy  {np.mean(I_f0):.3f}  shim Fresnel {np.mean(I_fz):.3f}  "
          f"lab {np.mean(I_lab):.3f}  Zernike {np.mean(I_zk):.3f}  knife {np.mean(I_kn):.3f}")


if __name__ == "__main__":
    main()
