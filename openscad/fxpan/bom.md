# Bill of materials — FXPAN 65

Two D800 bodies behind one EL-Nikkor 180/5.6N and a **75 × 75 × 1 mm** 50/50
plate at 45°. Stitch is 64.80 × 23.9 mm, 2.711:1, 65.1 MP. Path is
**179.5 … 193.5 mm** with infinity at 17.5 mm of helicoid travel.

Working aperture is **f/8 to f/22**, corner-to-corner clean from f/8.4. Two
line items decide whether you get even that. Get them right and the rest is
fasteners.

- **75 mm plate, not 50 mm.** At 45° a plate only presents `size/√2` across
  the fold, and the frame needs 44.7 mm there at f/5.6. 75 mm gives 53.03; the
  50 mm plate you already own gives 35.36 and clips until f/11 — and it clips
  the long axis of the panorama, not just the corners.
- **Metal reverse rings, not the printed bayonet.** The ring keeps the real
  44 mm F throat, which is what sets the f/8.4 limit. The printed F mesh is
  38 mm clear and **never** passes the whole frame, at any aperture.

Why: [PLAN.md](PLAN.md). How: [README.md](README.md).

## Optics

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 1 | **Edmund #37202** — 75 × 75 × 1.0 mm 50R/50T VIS plate beamsplitter | Takes the plate off the list of things that limit this body: 53.03 mm in-plane against the 44.66 mm the frame needs, **+18.7% at f/5.6** and more as you stop down. S1 is 50/50 ±5% at 550 nm, ±10% over 400–700. S2 is broadband AR, Ravg ≤1%. 1.0 mm thick, which is the other thing that has to be right. Do not cut it. **S1 faces the lens.** | [Edmund #37202](https://www.edmundoptics.com/p/75-x-75mm-50-50rt-vis-plate-beamsplitter/37202/) |
| 1 | **EL-Nikkor 180 mm f/5.6N** (or Componon-S 180, Rodagon 180) | Taking lens. 5×7 image circle, so the 64.80 mm stitch is nowhere near the edge of coverage. `EL_FOCAL = 180` is what the whole path budget is solved against. Barrel is **M62**, not L39 — it threads into the helicoid directly. Used $200–500. | [eBay EL-Nikkor 180](https://www.ebay.com/sch/i.html?_nkw=el-nikkor+180mm+f%2F5.6) · [Componon-S 180](https://www.ebay.com/sch/i.html?_nkw=componon-s+180) · [Rodagon 180](https://www.ebay.com/sch/i.html?_nkw=rodagon+180) |
| 1 | **M62×1 helicoid, 17–31 mm** | Focus. Male bottoms into the stem's 8 mm female boss; female takes the lens. Infinity lands at 17.5 mm, near collapsed, and the full 14 mm of travel reaches 2.6 m. **Do not substitute a longer one** — the 17 mm collapsed length is inside the path budget and anything taller pushes infinity out of reach. | Search **M62 focusing helicoid 17-31**. M65×1 is easier to find ([Pixco M65 17–31](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01N1GOL39)) but then you need M65↔M62 step rings, which add stack — measure before you commit. |
| 2 | **Fotodiox Nikon F reverse ring, 52 mm** | The camera mouths. Threads into the arms' M52×0.75 female, presents an F bayonet with the **real 44 mm throat**. That throat is what sets the body's f/8.4 limit, and 44 mm is as wide as an F mount gets — so this is both the recommended mouth and the ceiling. `ARM_MOUNT = 0` is the default for it. | [Fotodiox 52 mm F reverse](https://www.amazon.com/Fotodiox-Reverse-Adapter-Compatible-Cameras/dp/B001G4NBSC) |

### If you only have the 50 mm plate

`BS_SIZE = 50` still builds and `BOX_Z` shrinks from 108 to 83 automatically.
It is a real fallback, just an honest **f/11 one**:

| f-stop | need | 50 mm plate gives 35.36 |
| --- | --- | --- |
| 5.6 | 44.66 mm | clips |
| 8 | 38.72 mm | clips |
| 11 | 34.93 mm | +1.2% |
| 16 | 31.78 mm | +11.3% |

Edmund's 50 mm options, for reference: [#43-359](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/)
is 1 mm but **S2 uncoated**, and [#45-854](https://www.edmundoptics.com/p/50-x-50mm-50r50t-vis-plate-beamsplitter/6281/)
has S2 AR but is 3 mm, which is worse (see below). At 75 mm Edmund only sells
it AR-coated and 1 mm, so on the recommended build the two decisions that
matter are already made for you.

### Why 1 mm and why AR

Neither of these is a preference; both are the difference between sharp and
not. A tilted plate puts its errors on the **transmit path only** — S1 faces
the lens, so the reflected light never enters glass.

**Astigmatism** from the tilt, against depth of focus at c = 0.020 mm:

| thickness | astigmatism | verdict |
| --- | --- | --- |
| 1.0 mm | 0.172 mm | inside the 0.224 mm depth of focus at **f/5.6** |
| 3.0 mm | 0.516 mm | needs **f/16** before it hides |

So a 3 mm plate costs you three stops of usable aperture on one of the two
cameras, and it will not drop into the tray slot either.

**Back-surface ghost.** Light reflecting off S2 lands **0.743 mm** from the
real image, which is **152 px** on a D800 — far enough to read as a distinct
double, close enough to sit inside the subject.

| S2 | ghost intensity |
| --- | --- |
| uncoated | 4.0% of the T image |
| broadband AR | 1.0% |

Only the T camera gets it, which is worse than it sounds: the stitch would
have a ghost on one side of the seam and none on the other. #37202 is AR
coated, so this costs nothing on the recommended build.

## Cameras and sync

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 2 | **Nikon D800** bodies, no lenses | 36 × 23.9 mm, 7360 × 4912, 46.5 mm register. Both sit **upright and landscape** — the seam is horizontal and `cam/pano.py` requires it. | (you have these) |
| 1 | **10-pin dual release** | The D800 uses the **10-pin** remote terminal, not MC-DC2 — a lead from the D7000 bodies will not fit. Both shutters have to fire together or the stitch tears on anything moving. | [10-pin Y splitter](https://www.ebay.com/sch/i.html?_nkw=nikon+10+pin+dual+camera+shutter+release) · [MC-30A](https://www.amazon.com/s?k=Nikon+MC-30A) |

`cam/` is D7000 USB only. Fire the D800s from the 10-pin lead and pull the
files afterwards.

## Print and hardware

| Qty | Item | Why | Link |
|-----|------|-----|------|
| ~1.5 spool | **PETG or ABS**, dark | Chassis, lid, tray, arms, stem, base, cradles. Not PLA — the M52 threads and the cradle flange both see real load, and a 1 kg body hanging on a brittle mouth is how you break a D800. | [Amazon PETG](https://www.amazon.com/s?k=PETG+filament+1.75) |
| scraps | 4 accent colours | Only if you want the FXPAN badge in filament rather than paint: gold, off-white, red, grey. A few grams each. | — |
| 6 | **M3 × 12** socket screws + 6 **M3 nuts** | Port cookies, 2 per cookie into wall nut traps. Three cookies: stem, arm R, arm T. | [M3 screws](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) · [M3 nuts](https://www.amazon.com/s?k=M3+hex+nuts) |
| 4 | **M3 × 20** + 4 **M3 nuts** | Lid to chassis, one per corner. Nuts drop into the corner pockets before the lid goes on. | as above |
| 8 | **M3 × 16–20** + 8 **M3 nuts** | Cradle to base, 4 per cradle. Heads sink into the plinth top, nuts sit under the base. | as above |
| 4 | **M3 × 8 set screws** + 4 **M3 nuts** | Two per arm mouth at 120°, pinching the reverse-ring barrel. These hold your **roll alignment** — without them the ring can creep and one camera's horizon walks off the other's. | [M3 set screws](https://www.amazon.com/s?k=M3+set+screw+kit) |
| 2 | **1/4-20 heat-set insert, short 6.4 mm** | One in the chassis floor pad, one in the base tripod pad. Ø8.1 mm wells. Iron in **from the bed face** and leave the 1.2 mm keep so they stay blind. | [CNC Kitchen 1/4-20×6.4](https://cnckitchenus.store/products/heat-set-insert-1-4-20x6-4-camera-thread-short-version-20-pieces) · [Amazon](https://www.amazon.com/s?k=1/4-20+heat+set+insert) |
| 1 | **1/4-20 knurled thumbscrew** | Chassis onto the base origin pad, through the Ø24 mm counterbore. Hand-tight, no tool. | [1/4-20 camera thumbscrew](https://www.amazon.com/s?k=1%2F4-20+camera+thumbscrew+knurled) |
| 2 | **1/4-20 × 25 mm** | Up through the base slot and the cradle slot into each body's tripod socket. 18 mm of printed stack plus ~6 mm into the camera — **check the depth on your own bodies before you crank it down.** | [1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | **1/4-20 tripod screw** | Into the base insert at the combined centre of mass. Tripod goes there, **not** in the chassis. | as above |
| 1 sheet | **Flocking paper** or flat black paint | Chamber, tray faces, arm bores, and the F throats. The throats matter most: they are deliberately **unlined**. The throat is the tightest aperture in the body — 1.3 mm clear of the frame corners even at f/11 — so a 1.6 mm liner in there would vignette outright. | [camera flocking paper](https://www.amazon.com/s?k=camera+flocking+paper) |
| 2 | **TPU or cork pads**, 2.4 mm | Pockets in the cradle flanges, so the flange grips the body without marking it. Cut from sheet. | [cork sheet](https://www.amazon.com/s?k=2mm+cork+sheet+adhesive) |

## Print-only alternatives

Both of these work and both cost you something. Neither is the recommended
build.

| Part | Instead of | What it costs |
|------|-----------|---------------|
| `el180_adapter` | the M62 helicoid | A fixed spacer solved for infinity — **no focus travel at all**, distant subjects only. Its length tracks `BOX_XY`, so it stays correct if you change the chassis. Print a second at +0.5 mm if the first lands long; shims can only add length. |
| `arm_r_f` / `arm_t_f` (`ARM_MOUNT = 1`) | the 52 mm reverse rings | The printed bayonet mesh is **38 mm** clear, and the frame corners need 38.47 mm even at infinite f-number, so it **never** passes the whole frame — f/22 still leaves the corners at 0.34. Fine for dry-fitting and checking clocking; not a way to avoid buying the rings. `WATCH_ME.scad` warns about this in its echo. |

## Export

```
./export_fxpan.sh              # 34 STLs -> stls/fxpan/
./export_fxpan.sh chassis lid  # just these
```

Wraps `./export_stls.sh --fxpan`. Each part is stamped `fxp_<name>` plus the
render minute, so a part on the bench can always be traced to the export that
made it.

Print list and bed orientations: [README.md](README.md#print-list).

To check the optics rather than trust this file:

```
pip install -r ../../kraken/requirements.txt
python ../../kraken/fxpan_paths.py
```

It ray traces the body and exits non-zero if the stitch, the shift senses or
the apertures stop matching `params.scad`.

## Notes

- **f/8 and narrower.** Corner-to-corner clean from f/8.4. At f/5.6 the four
  corners sit at 0.84 while the panorama's long axis stays clean, so it reads
  as corner shading. A 180 mm enlarger lens is happiest at f/8–f/11 anyway.

- **S1 faces the lens.** Edmund marks it. Backwards puts the glass path on the
  reflect leg while the T arm's 0.303 mm compensation is still shortening the
  transmit leg — both legs then disagree by 0.6 mm and no shim stack fixes it
  cleanly.
- **Do not swap the arms.** T (+Y, straight back) is shorter than R (+X) by
  `bs_t_comp = 0.303 mm`. Flanges are engraved **▲ R** and **▲ T**. There is
  no tube toe on this body — each bore is translated 14.4 mm instead of tilted,
  so the arrow is for identification, not aiming.
- **The bayonet locates, the cradle carries.** A D800 is about 1 kg. Every
  printed F mount in this project is a weak point when it takes load; here it
  should never feel any.
- **This body's bore is not the others'.** `TUBE_ID` 46 and `F_BORE` 44.0
  against 52 and 40.3 elsewhere. Arms, stem and cookies are not
  interchangeable with `hybrid_shift` parts even where they look similar —
  which is why everything is stamped `fxp_`.
- **20.4° horizontal.** XPan's aspect ratio, not XPan's angle of view. 65 mm
  at 180 mm of focal length is a telephoto panorama.
- The two 50 mm first-surface mirrors are not used here. Keeping the stitch
  axis off every fold's foreshortened dimension forces all folds coplanar, and
  coplanar folds cannot make two bodies parallel. They stay with the V body.
