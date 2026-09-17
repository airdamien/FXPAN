# Bill of materials — Nikon Dual T

Path target: **PATH_TOTAL ≈ 173.5 mm** with current defaults (`D_LENS_TO_KNIFE=55`, `D_KNIFE_TO_MOUNT=72`). See [OPTICS.md](OPTICS.md). Buy **first-surface** mirrors only.

## Optics (order these)

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 2 | **50×50 mm first-surface mirror** (enhanced Al or protected Ag) | Field splitter at 45° | [Edmund 50×50 mm Silver 4–6λ](https://www.edmundoptics.com/p/50-x-50mm-silver-4-6lambda-mirror/31994/) · cheaper DIY: [Amazon “first surface mirror” search](https://www.amazon.com/s?k=first+surface+mirror+50mm) · craft sheet to cut: [Amazon 6×8" front surface sheet](https://www.amazon.com/s?k=front+surface+mirror+6x8) |
| 1 | **M42–M42 focusing helicoid** (12–19 mm) | Fine focus on stem | [Fotasy 12–19 mm](https://www.amazon.com/Fotasy-Helicord-Focusing-Helicoid-Extention/dp/B01N5V1QAC) · [Pixco 12–19 mm](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01IGGQR7Y) |
| 1 | **Longer M42 helicoid or M42 extension tubes** (optional stack) | Extra travel if infinity is short | [Amazon M42 helicoid 25–55](https://www.amazon.com/s?k=M42+focusing+helicoid+25-55) · [M42 extension tube set](https://www.amazon.com/s?k=M42+extension+tube+set) |
| 1 | **M39→M42 adapter** (if using enlarger lens) | Enlarger lenses are often M39 | Printed `elnikkor_adapter` (L39×26 TPI) for the El-Nikkor 50/2.8 Japan, or [Amazon M39 to M42](https://www.amazon.com/s?k=M39+to+M42+adapter) |
| 1 | **El-Nikkor 50 mm f/2.8** (you have this) | Stand-in taking lens — close-up only on this path | Rear is **L39 × 26 TPI**. Print `elnikkor_adapter`. |

## Cameras / sync

| Qty | Item | Link |
|-----|------|------|
| 2 | Nikon D7000 bodies (no lenses) | (you have these) |
| 2 | **Fotodiox Nikon F reverse ring, 52 mm** | [Fotodiox reverse adapter](https://www.amazon.com/Fotodiox-Reverse-Adapter-Compatible-Cameras/dp/B001G4NBSC) (pick **52 mm**; screws into the printed 52×0.75 mouths) |
| 1 | MC-DC2-compatible remote | [Kiwifotos MC-DC2](https://www.amazon.com/Kiwifotos-MC-DC2-Remote-Shutter-Release/dp/B071D9Y331) |
| 1 | Dual-camera sync path | Prefer [FlashZebra #0236](http://flashzebra.com/products/0236/) (2.5 mm TRS, splitter-ready) + [FlashZebra #0216](https://flashzebra.com/products/0216/index.shtml) Y (or Amazon [MyCableMart 3-conductor](https://www.amazon.com/dp/B0C7WHDT5P) / [Wideskall 2.5 mm stereo](https://www.amazon.com/dp/B01CRXGEDY)) + **2×** 2.5 mm→DC2 pigtails ([LGSHOP N10-DC2](https://www.amazon.com/dp/B076FV2WDB) · [HAPPYTOPSTAR](https://www.amazon.com/dp/B08ZJ3GD7T)). Must be **2.5 mm TRS (3-pole)**, not 3.5 mm and not 4-pole TRRS. |
| 1 | 10.1″ Pi HDMI touch (HAMTYSAN HCIK101V.CC) | Field UI. Ghost + drawings in [`docs/monitor/`](docs/monitor/). | [Amazon B0B9M5SCG4](https://www.amazon.com/dp/B0B9M5SCG4) |

## Print / hardware

| Qty | Item | Link |
|-----|------|------|
| 1 spool | PETG or ABS (not brittle PLA for bayonets) | [Amazon PETG](https://www.amazon.com/s?k=PETG+filament+1.75) |
| ~20 | M3 heat-set inserts | [Amazon M3 heat set inserts](https://www.amazon.com/s?k=M3+heat+set+inserts) |
| ~36 | M3×8–20 socket screws | 12 for the three port cookies (4 each). 4× M3×20 lid-to-body (nuts under the stem / T plates). 6× M3×16 lid → `display_mount` (3 per rail). 6× M3 through the Wormfingers back into the rails (3 per rail). [Amazon M3 socket screws](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) |
| 16 | M3 hex nuts | 12 in the tube-wall traps. 4 slide into the lid-corner slots (stem / T plates cover them). [Amazon M3 hex nuts](https://www.amazon.com/s?k=M3+hex+nuts) |
| 4 | M3×25 + nuts | Wormfingers case sandwich. Comes with their Printables note. |
| 6 | M3 set screws (mirror tip/tilt) | [Amazon M3 set screws](https://www.amazon.com/s?k=M3+set+screw+kit) |
| 1 | **1/4-20 heat-set insert**, short **6.4 mm** | Floor well Ø8.1 mm. Iron in from the bed face after printing. Do not punch through. | [CNC Kitchen 1/4-20×6.4](https://cnckitchenus.store/products/heat-set-insert-1-4-20x6-4-camera-thread-short-version-20-pieces) · [Amazon](https://www.amazon.com/s?k=1/4-20+heat+set+insert) |
| 1 | 1/4-20 camera screw | Into that insert (tripod / clamp) | [Amazon 1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | Flocking sheet or flat black paint | [Amazon camera flocking paper](https://www.amazon.com/s?k=camera+flocking+paper) |

## Print export cheatsheet

`./export_stls.sh` writes print STLs under [`stls/`](stls/) by fork. Those files are committed.

| Flag / wrapper | Out | Mouth (`ARM_MOUNT=0` / `arm_*_f`) |
|----------------|-----|-----------------------------------|
| (none) | `stls/v/` | 52×0.75 F reverse / printed F |
| `--bsplit` | `stls/bsplit/` | 52×0.75 F reverse / printed F |
| `--hybrid` | `stls/hybrid/` | 52×0.75 F reverse / printed F |
| `--shadowgraph` / `./export_shadowgraph.sh` | `stls/hybrid_shadowgraph/` | 52×0.75 F reverse / printed F; shadowgraph R tube |
| `--efhybrid` / `./export_efhybrid.sh` | `stls/EFhybrid/` | **58×0.75** EF reverse / printed EF |
| `--ehybrid` / `./export_ehybrid.sh` | `stls/Ehybrid/` | **52×0.75** E reverse / printed E |

Or set `PART` and F6:

- `chassis` — junction box only (print floor on the bed)
- `stem` / `arm_l` / `arm_r` / `arm_t` — tube + flange (print the square flange on the bed)
- `lid` — chamber lid
- `mirror_tray` / `bs_tray` / `hybrid_tray` — splitter cartridge
- `brace` — hybrid tripod plate (print floor on the bed; insert from the bed)
- `shims` — 0.2 / 0.5 / 1.0 mm focus rings
- `elnikkor_adapter` — male M42 → female L39×26 TPI (print the M42 male on the bed)

`--bsplit` parts: `chassis` / `stem` / `arm_r` (reflect, +X) / `arm_t` (transmit, +Y, shorter by `bs_t_comp`) / `lid` / `bs_tray` / `shims` / `elnikkor_adapter`

`--hybrid` / `--hybrid-shift` / `--efhybrid` / `--ehybrid` parts: `chassis` / `stem` / `arm_r` / `arm_t` / `lid` / `hybrid_tray` / `brace` (D7000 hybrids) / `shims` / `elnikkor_adapter`. `--hybrid-shift` also writes `*_inner` / `*_outer` for PETG lining + PCTG shell. Drop the whole 50×50×1 plate into the slot (S1 toward the lens). Do not cut it.

`--shadowgraph` parts: same list, but tubes are not toed. T is conjugate (`▲ T shadowgraph`). R is the longer razor-slot tube (`▲ R shadowgraph`). Do not swap them. Bench setup and Kraken plates: [README — Shadowgraph](README.md#shadowgraph).

## 50/50 plate fork (optional)

Same cameras and stem hardware. One [Edmund 50×50 mm 50R/50T plate](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/) (#43-359, 1 mm, S2 uncoated) **instead of** two first-surface mirrors. Both bodies get the same image at half the light — not a stitch. AR-backed 50×50 is [#45-854](https://www.edmundoptics.com/p/50-x-50mm-50r50t-vis-plate-beamsplitter/6281/) (3 mm, ~$263).

## Hybrid pano — D7000

Open [`openscad/hybrid/WATCH_ME.scad`](openscad/hybrid/WATCH_ME.scad). Export with `./export_stls.sh --hybrid`. Print `chassis` (floor on the bed), `stem`, `arm_r`, `arm_t`, `lid`, `hybrid_tray`, `brace` (floor on the bed), `shims`, `elnikkor_adapter` (M42 male on the bed). Countryside: [`docs/kraken/el135_scene.png`](docs/kraken/el135_scene.png). Brace is sized for the **72 mm** 135/180 arms.

### Assembly

1. Box floor on the bed; tubes flange-on-bed; **brace** floor on the bed. Black PETG/ABS. Iron a **1/4-20×6.4** heat-set into the **chassis** floor well and another into the **brace** well, both from the bed face. Do not punch through. Tripod goes in the brace, not the box.
2. Drop the uncut 50×50×1 into the tray from +Z, **S1 toward the lens**. Roof pegs sit past the plate edge so it drops in. Seat the tray in the box corners. Lid forks over the two posts.
3. **Lid Pi holes are not threaded.** They are Ø2.3 mm, 2.5 mm deep, 1.5 mm floor. Drive **M2.5×6 thread-forming** screws from the outside. Do not punch through, and do not slice them as through-holes.
4. Flanges are engraved **▲ R** (side, +X) and **▲ T** (back, +Y). Bolt with the arrow at the top (box floor down) so the toe points at the lens. Do not swap the arms — T is shorter (`bs_t_comp`).
5. Nuts in the wall traps; 4× M3 per cookie. Screw a 52 mm **F** reverse ring into each mouth; bayonet the D7000s. Or print `arm_*_f` (`ARM_MOUNT=1`) and dry-fit the printed F; add `F_MOUNT_CLOCK` if the first print locks 90° off.
6. Helicoid + `elnikkor_adapter` + **EL-Nikkor 135/5.6** on the stem for a **~0.61 m** subject. The 50/2.8 and the F 50/1.8 are close-up only. The F 50 stem takes the **54 mm / 2 mm-cookie** camera tubes (`arm_*_s` / `arm_*_sf`), not the 72 mm 135/180 pair. Landscape infinity is the **180**, not a shorter stem.
7. Shim one arm until both live-views are sharp on the same subject without touching the helicoid. MC-DC2 Y-lead for sync.
8. Both bodies **upright**. Bolt `brace` from below: one 1/4-20 up into the box insert, two 1/4-20s through the **slots** into the D7000 bases. The plate is solid with hex cutouts. Iron the tripod insert at the **centroid**. Mount the tripod there, not in the box.

Kraken for the 135: [`docs/kraken/el135_frames.png`](docs/kraken/el135_frames.png) · [`docs/kraken/el135_pano.png`](docs/kraken/el135_pano.png) (~14 cm object stitch at 0.61 m, 1.7× one DX). You already have the D7000s and the 50/2.8 (close-up only).

The 90 mm box plus the D7000 46.5 mm register is already **~136 mm** before any tube or mount. A 135 cannot reach infinity on this chassis (floor is ~150 mm with L39 + reverse rings). Infinity needs **f ≈ PATH_TOTAL ≈ 174 mm**.

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 1 | **Edmund 50×50×1 mm 50R/50T** #43-359 | Fits the printed tray. **S2 uncoated** — the S2 ghosts in the stitch. Do not cut it. | [Edmund #43-359](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/) |
| 1 | **Edmund 50×50×3 mm 50R/50T VIS** #45-854 (optional) | Same 50/50 on S1, **S2 AR** Ravg ≤1% 400–700 nm (black-dot S1). **~$263**. 3 mm, not 1 mm — will not drop into the current tray; needs a thicker slot and ~3× `bs_t_comp`. Edmund does not sell a 50×50×1 mm with S2 AR. | [Edmund #45-854](https://www.edmundoptics.com/p/50-x-50mm-50r50t-vis-plate-beamsplitter/6281/) |
| 1 | **EL-Nikkor 135 mm f/5.6** | Taking lens at **~0.61 m**. 4×5 circle covers the 42.5 mm stitch. **L39×26 TPI**. Used often **$80–150**. | [eBay](https://www.ebay.com/sch/i.html?_nkw=el-nikkor+135mm+f%2F5.6) · [Amazon](https://www.amazon.com/s?k=el-nikkor+135mm) |
| 1 | **EL-Nikkor 180 mm f/5.6** (or Componon-S / Rodagon 180) | Landscape **infinity** on this path. Rack the 12–19 mm helicoid out **~6.5 mm** (173.5 → 180). 5×7 circle. Barrel is **62 mm**, not L39. Used often **$200–500**, scarcer than the 135. | [eBay](https://www.ebay.com/sch/i.html?_nkw=el-nikkor+180mm+f%2F5.6) · [Componon-S 180](https://www.ebay.com/sch/i.html?_nkw=componon-s+180) · [Rodagon 180](https://www.ebay.com/sch/i.html?_nkw=rodagon+180) |
| 1 | **M62×1 helicoid** 17–31 mm | Fine focus for the **180**. Male into `stem_el180`, female for the lens. Until it ships, print `el180_adapter` (same 17 mm collapsed length). | Search **M62 focusing helicoid 17-31**. M65×1 is easier to find ([Pixco M65 17–31](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01N1GOL39)); that needs M65↔M62 rings. |
| 1 | Printed `el180_adapter` | Male M62 into the stem nut, female M62 for the 180. Same stack as the helicoid at **17 mm**. | export `PART=el180_adapter` |
| 1 | Printed `elnikkor_adapter` | Male M42 into the helicoid, female L39 for the **135** (or the 50) | export `PART=elnikkor_adapter` |
| 1 | **M42–M42 helicoid** 12–19 mm | Fine focus for the **135** only. | [Fotasy 12–19](https://www.amazon.com/Fotasy-Helicord-Focusing-Helicoid-Extention/dp/B01N5V1QAC) · [Pixco 12–19](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01IGGQR7Y) |
| 1 | **M42 extension tubes** (optional) | If the 180 is still short of infinity at helicoid max, stack 5–10 mm. If the 135 is short of 0.61 m, same tubes. | [M42 extension tube set](https://www.amazon.com/s?k=M42+extension+tube+set) |
| 2 | **Fotodiox Nikon F reverse ring, 52 mm** | Arms are 52×0.75 | [Fotodiox 52 mm](https://www.amazon.com/Fotodiox-Reverse-Adapter-Compatible-Cameras/dp/B001G4NBSC) |
| 1 | Dual-camera sync | Same as the V | [FlashZebra #0236](http://flashzebra.com/products/0236/) + [#0216](https://flashzebra.com/products/0216/index.shtml) + 2× [2.5 mm→DC2](https://www.amazon.com/dp/B076FV2WDB) |
| 1 spool | PETG or ABS | Chassis + tray | [Amazon PETG](https://www.amazon.com/s?k=PETG+filament+1.75) |
| 16 | M3 hex nuts + 12× M3×10–16 + 4× M3×20 | 12 in the port cookies. 4 lid-corner nuts (slide in from stem / T, plates cover the slots) with M3×20 through the lid | [M3 nuts](https://www.amazon.com/s?k=M3+hex+nuts) · [M3 screws](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) |
| 4 | M2.5×6 thread-forming | Blind Pi holes in the lid (58×49 HAT). Do not punch through. | [M2.5 screws](https://www.amazon.com/s?k=M2.5+6mm+screw) |
| 2 | **1/4-20 heat-set**, short 6.4 mm | Chassis floor + **centroid** well in `brace`. Ø8.1. Iron in from the bed face. | [CNC Kitchen 1/4-20×6.4](https://cnckitchenus.store/products/heat-set-insert-1-4-20x6-4-camera-thread-short-version-20-pieces) · [Amazon](https://www.amazon.com/s?k=1/4-20+heat+set+insert) |
| 3 | 1/4-20 × **16–25 mm** | From below: brace → box insert, brace → each D7000 (slots). | [1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | 1/4-20 tripod screw | Into the **brace** insert (not the box). | [1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | Flocking or matte black + fuzzy skin on the tray | Kill bounce inside the cartridge | [flocking paper](https://www.amazon.com/s?k=camera+flocking+paper) |

A 150 mm EL-Nikkor / Rodagon / Componon-S focuses at **~1.1 m** on this path. Infinity is the **180** (helicoid +6.5 mm), not a shorter stem and not the 135.

## Hybrid shift — D7000 (no tube toe)

Open [`openscad/hybrid_shift/WATCH_ME.scad`](openscad/hybrid_shift/WATCH_ME.scad). Export with `./export_stls.sh --hybrid-shift`. For **D800 FX**, set `FX_MODE = 1` in the customizer (or `./export_hybrid_shift_fx.sh`) → `stls/hybrid_shift_fx/`; reuse stem, tray, and tools from the DX shift kit. Same plate, stem, and path as hybrid. Camera tubes are **square**; cookies sit on the cube faces and the bores sit `sensor_shift()` off center. Print `*_inner` in PETG or CF-PETG and `*_outer` in PCTG (lining 1.6 mm). Or print the unsplit `chassis` / `arm_r` / `arm_t` / `lid` / `stem` in one dark filament. Flanges stay **▲ R** / **▲ T** at the top — there is no toe to aim. Brace holes follow the shifted 1/4-20s. Cartridge and PETG liners: same Bambu fuzzy skin (`None (Allow Paint)`, thickness 0.3 mm, point distance 0.8 mm) — see [README — Shift kit](README.md#shift-kit-stls/hybrid_shift/).

## EF hybrid — 5D Mark III

Same L, same uncut plate, same stem (helicoid + 135 + adapter). Bodies are two **5D Mark III** (36×24, EF, 44 mm). `PATH_TOTAL` ≈ **171 mm**; the 135 focuses at **~0.64 m**. Stitch ≈ **64.8 mm / 21.5° / ~10368×3840**.

Open [`openscad/EFhybrid/WATCH_ME.scad`](openscad/EFhybrid/WATCH_ME.scad). Export with `./export_stls.sh --efhybrid` or `./export_efhybrid.sh`. Countryside: [`docs/kraken/el135_d7000_5d3.png`](docs/kraken/el135_d7000_5d3.png).

Print the same part list as the D7000 hybrid. Shared buy list too: plate, 135, helicoid, adapter, PETG, M3, lid screws, Pi screws, 1/4-20 heat-set, flocking. Swap the cameras and the mouths.

### Buy (delta)

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 2 | Canon **5D Mark III** bodies (no lenses) | FF windows, 44 mm register | (you have these, or buy used) |
| 2 | **Fotodiox Canon EF reverse ring, 58 mm** | Mouths are **58×0.75**. A 52 mm ring will not start. | [Fotodiox 58 mm EOS](https://www.amazon.com/Fotodiox-Reverse-Adapter-Mounting-Threads/dp/B001G4PA36) |
| 1 | Dual **N3** shutter | 5D III is N3, not MC-DC2 | [Canon N3 release](https://www.amazon.com/s?k=canon+n3+shutter+release) · [N3 Y-splitter](https://www.amazon.com/s?k=canon+n3+dual+shutter) |

`cam/` is D7000 USB only. Fire the 5Ds from the N3 lead.

### Assembly

Same tray / lid / Pi holes / flange arrows as the D7000 hybrid.

1. Print floor-down / flange-on-bed. Black PETG/ABS. Iron the **1/4-20×6.4** heat-set into the floor from the bed face.
2. Plate in from +Z, **S1 toward the lens**. Lid forks over the posts.
3. **▲ R** on +X, **▲ T** on +Y, arrow up. T is shorter. Do not swap the arms.
4. Screw the **58 mm EF** reverse rings into the mouths; bayonet the 5Ds. No lens on the EF mounts — iris is on the 135.
5. Or print `arm_r_f` / `arm_t_f` (`ARM_MOUNT=1`). Dry-fit a 5D. If the lock is 90° off, add `EF_MOUNT_CLOCK`. If the lugs are stiff, ease `EF_LUG_SWEEP` / `EF_LUG_OD`.
6. Helicoid + adapter + 135. Subject ~0.64 m, not infinity.
7. Shim one arm until both live-views match without touching the helicoid. N3 Y-lead for sync.

## E hybrid — Sony α7

Same L, same plate, same stem. Bodies are two **α7** (ILCE-7; 35.8×23.9, E, **18 mm**). Fold is still 55+72, so `PATH_TOTAL` is **145 mm**. The 135 focuses at **~2 m**, not 0.61 m. Stitch ≈ **64.4 mm / 25° / ~10800×4000**.

Open [`openscad/Ehybrid/WATCH_ME.scad`](openscad/Ehybrid/WATCH_ME.scad). Export with `./export_stls.sh --ehybrid` or `./export_ehybrid.sh`. Countryside: [`docs/kraken/el135_d7000_a7.png`](docs/kraken/el135_d7000_a7.png).

Print the same part list. Shared buy list is the D7000 hybrid minus the F rings and MC-DC2 lead.

### Buy (delta)

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 2 | Sony **α7** bodies (no lenses) | FF windows, 18 mm register | (ILCE-7 / later E FF; CIPA box is the first A7) |
| 2 | **Fotodiox Sony E reverse ring, 52 mm** | Mouths are **52×0.75** — same *thread* as the Nikon hybrid, **E bayonet**, not F. A Nikon F reverse ring will not take an A7. | [Fotodiox 52 mm E](https://www.amazon.com/Fotodiox-Filter-Thread-Reverse-Adapter/dp/B0054ENYI2) |
| 1 | Dual **Multi Terminal** shutter | First A7 is Multi Terminal, not N3 / MC-DC2 | [Sony Multi Terminal release](https://www.amazon.com/s?k=sony+multi+terminal+shutter+release) · [RM-VPR1](https://www.amazon.com/s?k=sony+RM-VPR1) |

`cam/` is D7000 USB only. Fire the A7s from the Multi Terminal lead.

### Assembly

Same tray / lid / Pi holes / flange arrows as the other L forks.

1. Print floor-down / flange-on-bed. Black PETG/ABS. Do not print the bayonet in PLA. Iron the **1/4-20×6.4** heat-set into the floor from the bed face.
2. Plate in from +Z, **S1 toward the lens**. Lid forks over the posts.
3. **▲ R** on +X, **▲ T** on +Y, arrow up. T is shorter. Do not swap the arms.
4. Screw the **52 mm E** reverse rings into the mouths; bayonet the A7s. No lens on the E mounts.
5. Or print `arm_r_f` / `arm_t_f` (`ARM_MOUNT=1`). Dry-fit an A7. If the lock is 90° off, add `E_MOUNT_CLOCK`. If the lugs are stiff, ease `E_LUG_SWEEP` / `E_LUG_OD`.
6. Helicoid + adapter + 135. Subject **~2 m**. A chart at 0.61 m will not focus.
7. Turn **IBIS off**. Shim one arm until both live-views match without touching the helicoid.

## Notes

- Coatings face the **lens**; glass sits behind (toward +Y). Wrong way = ghosts and blocked camera tunnels.
- Short 12–19 mm helicoid is for **fine** focus; fixed chassis length sets most of the register. Stack tubes if you cannot reach the working distance.
- Hybrid mouths: D7000 = 52 mm **F** reverse ring; 5D III = 58 mm **EF**; α7 = 52 mm **E**. Same 52×0.75 thread on Nikon and Sony is not the same ring.
- Tune `F_REV_STACK` / `EF_REV_STACK` / `E_REV_STACK` if the working distance is long or short.
- Floor is a Ø8.1 mm well for a **1/4-20×6.4** heat-set, not a printed thread. Iron from the bed face; leave the 1.2 mm keep so it stays blind.
