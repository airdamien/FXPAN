# Nikon Duals

Two bodies + one taking lens. The original chassis is a panoramic **T**: two Nikon D7000s, field-split with first-surface mirrors.

The taking lens is never an F-Nikkor. Stem is **M42/M39 helicoid + enlarger/LF lens**. Path budget is `PATH_TOTAL = fold + register` — see [OPTICS.md](OPTICS.md). Shopping and assembly: [bom.md](bom.md).

## Forks

Same 90 mm junction box, same 52/68 tubes, same enlarger stem. What changes is the splitter and the camera mount.

| Fork | Split | Bodies | Register | `PATH_TOTAL` | 135/5.6 focus | Stitch | Watch | Export |
|------|-------|--------|----------|--------------|---------------|--------|-------|--------|
| V (default) | two 50×50 FSM, hard knife | D7000 DX | 46.5 mm F | 173.5 mm | — | field halves | [`openscad/WATCH_ME.scad`](openscad/WATCH_ME.scad) | `./export_stls.sh` |
| bsplit | one 50/50 plate | D7000 DX | 46.5 mm F | 173.5 mm | — | same frame, −1 stop | [`openscad/bsplit/WATCH_ME.scad`](openscad/bsplit/WATCH_ME.scad) | `--bsplit` |
| hybrid | one 50/50, toed arms | D7000 DX | 46.5 mm F | 173.5 mm | ~0.61 m | 42.5 mm · 14° · ~8.9k | [`openscad/hybrid/WATCH_ME.scad`](openscad/hybrid/WATCH_ME.scad) | `--hybrid` |
| EFhybrid | same L | 5D Mark III FF | 44.0 mm EF | 171 mm | ~0.64 m | 64.8 mm · 21.5° · ~10.4k | [`openscad/EFhybrid/WATCH_ME.scad`](openscad/EFhybrid/WATCH_ME.scad) | `--efhybrid` |
| Ehybrid | same L | Sony α7 FF | 18.0 mm E | 145 mm | **~2 m** | 64.4 mm · 25° · ~10.8k | [`openscad/Ehybrid/WATCH_ME.scad`](openscad/Ehybrid/WATCH_ME.scad) | `--ehybrid` |

Hybrid panorama is **not** a pupil-split of one DX/FF frame. Each body is aimed at a different half of a wider taking-lens image (`sensor_shift` / `field_toe`, 20% overlap). Stitch is **1.8×** one frame. The 50×50 plate is large enough; do not cut it.

Print the box floor-down. Print tubes with the square flange on the bed, then bolt each flange onto the flat wall with 4× M3 + hex nuts. Wrappers: `./export_efhybrid.sh`, `./export_ehybrid.sh`.

## Countryside — EL-Nikkor 135/5.6

Kraken maps the same Tuscany still through the toed T/R windows. Scene: [Radek Hloch / CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Landscape_of_Tuscany_3.jpg). Regenerate with `kraken/.venv/bin/python kraken/hybrid_scene.py`.

On the D7000 / 5D III path the 135 focuses around **0.61–0.64 m**. The α7 fork is shorter (E is 18 mm), so the same lens focuses at **~2 m** and the object field is much larger. That is the chassis, not a different lens.

### D7000 DX — 173.5 mm path, ~0.61 m

One DX window (~83×55 mm of object, 7.8°) versus the hybrid stitch (~149 mm, 14°, ~8870×3264).

![D7000 countryside](docs/kraken/el135_scene.png)

T and R each own a half of a wider image. Color map of that split, and the stitched object strip:

![D7000 T/R frames](docs/kraken/el135_frames.png)

![D7000 stitch vs one DX](docs/kraken/el135_pano.png)

Same DX window on a D7200 (24.2 MP, 3.9 µm) versus the D7000 (16.2 MP, 4.8 µm). Stars are native photosites on 8×8 mm of object.

![D7000 vs D7200 sampling](docs/kraken/el135_d7200.png)

### 5D Mark III FF — 171 mm path, ~0.64 m

36×24 mm, 6.25 µm. Single ~135×90 mm / 12°. Stitch ~243 mm / 21.5° / ~10368×3840.

![5D Mark III countryside](docs/kraken/el135_5d3_scene.png)

Same still, D7000 boxes inside the 5D III field:

![D7000 vs 5D Mark III](docs/kraken/el135_d7000_5d3.png)

### Sony α7 FF — 145 mm path, ~2 m

35.8×23.9 mm, 6.0 µm. Single ~483×323 mm / 14.1°. Stitch ~870 mm / 25.1° / ~10800×4000.

![α7 countryside](docs/kraken/el135_a7_scene.png)

D7000 at 0.61 m is a postage stamp on the α7 field. Footer on the figure calls that out.

![D7000 vs α7](docs/kraken/el135_d7000_a7.png)

## Watch while editing

1. Open the watch file for the fork you are printing (table above).
2. Enable **Design → Automatic Reload and Preview**.
3. Tweak that folder’s `params.scad` (`EXPLODED`, distances, `PART`). `ARM_MOUNT=0` is the reverse-ring mouth; `1` is the printed male bayonet (`arm_*_f`).

```
python3.12 -m venv kraken/.venv
kraken/.venv/bin/pip install -r kraken/requirements.txt
kraken/.venv/bin/python kraken/hybrid_paths.py
kraken/.venv/bin/python kraken/hybrid_stl_paths.py   # rays on the print STLs
kraken/.venv/bin/python kraken/hybrid_scene.py       # countryside figures above
```

`docs/kraken/el135_*.png` is committed. `kraken/preview_*.png` is gitignored.

## Dual D7000 USB

Nikon-only. Both bodies: Setup → USB → **MTP/PTP**. No lens on the F-mounts (the iris is on the enlarger). `gphoto2` is already the Mac driver.

```
python3 cam/dual.py detect
python3 cam/dual.py pair --t SERIAL --r SERIAL
python3 cam/dual.py set --iso 400 --shutter 1/125 --program M
python3 cam/dual.py shoot captures/
```

USB fire is tens of ms apart. Use the MC-DC2 Y-lead for anything that moves.

```
python3 cam/web.py          # iPhone: http://<lan-ip>:8787/   laptop: http://127.0.0.1:8787/lab
```

## Files

| Path | Role |
|------|------|
| `openscad/WATCH_ME.scad` | Live assembly / STL export (V) |
| `openscad/params.scad` | V dimensions |
| `openscad/hybrid/WATCH_ME.scad` | D7000 hybrid L |
| `openscad/EFhybrid/WATCH_ME.scad` | 5D Mark III hybrid L |
| `openscad/Ehybrid/WATCH_ME.scad` | α7 hybrid L |
| `openscad/f_mount_male.scad` | Printed male F |
| `openscad/mirror_tray.scad` | 45° FSM trays + knife |
| `f-mount_raw.stl` | Reference scan for bayonet calibration |
| `OPTICS.md` / `bom.md` | Path math + buy lists + assembly |
| `kraken/hybrid_paths.py` | KrakenOS trace (paths, frames, stitch) |
| `kraken/hybrid_scene.py` | Countryside figures |
| `docs/kraken/el135_*.png` | 135/5.6 sims (commit these) |
| `cam/dual.py` | USB control for both D7000s (gphoto2 PTP) |
