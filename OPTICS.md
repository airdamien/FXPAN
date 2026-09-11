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
- **Stitch overlap** (`OVERLAP_FRAC`, default **0.20**): arm cookies stay **flat** on the cube faces; each tube is toed toward the lens by `arm_toe()` so the camera looks across the knife. Each glass is shifted inward by `overlap_cross()/2` so there is coating on that line of sight. That is ~4.7 mm / ~1000 px on a D7000. A hard V still cannot put the *same* full-brightness rays on both sensors — the extra strip is the crossed-glass + pupil-split seam, not a 50/50 cube. Tune `OVERLAP_FRAC` in [`openscad/params.scad`](openscad/params.scad).

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

## Hybrid (pano L: one 50/50, no extra mirror)

Tilting a 50/50 does **not** send left pixels one way and right pixels the other — it only steers the reflected beam. Field split comes from **where the plate sits in the aperture**.

The [Edmund 50×50×1 50R/50T](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/) stands at 45° with its leading edge at the split:

- Rays that **miss** (left field) go straight to the back camera (+Y) at full brightness.
- Rays that **hit** reflect to +X and transmit toward +Y. The first `BS_EXPOSE` mm is the stitch overlap (both cameras). A baffle on the transmit face blocks unique-right T so the back camera does not see the whole right half.

The right unique is ~1 stop down (it only exists as a 50/50 reflection). Chassis is an **L** (lens −Y, right +X, left +Y). Open [`openscad/hybrid/WATCH_ME.scad`](openscad/hybrid/WATCH_ME.scad). Export with `./export_stls.sh --hybrid`.

## What will not work

- Native F-mount Nikkor on the stem for infinity (path already spent 46.5 mm inside each body).
- El-Nikkor **50 mm** f/2.8 on this path (close-up only). Print `elnikkor_adapter` (L39×26 TPI) until a ~90–150 mm enlarger/LF lens arrives.
- Second-surface (household) mirrors — ghost images.
- Fixed mirrors with no shims — one side will miss focus (see Hackaday A7 T-rig).
