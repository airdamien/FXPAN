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
- **Stitch overlap** (`OVERLAP_FRAC`, default **0.20**): each arm is toed toward the lens by `arm_toe()` so the camera axis looks across the knife, and each glass is shifted inward by `overlap_cross()/2` so there is coating on that line of sight. That is ~4.7 mm / ~1000 px on a D7000. A hard V still cannot put the *same* full-brightness rays on both sensors — the extra strip is the crossed-glass + pupil-split seam, not a 50/50 cube. Tune `OVERLAP_FRAC` in [`openscad/params.scad`](openscad/params.scad).

## Equal-path rule

L and R geometric paths must match within **~0.1 mm**. Use printed shim rings (`SHIM_STEPS`) between arm tube and F-mount until both live-views are sharp on a **distant** chart without refocusing the helicoid between bodies.

## Alignment procedure

1. Flock or matte-black the chamber interior; install FSM glass coating-side toward the light.
2. Mount both D7000s; MC-DC2 Y-remote for sync.
3. Helicoid → infinity on a distant target using **one** body.
4. If the other body is soft, add/remove shims on that arm only; recheck.
5. Tip/tilt set-screws on mirror trays until the seam is centered and vertical.
6. Shoot overlap chart; stitch; note vignetting — stop down or swap to larger-circle lens if needed.

## What will not work

- Native F-mount Nikkor on the stem for infinity (path already spent 46.5 mm inside each body).
- Second-surface (household) mirrors — ghost images.
- Fixed mirrors with no shims — one side will miss focus (see Hackaday A7 T-rig).
