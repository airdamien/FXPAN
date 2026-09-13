# Optical path budget — Nikon Dual T

## Register math

| Segment | Symbol | Default (mm) |
|---------|--------|--------------|
| Helicoid/lens register → knife edge | `D_LENS_TO_KNIFE` | 55 |
| Knife edge → camera F-mount face | `D_KNIFE_TO_MOUNT` | 72 |
| Fold subtotal | `PATH_FOLD` | 127 |
| Inside each D7000 (mount → sensor) | `FLANGE_F` | **46.5** (fixed) |
| **Total flange → sensor** | `PATH_TOTAL` | **173.5** |

The taking lens must form infinity at **`PATH_TOTAL`**, not at 46.5 mm. That is why the stem is an **M42/M39 focusing helicoid + enlarger/LF lens**, not an F-Nikkor.

Edit distances in [`openscad/params.scad`](openscad/params.scad). Keep **L and R arms identical** except for shim stacks.

## Field split (panorama)

- One-piece **V cartridge** joins at the **middle** (knife at origin); arms run toward the blank **back wall** (+Y).
- Coatings face **out from the V**. Cartridge stays inside the chamber; floor pockets locate it; lid forks slot over two posts (`SHOW_LID=1`).
- Right blade → +X camera; left blade → −X camera.
- **Stitch overlap** (`OVERLAP_FRAC`, default **0.20**): arm cookies stay **flat** on the cube faces; each tube is toed toward the lens by `arm_toe()` so the camera looks across the knife. Each glass is shifted inward by `overlap_cross()/2` so there is coating on that line of sight. That is ~4.7 mm / ~1000 px on a D7000. A hard V still cannot put the *same* full-brightness rays on both sensors — the extra strip is the crossed-glass + pupil-split seam, not a 50/50 cube. Stitch is **1.6×** one DX (~37.8 mm / 12.4°). Countryside: [`docs/kraken/el135_v_scene.png`](docs/kraken/el135_v_scene.png) · vs hybrid: [`docs/kraken/el135_v_hybrid.png`](docs/kraken/el135_v_hybrid.png). Tune `OVERLAP_FRAC` in [`openscad/params.scad`](openscad/params.scad).

## Equal-path rule

L and R geometric paths must match within **~0.1 mm**. Use printed shim rings (`SHIM_STEPS`) between arm tube and F-mount until both live-views are sharp on a **distant** chart without refocusing the helicoid between bodies.

## Alignment procedure

1. Flock or matte-black the chamber interior; install FSM glass coating-side toward the light.
2. Mount both D7000s; MC-DC2 Y-remote for sync.
3. Helicoid → infinity on a distant target using **one** body.
4. If the other body is soft, add/remove shims on that arm only; recheck.
5. Tip/tilt set-screws on mirror trays until the seam is centered and vertical.
6. Shoot overlap chart; stitch; note vignetting — stop down or swap to larger-circle lens if needed.

## Why not a 50/50 plate beamsplitter

The panorama T uses a **hard V** because it splits the *field*. Each camera gets a different half of the taking lens’s image (plus a crossed-seam overlap) so you can stitch a wider frame. A [50×50 mm 50R/50T plate](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/) (Edmund #43-359) splits *amplitude*: both bodies see the **same** full frame at ~half the light. That is a different camera — dual-ISO / dual-exposure / redundant record — not a panorama.

Other reasons the V stayed:

- One 45° plate reflects to **+X** and transmits to **+Y**. It cannot feed two opposite (±X) cameras without a second fold.
- Each body loses a stop. The V does not.
- Transmit goes through 1 mm float at 45° (~0.3 mm extra OPL). The two arms are no longer the same length.
- #43-359 is **uncoated on S2** — ghosts. Dielectric 50/50 at 45° is also not 50/50 for both polarizations.

The amplitude-split fork is [`openscad/bsplit/`](openscad/bsplit/WATCH_ME.scad): lens −Y, reflect +X, transmit +Y. The T tube is shortened by `bs_t_comp()`. Open that file, not `WATCH_ME.scad`. Export with `./export_stls.sh --bsplit`.

## Hybrid (pano L: toed DX + one 50/50 plate)

A knife in the converging beam splits the **pupil**, not the picture — both bodies still see one DX frame. The panorama is each camera looking at a **different half** of a wider taking-lens image.

`sensor_shift() = SENSOR_W/2 × (1 − OVERLAP_FRAC)` ≈ **9.4 mm**. Each arm is toed by `field_toe()` so its DX window is that offset. Stitch width is `SENSOR_W × (2 − OVERLAP_FRAC)` ≈ **42.5 mm / 1.8×** one frame. The taking lens must cover that (~45 mm diagonal).

One uncut 50×50 plate at the origin (same seat as bsplit): reflect → +X, transmit → +Y. Both unique halves are ~1 stop down.

Taking lens: **EL-Nikkor 135 mm f/5.6** (L39, 4×5 coverage, ~$80–150 used). On `PATH_TOTAL=173.5` it focuses at **~608 mm** (m≈0.29). Stitch is ~149 mm of object / 42.5 mm on the sensors (~1.7× one DX). The 50/2.8 you have is close-up only (~73 mm). Infinity on this chassis is an **EL-Nikkor / Componon / Rodagon 180** (helicoid out ~6.5 mm). The 135 cannot get there — the 90 mm box plus the D7000 register already exceed 135 mm. See [`docs/kraken/el135_frames.png`](docs/kraken/el135_frames.png) and [`docs/kraken/el135_pano.png`](docs/kraken/el135_pano.png).

Open [`openscad/hybrid/WATCH_ME.scad`](openscad/hybrid/WATCH_ME.scad). Verify with [`kraken/hybrid_paths.py`](kraken/hybrid_paths.py) (`ratio` must be ≥ 1.6). Export with `./export_stls.sh --hybrid`.

## Hybrid shadowgraph (same-image DX + one 50/50 plate)

Same L and plate, but `field_toe() = 0`: both bodies see the same DX frame. T is the conjugate tube (`▲ T shadowgraph`). R is the longer razor-slot tube — 0.6 mm extra (~7.4 mm object-side defocus), `▲ R shadowgraph`. Not a stitch. Bright card at ~0.61 m. Export with `./export_stls.sh --shadowgraph`. Setup, what works, and the Kraken plates: [README — Shadowgraph](README.md#shadowgraph).

## EF hybrid (pano L: toed 5D Mark III + one 50/50 plate)

Same L and the same uncut 50×50 plate. Bodies are Canon **5D Mark III** (36×24 mm, EF, **44.0 mm** register). `sensor_shift()` ≈ **14.4 mm**, stitch ≈ **64.8 mm / 1.8×** one FF frame. `PATH_TOTAL` ≈ **171 mm**. Tube mouth is **58×0.75** for an EF reversing ring, or `ARM_MOUNT=1` for a printed male EF. Open [`openscad/EFhybrid/WATCH_ME.scad`](openscad/EFhybrid/WATCH_ME.scad). Export with `./export_stls.sh --efhybrid`. Countryside compare: [`docs/kraken/el135_d7000_5d3.png`](docs/kraken/el135_d7000_5d3.png) (D7000 stitch ~14° / 8.9k px vs 5D Mk III ~21.5° / 10.4k px).

## E hybrid (pano L: toed α7 + one 50/50 plate)

Same L, Sony **α7** (35.8×23.9 mm, E, **18.0 mm** register). `PATH_TOTAL` ≈ **145 mm**, so the 135/5.6 focuses at **~2 m** (not 0.61 m). Stitch ≈ **64.4 mm / 1.8×** one FF frame, ~**25°**. Open [`openscad/Ehybrid/WATCH_ME.scad`](openscad/Ehybrid/WATCH_ME.scad). Export with `./export_stls.sh --ehybrid`. Countryside: [`docs/kraken/el135_d7000_a7.png`](docs/kraken/el135_d7000_a7.png).

## What will not work

- Native F-mount Nikkor on the stem for infinity (path already spent 46.5 mm inside each body).
- El-Nikkor **50 mm** f/2.8 on this path (close-up only). Print `elnikkor_adapter` (L39×26 TPI) and use the **135 mm f/5.6** for a ~0.6 m subject. Infinity needs path ≈ f: that is a **180 mm** enlarger lens on this box (see [bom.md](bom.md)), not a shorter 135 stem.
- Second-surface (household) mirrors — ghost images.
- Fixed mirrors with no shims — one side will miss focus (see Hackaday A7 T-rig).
