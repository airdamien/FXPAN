# Bill of materials — Nikon Dual T

Path target: **PATH_TOTAL ≈ 173.5 mm** with current defaults (`D_LENS_TO_KNIFE=55`, `D_KNIFE_TO_MOUNT=72`). See [OPTICS.md](OPTICS.md). Buy **first-surface** mirrors only.

## Optics (order these)

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 2 | **50×50 mm first-surface mirror** (enhanced Al or protected Ag) | Field splitter at 45° | [Edmund 50×50 mm Silver 4–6λ](https://www.edmundoptics.com/p/50-x-50mm-silver-4-6lambda-mirror/31994/) · cheaper DIY: [Amazon “first surface mirror” search](https://www.amazon.com/s?k=first+surface+mirror+50mm) · craft sheet to cut: [Amazon 6×8" front surface sheet](https://www.amazon.com/s?k=front+surface+mirror+6x8) |
| 1 | **M42–M42 focusing helicoid** (12–19 mm) | Fine focus on stem | [Fotasy 12–19 mm](https://www.amazon.com/Fotasy-Helicord-Focusing-Helicoid-Extention/dp/B01N5V1QAC) · [Pixco 12–19 mm](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01IGGQR7Y) |
| 1 | **Longer M42 helicoid or M42 extension tubes** (optional stack) | Extra travel if infinity is short | [Amazon M42 helicoid 25–55](https://www.amazon.com/s?k=M42+focusing+helicoid+25-55) · [M42 extension tube set](https://www.amazon.com/s?k=M42+extension+tube+set) |
| 1 | **M39→M42 adapter** (if using enlarger lens) | Enlarger lenses are often M39 | [Amazon M39 to M42](https://www.amazon.com/s?k=M39+to+M42+adapter) |
| 1 | **Enlarger / LF taking lens** ~90–150 mm | Large image circle for dual DX | e.g. search used: Schneider Componon, Rodenstock Rodagon, EL-Nikkor — [eBay enlarger lens](https://www.ebay.com/sch/i.html?_nkw=componon+OR+rodagon+OR+el-nikkor+lens) |

## Cameras / sync

| Qty | Item | Link |
|-----|------|------|
| 2 | Nikon D7000 bodies (no lenses) | (you have these) |
| 1 | MC-DC2-compatible remote | [Kiwifotos MC-DC2](https://www.amazon.com/Kiwifotos-MC-DC2-Remote-Shutter-Release/dp/B071D9Y331) |
| 1 | Dual-camera sync path | Prefer [FlashZebra #0236](http://flashzebra.com/products/0236/) (2.5 mm TRS, splitter-ready) + [2× MC-DC2 pigtails](https://www.amazon.com/dp/B0939SV7WP) + a **2.5 mm stereo Y-splitter** ([search](https://www.amazon.com/s?k=2.5mm+stereo+y+splitter+TRS)) |

## Print / hardware

| Qty | Item | Link |
|-----|------|------|
| 1 spool | PETG or ABS (not brittle PLA for bayonets) | [Amazon PETG](https://www.amazon.com/s?k=PETG+filament+1.75) |
| ~20 | M3 heat-set inserts | [Amazon M3 heat set inserts](https://www.amazon.com/s?k=M3+heat+set+inserts) |
| ~20 | M3×8–16 socket screws | [Amazon M3 socket screws](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) |
| 6 | M3 set screws (mirror tip/tilt) | [Amazon M3 set screws](https://www.amazon.com/s?k=M3+set+screw+kit) |
| 2 | 1/4-20 screws (arm cradles / tripod) | [Amazon 1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | Flocking sheet or flat black paint | [Amazon camera flocking paper](https://www.amazon.com/s?k=camera+flocking+paper) |

## Print export cheatsheet

In [`openscad/params.scad`](openscad/params.scad) set `PART`, then F6 → STL:

- `chassis` — one solid T (junction + stem + both F-mounts)
- `lid` — chamber lid
- `mirror_tray` — L+R trays
- `shims` — 0.2 / 0.5 / 1.0 mm focus rings

## Notes

- Coatings face the **lens**; glass sits behind (toward +Y). Wrong way = ghosts and blocked camera tunnels.
- Short 12–19 mm helicoid is for **fine** focus; fixed chassis length sets most of the 136.5 mm register. Stack tubes if you cannot reach infinity.
- Dry-fit printed F bayonets on a body before hanging both D7000s on the chassis.
