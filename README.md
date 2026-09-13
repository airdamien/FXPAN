# D12600

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
| `lid.stl` | chamber lid, blind Pi holes + 4× M3 display bosses | outer face up |
| `display_mount.stl` | bridge over the Pi; AMPS + 48 mm for the Wormfingers case | feet down |
| `stem.stl` | lens tube, M42 helicoid nut (135 / 180) | flange down |
| `stem_f50.stl` | 1.6 mm cookie + female F (50 mm test) | flange down |
| `arm_r.stl` / `arm_t.stl` | 72 mm toed tubes, 52×0.75 (135 / 180) | flange down |
| `arm_r_f.stl` / `arm_t_f.stl` | same 72 mm tubes, printed F | flange down |
| `arm_r_s.stl` / `arm_t_s.stl` | 54 mm F 50 tubes, 2 mm cookies, 52×0.75 | flange down |
| `arm_r_sf.stl` / `arm_t_sf.stl` | same 54 mm tubes, printed F | flange down |
| `shims.stl` | 0.2 / 0.5 / 1.0 mm focus rings | as exported |
| `elnikkor_adapter.stl` | M42 male → L39×26 TPI | M42 male on the bed |

Do not swap R and T — T is shorter (`bs_t_comp`). Drop the whole Edmund #43-359 plate in from above; do not cut it. Re-export with `./export_stls.sh --hybrid` (wrappers: `./export_hybrid.sh`, `./export_efhybrid.sh`, `./export_ehybrid.sh`).

### Shadowgraph kit (`stls/hybrid_shadowgraph/`)

Same box, stem, tray, and lid as hybrid. Tubes are not toed — both bodies see one frame. `arm_t` is the conjugate tube (`▲ T shadowgraph`). `arm_r` is the longer razor-slot tube (`▲ R shadowgraph`). Do not stack a 0.6 mm ring to fake it. Export: `./export_stls.sh --shadowgraph` or `./export_shadowgraph.sh`. Sims, what it can do, and the bench setup: [Shadowgraph](#shadowgraph).

## Light path

The hybrid L is **one** 50/50 plate, not a knife in the pupil. Lens on −Y. Reflect → R (+X). Transmit → T (+Y). Each arm is toed by `field_toe` so its sensor window sits on a different half of a `stitch_w` image.

![Fold schematic](docs/kraken/el135_paths.png)

KrakenOS sequential fold. Plate at z = 55 mm. Gold = 50/50. Red = R sensor. Blue = T sensor. Same fold on every hybrid kit; only the register (46.5 / 44 / 18 mm) changes `PATH_TOTAL`.

![Rays on the print STLs](docs/kraken/hybrid_stl_paths.png)

Non-sequential trace **on the print meshes** (`stls/hybrid/chassis.stl` + `hybrid_tray.stl`). Plastic is absorb. Blue = T through the slot. Red = R off the coating. Left is top (lens −Y, T +Y, R +X). The plate is large enough — the field at the glass is small.

![V rays on the print STLs](docs/kraken/v_stl_paths.png)

Same idea on the V (`stls/v/chassis.stl` + `mirror_tray.stl`). Two 45° first-surface mirrors, knife at the origin. Blue = L (−X). Red = R (+X). Incoming from the lens (−Y). Unique halves stay full brightness.

On a D7000 + EL-Nikkor 135/5.6: focus **~608 mm**, stitch **~149 mm** of object / **42.5 mm** on the sensors, **~14°**, **~8870×3264**. T-only / overlap / R-only = 108 / 27 / 108. The **180/5.6** at 50 m (helicoid **+7.2 mm**, path **180.7 mm**) is the same angular stitch on a **~12 m** field. `ratio` must stay ≥ 1.6. Full budget: [OPTICS.md](OPTICS.md).

Regenerate:

```
kraken/.venv/bin/python kraken/hybrid_paths.py       # fold + frames + stitch
kraken/.venv/bin/python kraken/hybrid_stl_paths.py   # rays on the hybrid STLs
kraken/.venv/bin/python kraken/v_stl_paths.py        # rays on the V STLs
kraken/.venv/bin/python kraken/hybrid_scene.py       # countryside below
```

## Field — same countryside, three bodies

Same Tuscany still through the toed windows. Scene: [Radek Hloch / CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Landscape_of_Tuscany_3.jpg).

D7000 / 5D III: 135 focuses **~0.61–0.64 m**. α7: E is 18 mm, so the same lens focuses at **~2 m** and the object field is much larger. That is the chassis, not a different lens. Landscape on this box is the **180/5.6** at **50 m** (the 135 cannot get there).

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

### D7000 DX — EL-Nikkor 180, 50 m

Infinity helicoid (**+7.2 mm**, path **180.7 mm**). Same Tuscany still as a distant landscape. One DX is **~6.5×4.3 m / 7.5°**; stitch is **~11.8 m / 13.4° / ~8870×3264** (1.8×). Angular FOV is almost the 135 at 0.61 m; the object is **~12 m**, not 15 cm. 135 cannot focus here. T-only / overlap / R-only = 108 / 27 / 108. `ratio` 1.67.

![180 fold](docs/kraken/el180_paths.png)

![D7000 180 countryside](docs/kraken/el180_scene.png)

![D7000 180 T/R frames](docs/kraken/el180_frames.png)

![D7000 180 stitch vs one DX](docs/kraken/el180_pano.png)

Same DX window, D7000 vs D7200. Stars are native photosites on **0.5 m** of object (8 mm is invisible at 50 m).

![D7000 vs D7200 at 50 m](docs/kraken/el180_d7200.png)

## Shadowgraph

The pano hybrid toes each body at a **different** half of a wider image. For air, vapor, or a shock you want the **same** DX pixels (`field_toe = 0`). That is [`stls/hybrid_shadowgraph/`](stls/hybrid_shadowgraph/): same box, same uncut #43-359 plate, same 135/5.6. Different tubes.

T is conjugate — a phase-blind image of the card (the slug only). R is **0.6 mm** longer, about **7.4 mm** of object-side defocus (`extra / m²`). Ray bunching at a density jump is the shadowgraph. Both flanges say **shadowgraph**. Do not swap them. Do not stitch.

![Hybrid toe vs same-image](docs/kraken/schlieren_windows.png)

Top: current hybrid (~4.6° toe). Subtract T−R and you have two scenes — a tree that only exists on one body looks like flow. Bottom: shadowgraph arms (`toe = 0`). Same pixels. The knife panel is Kraken’s ray walk through a jet, linearized.

![T conjugate / R shadowgraph / Settles](docs/kraken/shadowgraph_bullet.png)

Same 50/50 pair, M≈2. T is the silhouette. R is the printed extra length at DX sampling. Right is a collimated-lab Settles plate — the thing this chassis is not.

![Wave plate vs Fresnel vs the 0.6 mm extra](docs/kraken/shadowgraph_wave.png)

Same Kraken OPD. Geometric extra ≈ Fresnel at the chassis z (7.4 mm) — a printed phase plate does not buy a Mach cone. A Fourier knife is schlieren. A 250 mm lab throw is closer to Settles and is a **different illuminator**, not a printed part. Do not add a Zernike / phase plate.

![BOS on the same-image pair](docs/kraken/schlieren_bos.png)

Background-oriented schlieren on `toe = 0`: speckle card, both bodies see this. Correlate each body against its own still. Quiver is Kraken’s chief-ray walk. Stitch first and the hybrid toe looks like fake flow.

### Setup

1. Print the shadowgraph kit. Box floor on the bed; tubes flange on the bed. Same plate drop as hybrid: **S1 toward the lens**.
2. Bright card (or a speckle card for BOS) at **~0.61 m** — the 135 conjugate on `PATH_TOTAL = 173.5`.
3. Helicoid until **T** is sharp on the card. Leave R alone. The extra length is the tube, not a stacked ring.
4. Put the subject in front of the card (jet, wake, slug). MC-DC2 Y-lead — USB fire is tens of ms apart.
5. Optional: a razor in the R mouth slot (0.42 mm, +Y through to the axis). Soft Fourier cutoff, ~8 mm early of the 135 rear focus; the real plane sits ~8 mm *inside* the F-mount.
6. Compare T vs R on the same pixels. Do not stitch. Do not subtract a toed pano pair.

### What this chassis will and will not do

| Works | Will not |
|-------|----------|
| Geometric shadowgraph on R (printed +0.6 mm) | Settles spark *lines* from chassis z — that needs ~250 mm of throw and a collimated flash |
| Same-image BOS on a speckle card | Using the pano hybrid and subtracting — two windows, looks like flow |
| Razor in the R slot (soft knife / weak schlieren) | A printed Zernike or phase plate — helps weak phase, not a Mach cone |
| Heat-gun / shock / vapor in front of the card | Stereo, or a field-split V, of the same event — one taking lens |

Regenerate:

```
kraken/.venv/bin/python kraken/schlieren_scene.py      # toe vs same-image, BOS, ray walk
kraken/.venv/bin/python kraken/shadowgraph_scene.py    # T slug / R cone / Settles
kraken/.venv/bin/python kraken/shadowgraph_wave.py     # Fresnel / knife / phase plate
```

## Dual D7000 USB

Nikon-only. Both bodies: Setup → USB → **MTP/PTP**. No lens on the F-mounts (the iris is on the enlarger). `gphoto2` is already the Mac driver.

```
python3 cam/dual.py detect
python3 cam/dual.py pair --t SERIAL --r SERIAL
python3 cam/dual.py set --iso 400 --shutter 1/125 --program M
python3 cam/dual.py shoot captures/
```

USB fire is tens of ms apart. Use the MC-DC2 Y-lead for anything that moves. SET stores **GPIO shutter** (BCM 21 / Corona / Y-lead) and **Download files**; both default on on a Pi and survive restarts. USB **Sim as Pi** lets a Mac show the GPIO switch (no pulse).

```
python3 cam/web.py          # iPhone: http://<lan-ip>:8787/   laptop: http://127.0.0.1:8787/lab
```

On the 10.1″ Pi (`airdamien@192.0.2.10`) the field page is **D12600**: Chromium kiosk, login autostart, respawn loop. SET **Desktop** returns to labwc. Tap **D12600** on the desktop to come back.

Tabs are **LIVE / USB / PANO / FILES / SET**. LIVE is the home page and opens with no cameras on USB. The side stack is START / STOP (every tab), ISO, FIRE. T/R preview is LIVE only. ISO is a modal over the buttons.

SET is grouped: **Exposure** (ISO / shutter / program / WB / quality + APPLY), **Master** (T or R, copy to the other body — not flash; T is usually master, a speedlight can stay on R), **Capture** (download, GPIO, flop R, overlap), **Screen** (HDMI DDC backlight), **Wi-Fi** (scan / join, AP `D12600`), **Pi** (Sim as Pi, Desktop).

PANO **STITCH** queues on a background worker so you can keep shooting. Modes are match / blend / cut / open (OpenStitching). Each pair card keeps QUEUED / WORKING / OK / ERROR. Newest shots sit at the top. A pair needs T and R JPEGs; T-only until the splitter is in will say so on that card. FILES is the same list.

![LIVE](docs/cam/view.png)

![USB](docs/cam/usb.png)

![SET](docs/cam/set.png)

![ISO](docs/cam/iso.png)

![PREVIEW](docs/cam/preview.png)

```
./scripts/setup-pi-remote.sh airdamien@192.0.2.10
./scripts/redeploy-kiosk.sh                  # rsync cam/ + restart web.py + Chromium
```

## Source

1. Open the watch file for the fork you are printing.
2. Enable **Design → Automatic Reload and Preview**.
3. Tweak that folder’s `params.scad`. `ARM_MOUNT=0` is the reverse-ring mouth; `1` is the printed male bayonet.

```
python3.12 -m venv kraken/.venv
kraken/.venv/bin/pip install -r kraken/requirements.txt
```

`docs/kraken/`, `docs/chassis/`, and `docs/cam/` are committed. `kraken/preview_*.png` is gitignored.

| Path | Role |
|------|------|
| `stls/{v,bsplit,hybrid,hybrid_shadowgraph,EFhybrid,Ehybrid}/` | Print STLs |
| `openscad/WATCH_ME.scad` | V |
| `openscad/hybrid/WATCH_ME.scad` | D7000 hybrid L |
| `openscad/hybrid_shadowgraph/WATCH_ME.scad` | same-image T sharp / R shadowgraph |
| `openscad/EFhybrid/WATCH_ME.scad` | 5D Mark III |
| `openscad/Ehybrid/WATCH_ME.scad` | α7 |
| `openscad/monitor/WATCH_ME.scad` | HAMTYSAN 10.1″ HCIK101V.CC ghost |
| `kraken/hybrid_paths.py` | Fold + frames + stitch |
| `kraken/hybrid_stl_paths.py` | Rays on the hybrid STLs |
| `kraken/v_stl_paths.py` | Rays on the V STLs |
| `kraken/hybrid_scene.py` | Countryside |
| `kraken/schlieren_scene.py` | Toe vs same-image, BOS, ray walk |
| `kraken/shadowgraph_scene.py` | T slug / R cone |
| `kraken/shadowgraph_wave.py` | Fresnel / knife / phase plate |
| `OPTICS.md` / `bom.md` | Path math + buy + assembly |
| `docs/monitor/` | 10.1″ panel datasheets / sibling drawings |
| `cam/dual.py` | D7000 USB (gphoto2 PTP) + master→slave copy |
| `cam/wifi.py` | nmcli scan / join / AP |
| `cam/brightness.py` | HDMI DDC/CI backlight (VCP 0x10) |
| `cam/pano.py` | T/R pairs, stitch queue, OpenStitching |
| `cam/gpio.py` | Pi BCM 21 / Corona Y-lead pulse |
| `cam/kiosk/` | labwc Chromium kiosk, OpenStitching venv, PTP quiet |
