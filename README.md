# Nikon Duals — panoramic T chassis

Two Nikon D7000 bodies + one taking lens, field-split with first-surface mirrors.

A **50/50 plate** fork (both cameras get the same full frame) lives in [`openscad/bsplit/`](openscad/bsplit/WATCH_ME.scad). A **hybrid** pano L (toed DX bodies + one 50/50 plate — ~1.8× one frame) lives in [`openscad/hybrid/`](openscad/hybrid/WATCH_ME.scad). See [OPTICS.md](OPTICS.md).

**Infinity-capable:** M42/M39 helicoid + enlarger/LF lens on the stem (not an F-Nikkor).  
Path budget: `PATH_TOTAL = fold + 46.5 ≈ 173.5 mm` — see [OPTICS.md](OPTICS.md). Hybrid taking lens: EL-Nikkor 135/5.6 (focus ~0.61 m on this path) — [`docs/kraken/el135_pano.png`](docs/kraken/el135_pano.png).

## Watch while editing

1. Open [`openscad/WATCH_ME.scad`](openscad/WATCH_ME.scad) in OpenSCAD
2. Enable **Design → Automatic Reload and Preview**
3. Tweak [`openscad/params.scad`](openscad/params.scad) (`EXPLODED`, distances, `PART`)

`./export_stls.sh` writes print STLs to `stls/`. `--bsplit` and `--hybrid` write those forks to `stls/bsplit/` and `stls/hybrid/`. Print the box floor-down. Print tubes with the square flange on the bed, then bolt each flange onto the flat wall with 4× M3 + hex nuts.

KrakenOS path/frame preview for the hybrid L (Python 3.12):

```
python3.12 -m venv kraken/.venv
kraken/.venv/bin/pip install -r kraken/requirements.txt
kraken/.venv/bin/python kraken/hybrid_paths.py
kraken/.venv/bin/python kraken/hybrid_stl_paths.py   # rays on the print STLs
# also writes docs/kraken/el135_*.png for the recommended 135 mm taking lens
```

## Files

| Path | Role |
|------|------|
| `openscad/WATCH_ME.scad` | Live assembly / STL export switch |
| `openscad/params.scad` | All critical dimensions |
| `openscad/f_mount_male.scad` | Male F bayonet for D7000s |
| `openscad/mirror_tray.scad` | 45° FSM trays + knife |
| `openscad/shims.scad` | Focus-match rings |
| `f-mount_raw.stl` | Reference scan for bayonet calibration |
| `OPTICS.md` / `bom.md` | Path math + shopping list (hybrid buy list in `bom.md`) |
| `kraken/hybrid_paths.py` | KrakenOS trace of the hybrid pano (paths, frames, stitch) |
| `docs/kraken/el135_*.png` | 135/5.6 object frames + stitch (commit these; `kraken/preview_*.png` is gitignored) |
| `cam/dual.py` | USB control for both D7000s (gphoto2 PTP) |

## Dual D7000 USB

Both bodies: Setup → USB → **MTP/PTP**. No lens on the F-mounts (the iris is on the enlarger). `gphoto2` is already the Mac driver.

```
python3 cam/dual.py detect
python3 cam/dual.py pair --t SERIAL --r SERIAL
python3 cam/dual.py set --iso 400 --shutter 1/125 --program M
python3 cam/dual.py shoot captures/
```

USB fire is tens of ms apart. Use the MC-DC2 Y-lead for anything that moves.
