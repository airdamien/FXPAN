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
| 1 | Dual-camera sync path | Prefer [FlashZebra #0236](http://flashzebra.com/products/0236/) (2.5 mm TRS, splitter-ready) + [2× MC-DC2 pigtails](https://www.amazon.com/dp/B0939SV7WP) + a **2.5 mm stereo Y-splitter** ([search](https://www.amazon.com/s?k=2.5mm+stereo+y+splitter+TRS)) |

## Print / hardware

| Qty | Item | Link |
|-----|------|------|
| 1 spool | PETG or ABS (not brittle PLA for bayonets) | [Amazon PETG](https://www.amazon.com/s?k=PETG+filament+1.75) |
| ~20 | M3 heat-set inserts | [Amazon M3 heat set inserts](https://www.amazon.com/s?k=M3+heat+set+inserts) |
| ~20 | M3×8–16 socket screws | 12 for the three port cookies (4 each). [Amazon M3 socket screws](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) |
| 12 | M3 hex nuts | Drop into the inner traps, then screw the tubes on. [Amazon M3 hex nuts](https://www.amazon.com/s?k=M3+hex+nuts) |
| 6 | M3 set screws (mirror tip/tilt) | [Amazon M3 set screws](https://www.amazon.com/s?k=M3+set+screw+kit) |
| 2 | 1/4-20 screws (arm cradles / tripod) | Printed **1/4-20** in the chassis floor (print that face on the bed). [Amazon 1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | Flocking sheet or flat black paint | [Amazon camera flocking paper](https://www.amazon.com/s?k=camera+flocking+paper) |

## Print export cheatsheet

`./export_stls.sh` writes the panorama V to [`stls/`](stls/). `--bsplit` → `stls/bsplit/`. `--hybrid` → `stls/hybrid/`. Or set `PART` and F6:

- `chassis` — junction box only (print floor on the bed)
- `stem` / `arm_l` / `arm_r` — tube + flange (print the square flange on the bed)
- `lid` — chamber lid
- `mirror_tray` — V cartridge
- `shims` — 0.2 / 0.5 / 1.0 mm focus rings
- `elnikkor_adapter` — male M42 → female L39×26 TPI (print the M42 male on the bed)

`--bsplit` parts: `chassis` / `stem` / `arm_r` (reflect, +X) / `arm_t` (transmit, +Y, shorter by `bs_t_comp`) / `lid` / `bs_tray` / `shims` / `elnikkor_adapter`

`--hybrid` parts: `chassis` / `stem` / `arm_r` (right half, +X) / `arm_t` (left half, +Y) / `lid` / `hybrid_tray` / `shims` / `elnikkor_adapter`. Drop the whole 50×50×1 plate into the slot (S1 toward the lens). Do not cut it.

## 50/50 plate fork (optional)

Same cameras and stem hardware. One [Edmund 50×50 mm 50R/50T plate](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/) (#43-359, 1 mm, S2 uncoated) **instead of** two first-surface mirrors. Both bodies get the same image at half the light — not a stitch.

## Hybrid pano — buy list

Open [`openscad/hybrid/WATCH_ME.scad`](openscad/hybrid/WATCH_ME.scad). Export with `./export_stls.sh --hybrid`. Print `chassis` (floor on the bed), `stem`, `arm_r`, `arm_t`, `lid`, `hybrid_tray`, `shims`, `elnikkor_adapter` (M42 male on the bed). Drop the 50×50×1 plate into the tray slot from above, **S1 toward the lens**.

Kraken for the 135: [`docs/kraken/el135_frames.png`](docs/kraken/el135_frames.png) · [`docs/kraken/el135_pano.png`](docs/kraken/el135_pano.png) (~14 cm object stitch at 0.61 m, 1.7× one DX). You already have the D7000s and the 50/2.8 (close-up only).

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 1 | **Edmund 50×50×1 mm 50R/50T** #43-359 | The only optic in the box. Do not cut it. | [Edmund #43-359](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/) |
| 1 | **EL-Nikkor 135 mm f/5.6** | Taking lens. 4×5 circle covers the 42.5 mm stitch. Same **L39×26 TPI** as the 50. Used often **$80–150**. | [eBay](https://www.ebay.com/sch/i.html?_nkw=el-nikkor+135mm+f%2F5.6) · [Amazon](https://www.amazon.com/s?k=el-nikkor+135mm) |
| 1 | Printed `elnikkor_adapter` | Male M42 into the helicoid, female L39 for the 135 (or the 50) | export `PART=elnikkor_adapter` |
| 1 | **M42–M42 helicoid** 12–19 mm | Fine focus on the stem | [Fotasy 12–19](https://www.amazon.com/Fotasy-Helicord-Focusing-Helicoid-Extention/dp/B01N5V1QAC) · [Pixco 12–19](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01IGGQR7Y) |
| 1 | **M42 extension tubes** (optional) | Extra travel if the 135 is short of 0.61 m | [M42 extension tube set](https://www.amazon.com/s?k=M42+extension+tube+set) |
| 2 | **Fotodiox Nikon F reverse ring, 52 mm** | Arms are 52×0.75 | [Fotodiox 52 mm](https://www.amazon.com/Fotodiox-Reverse-Adapter-Compatible-Cameras/dp/B001G4NBSC) |
| 1 | Dual-camera sync | Same as the V | [FlashZebra #0236](http://flashzebra.com/products/0236/) + [2× MC-DC2 pigtails](https://www.amazon.com/dp/B0939SV7WP) + [2.5 mm stereo Y](https://www.amazon.com/s?k=2.5mm+stereo+y+splitter+TRS) |
| 1 spool | PETG or ABS | Chassis + tray | [Amazon PETG](https://www.amazon.com/s?k=PETG+filament+1.75) |
| 12 | M3 hex nuts + 12× M3×10–16 | Three port cookies, 4 each | [M3 nuts](https://www.amazon.com/s?k=M3+hex+nuts) · [M3 screws](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) |
| 4 | M3×10 lid screws | Corners of the lid | same assortment |
| 1 | 1/4-20 camera screw | Printed thread in the floor | [1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | Flocking or matte black + fuzzy skin on the tray | Kill bounce inside the cartridge | [flocking paper](https://www.amazon.com/s?k=camera+flocking+paper) |

A 150 mm EL-Nikkor / Rodagon / Componon-S is the next step closer to “far” (focus ~1.1 m on this path). Infinity needs the chassis path ≈ the focal length (~174 mm), not a longer lens.

## Notes

- Coatings face the **lens**; glass sits behind (toward +Y). Wrong way = ghosts and blocked camera tunnels.
- Short 12–19 mm helicoid is for **fine** focus; fixed chassis length sets most of the 136.5 mm register. Stack tubes if you cannot reach infinity.
- Screw a 52 mm F reverse ring into each arm; bayonet the D7000s onto those. Tune `F_REV_STACK` if infinity is long/short.
