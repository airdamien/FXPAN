# Duals

One taking lens. Two bodies. A **1.8×** stitch.

Each camera is aimed at a different half of a wider image (20% overlap). The taking lens is an enlarger/LF optic on an M42 helicoid — never a native-mount still lens. Path is `fold + register`. Math: [OPTICS.md](OPTICS.md). Buy list and assembly: [bom.md](bom.md).

![Hybrid L with two D7000s](docs/chassis/hybrid_bodies.png)

Hybrid L — D7000s on **▲ R** (+X) and **▲ T** (+Y). Stem is the EL-Nikkor. Bodies are preview ghosts; the print is the box and tubes.

![Hybrid L, lid off](docs/chassis/hybrid.png)

Lid off: one uncut 50×50×1 plate, S1 toward the lens. Gold mouths are 52×0.75 reverse rings (or print `arm_*_f` for a male bayonet).

![Panorama V](docs/chassis/v.png)

The original **V**: two first-surface mirrors, opposite arms, field-split. Same box, same stem.

## Print STLs

Ready to slice. Every fork is a complete kit under [`stls/`](stls/). `arm_*.stl` is the reverse-ring mouth; `arm_*_f.stl` is the printed male bayonet.

| Kit | Bodies | Mouth | Path | 135/5.6 | Stitch | Files |
|-----|--------|-------|------|---------|--------|-------|
| [`stls/hybrid/`](stls/hybrid/) | D7000 DX | 52 mm F | 173.5 mm | ~0.61 m | 42.5 mm · 14° · ~8.9k | `--hybrid` |
| [`stls/hybrid_shadowgraph/`](stls/hybrid_shadowgraph/) | D7000 DX | 52 mm F | 173.5 mm | ~0.61 m | same frame · T sharp / R shadowgraph | `--shadowgraph` |
| [`stls/EFhybrid/`](stls/EFhybrid/) | 5D Mark III FF | 58 mm EF | 171 mm | ~0.64 m | 64.8 mm · 21.5° · ~10.4k | `--efhybrid` |
| [`stls/Ehybrid/`](stls/Ehybrid/) | Sony α7 FF | 52 mm E | 145 mm | **~2 m** | 64.4 mm · 25° · ~10.8k | `--ehybrid` |
| [`stls/v/`](stls/v/) | D7000 DX | 52 mm F | 173.5 mm | ~0.61 m | 37.8 mm · 12.4° · ~7.9k | `./export_stls.sh` |
| [`stls/bsplit/`](stls/bsplit/) | D7000 DX | 52 mm F | 173.5 mm | — | same frame, −1 stop | `--bsplit` |

**Print:** PETG or ABS (not PLA for bayonets). Box **floor on the bed**. Tubes **flange on the bed**. Bolt each flange with 4× M3 + hex nuts in the wall traps.

### Hybrid kit (`stls/hybrid/`)

| File | What | Bed |
|------|------|-----|
| `chassis.stl` | 90 mm junction box | floor down |
| `hybrid_tray.stl` | 50×50 plate seat + roof pegs | as exported |
| `lid.stl` | chamber lid, blind Pi holes | outer face up |
| `stem.stl` | lens tube, M42 helicoid nut | flange down |
| `arm_r.stl` / `arm_t.stl` | toed camera tubes, 52×0.75 | flange down |
| `arm_r_f.stl` / `arm_t_f.stl` | same tubes, printed F | flange down |
| `shims.stl` | 0.2 / 0.5 / 1.0 mm focus rings | as exported |
| `elnikkor_adapter.stl` | M42 male → L39×26 TPI | M42 male on the bed |

Do not swap R and T — T is shorter (`bs_t_comp`). Drop the whole Edmund #43-359 plate in from above; do not cut it. Re-export with `./export_stls.sh --hybrid` (wrappers: `./export_hybrid.sh`, `./export_efhybrid.sh`, `./export_ehybrid.sh`).

### Shadowgraph kit (`stls/hybrid_shadowgraph/`)

Same box, stem, tray, and lid as hybrid. Tubes are not toed — both bodies see one frame. `arm_t` is the conjugate tube (`▲ T shadowgraph`). `arm_r` is the longer razor-slot tube (`▲ R shadowgraph`). Do not stack a 0.6 mm ring to fake it. Export: `./export_stls.sh --shadowgraph` or `./export_shadowgraph.sh`.

## Light path

The hybrid L is **one** 50/50 plate, not a knife in the pupil. Lens on −Y. Reflect → R (+X). Transmit → T (+Y). Each arm is toed by `field_toe` so its sensor window sits on a different half of a `stitch_w` image.

![Fold schematic](docs/kraken/el135_paths.png)

KrakenOS sequential fold. Plate at z = 55 mm. Gold = 50/50. Red = R sensor. Blue = T sensor. Same fold on every hybrid kit; only the register (46.5 / 44 / 18 mm) changes `PATH_TOTAL`.

![Rays on the print STLs](docs/kraken/hybrid_stl_paths.png)

Non-sequential trace **on the print meshes** (`stls/hybrid/chassis.stl` + `hybrid_tray.stl`). Plastic is absorb. Blue = T through the slot. Red = R off the coating. Left is top (lens −Y, T +Y, R +X). The plate is large enough — the field at the glass is small.

![V rays on the print STLs](docs/kraken/v_stl_paths.png)

Same idea on the V (`stls/v/chassis.stl` + `mirror_tray.stl`). Two 45° first-surface mirrors, knife at the origin. Blue = L (−X). Red = R (+X). Incoming from the lens (−Y). Unique halves stay full brightness.

On a D7000 + EL-Nikkor 135/5.6: focus **~608 mm**, stitch **~149 mm** of object / **42.5 mm** on the sensors, **~14°**, **~8870×3264**. T-only / overlap / R-only = 108 / 27 / 108. `ratio` must stay ≥ 1.6. Full budget: [OPTICS.md](OPTICS.md).

Regenerate:

```
kraken/.venv/bin/python kraken/hybrid_paths.py       # fold + frames + stitch
kraken/.venv/bin/python kraken/hybrid_stl_paths.py   # rays on the hybrid STLs
kraken/.venv/bin/python kraken/v_stl_paths.py        # rays on the V STLs
kraken/.venv/bin/python kraken/hybrid_scene.py       # countryside below
```

## Field — same countryside, three bodies

Same Tuscany still through the toed windows. Scene: [Radek Hloch / CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Landscape_of_Tuscany_3.jpg).

D7000 / 5D III: 135 focuses **~0.61–0.64 m**. α7: E is 18 mm, so the same lens focuses at **~2 m** and the object field is much larger. That is the chassis, not a different lens.

### D7000 DX — 173.5 mm, ~0.61 m

One DX window (~83×55 mm, 7.8°) vs the stitch (~149 mm, 14°, ~8870×3264).

![D7000 countryside](docs/kraken/el135_scene.png)

T and R each own a half. Color map of that split, and the stitched strip:

![D7000 T/R frames](docs/kraken/el135_frames.png)

![D7000 stitch vs one DX](docs/kraken/el135_pano.png)

Same DX window, D7000 (16.2 MP, 4.8 µm) vs D7200 (24.2 MP, 3.9 µm). Stars are native photosites on 8×8 mm of object.

![D7000 vs D7200 sampling](docs/kraken/el135_d7200.png)

### V knife — same 173.5 mm, ~0.61 m

Hard field split. Each D7000 still records a full DX frame, but the frame is one half of the taking-lens image plus **20% across the knife** (~4.7 mm / ~1000 px). Unique halves keep a stop. Stitch is **1.6×** (~133 mm of object, 12.4°, ~7885×3264).

![V countryside](docs/kraken/el135_v_scene.png)

Same still, V vs hybrid L. Hybrid is two toed full-frame windows on a 50/50 (1.8×, −1 stop). The V boxes sit inside the hybrid stitch.

![V vs hybrid L](docs/kraken/el135_v_hybrid.png)

### 5D Mark III FF — 171 mm, ~0.64 m

36×24 mm, 6.25 µm. Single ~135×90 mm / 12°. Stitch ~243 mm / 21.5° / ~10368×3840.

![5D Mark III countryside](docs/kraken/el135_5d3_scene.png)

![D7000 vs 5D Mark III](docs/kraken/el135_d7000_5d3.png)

### Sony α7 FF — 145 mm, ~2 m

35.8×23.9 mm, 6.0 µm. Single ~483×323 mm / 14.1°. Stitch ~870 mm / 25.1° / ~10800×4000.

![α7 countryside](docs/kraken/el135_a7_scene.png)

D7000 at 0.61 m is a postage stamp on the α7 field.

![D7000 vs α7](docs/kraken/el135_d7000_a7.png)

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

## Source

1. Open the watch file for the fork you are printing.
2. Enable **Design → Automatic Reload and Preview**.
3. Tweak that folder’s `params.scad`. `ARM_MOUNT=0` is the reverse-ring mouth; `1` is the printed male bayonet.

```
python3.12 -m venv kraken/.venv
kraken/.venv/bin/pip install -r kraken/requirements.txt
```

`docs/kraken/` and `docs/chassis/` are committed. `kraken/preview_*.png` is gitignored.

| Path | Role |
|------|------|
| `stls/{v,bsplit,hybrid,hybrid_shadowgraph,EFhybrid,Ehybrid}/` | Print STLs |
| `openscad/WATCH_ME.scad` | V |
| `openscad/hybrid/WATCH_ME.scad` | D7000 hybrid L |
| `openscad/hybrid_shadowgraph/WATCH_ME.scad` | same-image T sharp / R shadowgraph |
| `openscad/EFhybrid/WATCH_ME.scad` | 5D Mark III |
| `openscad/Ehybrid/WATCH_ME.scad` | α7 |
| `kraken/hybrid_paths.py` | Fold + frames + stitch |
| `kraken/hybrid_stl_paths.py` | Rays on the hybrid STLs |
| `kraken/v_stl_paths.py` | Rays on the V STLs |
| `kraken/hybrid_scene.py` | Countryside |
| `OPTICS.md` / `bom.md` | Path math + buy + assembly |
| `cam/dual.py` | D7000 USB (gphoto2 PTP) |
