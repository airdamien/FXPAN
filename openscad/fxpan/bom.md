# Bill of materials — FXPAN 65

Two D800 bodies behind one EL-Nikkor 180/5.6N and a **50 × 75 × 1 mm** 50/50
plate at 45°. Stitch is 64.80 × 23.9 mm, 2.711:1, 65.1 MP. Path is
**179.5 … 193.5 mm** with infinity at 17.5 mm of helicoid travel.

Working aperture is **f/8 to f/22**, corner-to-corner clean from f/8.4. Two
line items decide whether you get even that. Get them right and the rest is
fasteners.

Nothing on this list needs measuring except your own cameras: the F register
stands 16 mm off the chassis face so a D800's front panel, which reaches
about 13 mm past its own flange, has room to come in and twist on. If yours
measures more than 16, set `D800_PROUD` before you print anything.

- **75 mm across the fold, 50 along it — and not a square.** At 45° a plate
  presents only `size/√2` in its plane of incidence, and that is the direction
  the 64.80 mm stitch has to cross: it needs 44.4 mm there at f/5.6, 75 mm
  gives 53.03, and the 50 mm square you already own gives 35.36 and clips
  until f/11 — clipping the long axis of the panorama, not just the corners.
  Along the fold nothing is foreshortened and nothing is being carried but the
  23.9 mm sensor height, so 50 mm is already +72% and a square plate is 25 mm
  of chassis height bought for a margin nobody will ever spend.
- **Metal reverse rings, not the printed bayonet — still the default.** The ring keeps the real
  44 mm F throat, which is what sets the f/8.4 limit. The printed Archive-663 mouth is
  43.5 mm (f/9.2) after the lips are bored; close, not equal.

Why: [PLAN.md](PLAN.md). How: [README.md](README.md).

## Optics

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 1 | **Edmund #37201** (stock #35-947) — 50 × 75 × 1.0 mm 50R/50T VIS plate beamsplitter | Takes the plate off the list of things that limit this body: **75 goes across the fold**, presenting 53.03 mm against the 44.39 mm the frame needs, **+19.5% at f/5.6** and more as you stop down. The 50 runs along the fold, where nothing is foreshortened and 29.05 mm is all that is asked, so it is +72% and it is the dimension that sets chassis height — which is why this is the right rectangle rather than the 75 × 75. S1 is 50/50 ±5% at 550 nm, ±10% over 400–700. S2 is broadband AR, Ravg ≤1%. 1.0 mm thick, which is the other thing that has to be right. Do not cut it. Edmund marks the coated face with a **black dot**: that dot faces the lens, and the 75 goes horizontal. | [Edmund #37201](https://www.edmundoptics.com/p/50-x-75mm-50-50rt-vis-plate-beamsplitter/37201/) |
| 1 | **EL-Nikkor 180 mm f/5.6N** (or Componon-S 180, Rodagon 180) | Taking lens. 5×7 image circle, so the 64.80 mm stitch is nowhere near the edge of coverage. `EL_FOCAL = 180` is what the whole path budget is solved against. Barrel is **M62**, not L39 — it threads into the helicoid directly. Used $200–500. | [eBay EL-Nikkor 180](https://www.ebay.com/sch/i.html?_nkw=el-nikkor+180mm+f%2F5.6) · [Componon-S 180](https://www.ebay.com/sch/i.html?_nkw=componon-s+180) · [Rodagon 180](https://www.ebay.com/sch/i.html?_nkw=rodagon+180) |
| 1 | **M62×1 helicoid, 17–31 mm** | Focus. Male bottoms into the stem's 8 mm female boss; female takes the lens. Infinity lands at 17.5 mm, near collapsed, and the full 14 mm of travel reaches 2.6 m. **Do not substitute a longer one** — the 17 mm collapsed length is inside the path budget and anything taller pushes infinity out of reach. | Search **M62 focusing helicoid 17-31**. An M65×1 17–31 ([Pixco](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01N1GOL39)) is the same travel, but both ends are M65×1. Amazon has no M65×1↔M62×1 ring. A filter step ring is 0.75 mm pitch and 6–7 mm tall, and infinity only has 0.5 mm to spare. |
| 1 | **M65×1 male to M62×1 female, flangeless** (only with the M65 helicoid) | Lens end. The 180's rear is M62×1; the M65 helicoid's front female is M65×1. Added length is **0 mm**, so the flange still seats where the path budget says it does. Do not put a ring on the stem side — print `stem_m65` so the helicoid male still bottoms on the cookie. The STEP is the finished threads, M65×1 outside and M62×1 inside, 8 mm long. | [RafCamera, flangeless, 0 mm](https://rafcamera.com/adapter-m65x1m-to-m62x1f-flangeless). Ships from Belarus, not Prime. CNC: [`sendcutsend/m65_m62_flangeless.step`](sendcutsend/m65_m62_flangeless.step). |
| 1 | Printed `m65_ring` | Stand-in until that ring arrives. Plastic has no wall between an M65 male and an M62 female, so the lens thread sits in a collar in front of a shoulder and the ring **adds 8 mm**. Collapsed focus is about **4.5 m**, not infinity. Face the 6 mm male shorter if the shoulder does not seat. Take the ring off when the metal one lands. Do not shorten the stem to make up the 8 mm — shims only add, and the metal ring is 0 mm. | `PART=m65_ring` in `WATCH_ME.scad`. Lens seat up. Print `stem_m65` with it. |
| 2 | **Fotodiox Nikon F reverse ring, 52 mm** | The camera mouths. Threads into the arms' M52×0.75 female, presents an F bayonet with the **real 44 mm throat**. That throat is what sets the body's f/8.4 limit, and 44 mm is as wide as an F mount gets — so this is both the recommended mouth and the ceiling. `ARM_MOUNT = 0` is the default for it. **Buy them before you print the arms** — you need one in hand to read the ring gauge. | [Fotodiox 52 mm F reverse](https://www.amazon.com/Fotodiox-Reverse-Adapter-Compatible-Cameras/dp/B001G4NBSC) |
| 2 | **M52 female to M42 male focusing helicoid, 17–31 mm** | One per camera, on `arm_r_hw` / `arm_t_hw`, instead of shimming the bodies. Amazon does not list an M52-to-M52. This is the Pixco/Fotasy unit the search returns: **M52 female in front, M42 male in the rear**, 17 mm collapsed to 31 mm. The M42 male screws into the cookie. A metal M52-male F ring screws into the front female. Collapsed sits inside focus; the travel moves that camera out, and the tripod screw locks it. Measured: body **69.05 mm**, 16.85 mm collapsed past a 4.67 mm M42 male, front does not rotate. Its male bottoms on a lip in the cookie. Take the **17–31**, not the 10–15. Confirm the photo: 42 mm male toward the cookie, 52 mm female toward the camera. | [Amazon: M52 to M42 helicoid 17–31](https://www.amazon.com/s?k=M52+to+M42+helicoid+17-31) |

### Which way round it goes, and what else fits

The plate is not square, so it can be fitted wrong. **75 mm horizontal,
across the fold.** The tray slot is keyed for it, but the slot will not stop
you turning the glass over in your hand first.

| | across the fold | along the fold |
| --- | --- | --- |
| what it carries | the 64.80 mm stitch, foreshortened by √2 | the 23.9 mm sensor height, not foreshortened |
| needs at f/5.6 | 44.39 mm | 29.05 mm |
| `BS_W` = 75 → 53.03 | **+19.5%** | — |
| `BS_H` = 50 | — | **+72.1%** |
| sets | nothing else | `BOX_Z`, and therefore the chassis |

Substitutions, in order of preference:

| plate | stock # | thickness | verdict |
| --- | --- | --- | --- |
| **#37201, 50 × 75** | 35-947 | **1.00** | the build. $303, in stock. |
| [#37202](https://www.edmundoptics.com/p/75-x-75mm-50-50rt-vis-plate-beamsplitter/37202/), 75 × 75 | 35-948 | 1.00 | optically identical and the original pick — it went to *Contact Us*, which is why the body is drawn around the rectangle. Set `BS_H = 75` and `BOX_Z` grows back to 108 by itself. $338 for 25 mm more chassis and no more picture. |
| [**#17536**](https://www.edmundoptics.com/p/50-x-75mm-50r50t-vis-plate-beamsplitter/17536/), 50 × 75 | 62-882 | **3.00** | **the trap.** Same size, same family, same page title, same $303, and 20+ in stock while the right one may not be. Three stops of astigmatism (below) and it will not go in the slot. **Check the thickness, not the size.** |
| [#43-359](https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/), 50 × 50 | — | 1.00 | S2 uncoated, and only 50 across the fold — see the f/11 table below. |
| [#45-854](https://www.edmundoptics.com/p/50-x-50mm-50r50t-vis-plate-beamsplitter/6281/), 50 × 50 | — | 3.00 | both faults at once. No. |

If all you have is a 50 mm square, `BS_W = 50` still builds and costs nothing
in chassis height. It is a real fallback, just an honest **f/11 one**:

| f-stop | need across the fold | 50 mm gives 35.36 |
| --- | --- | --- |
| 5.6 | 44.39 mm | clips |
| 8 | 38.36 mm | clips |
| 11 | 34.53 mm | +2.4% |
| 16 | 31.33 mm | +12.9% |

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
have a ghost on one side of the seam and none on the other. #37201 is AR
coated, so this costs nothing on the recommended build.

## Anamorphic adapter (optional)

Not required. Spherical FXPAN is already XPan's 2.71:1 at 20.3°. A cylinder
on the **front** of the 180 is how you go wider without changing the chassis.
Rear M62 is already in the helicoid; `EL180_LENS_OD` is 76 mm and there is
no useful front filter thread, so everything clamps onto the barrel. Measure
that OD on your own 180 before you order a clamp.

Same Tuscany still as [`docs/kraken/fxpan_anamorph_scene.png`](../../docs/kraken/fxpan_anamorph_scene.png): 1.5× is 30.1° / 26.9 m / 4.07:1; 1.33× is 26.8° / 23.9 m; 2× is 39.5° / 35.9 m / 5.42:1.

**This build is 2× HD.** Compact Gold / Iscorama / SLR Magic below stay as
the unused families. **Do not keep** the red spherical taking lens, and do
not confuse this with ISCO Ultra-Star HD Plus **60 mm integrated** (stock
**748.50.06**) — that is a 60 mm f/2.1 projector lens, BFL 36 mm, 21.3 × 18.2
mm Scope gate, one barrel, does not unscrew into an adapter.

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 1 | **Schneider 1101111** — ISCORAMA 54 CU-1.5× (MFR **08-1101111**) | The stills pick. 1.5×, rear **M77×0.75** female, 1.4 m close focus, 1/4-20 support bracket in the box, M77/M72 SLIM already mounted. $4,950 new. Vintage **Iscorama 54** (ISCO-Göttingen, same 77 mm rear) is the used equivalent, usually cheaper, dual-focus. Schneider **1104267** M77/M62 is the *wrong* M62 — that is the 180's rear, already occupied. | [Duclos 08-1101111](https://www.ducloslenses.com/products/iscorama-54) · [Schneider IDs](https://schneiderkreuznach.com/en/cine-optics/lenses/isco-family) · used [Iscorama 54](https://www.ebay.com/sch/i.html?_nkw=iscorama+54) |
| 1 | **RafCamera custom: 76 mm ID clamp → M77×0.75 male** | So the Iscorama's female rear can screw onto the 180. Stock [76 mm → M77 female](https://rafcamera.com/clamp-76mm-to-m77x0-75f-od80mm) is a filter ring, wrong gender. Print a collar if you would rather. Measure first. | [RafCamera custom](https://rafcamera.com/custom-adapter) |

1.33× if you want new, light, and in-catalogue rather than the extra 9°:

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 1 | **SLR Magic SLRA65133X** — Anamorphot-65 1.33× | Rear **82 mm**, takes a 65 mm front element (the 180's pupil is 32 mm). B&H **SLMA13365A**. Anamorphot-40/50 are 52/62 mm rear and will not reach a 76 mm barrel. | [B&H SLRA65133X](https://www.bhphotovideo.com/c/product/1413511-REG/sigma_slra65133x_anamorphot_65_1_33x_anamorphic_adapter.html) |
| 1 | **RafCamera custom: 76 mm ID clamp → M82×0.75 male** | Same job as the M77 collar, one step up. | [RafCamera custom](https://rafcamera.com/custom-adapter) |

2× cinema (5.42:1). **Bought:** ISCO Ultra-Star **HD Cinemascope attachment**
(the large gold/orange cylinder). Unscrew the red **HD Plus** spherical
(`f=xx mm`, marked **1.85**) — threads are often glued; tap the joint, do
**not** undo the ring of six screws. Keep only the front piece. Caliper its
**rear tube** before you order the clamp: this unit is the US turret —
**70.6 mm** rear tube, **67 mm** rear thread OD (KuSeRa lists **~72 mm**
tube / **~68 mm** thread for other batches).

| Qty | Item | Why | Link |
|-----|------|-----|------|
| 1 | **ISCO Ultra-Star HD Cinemascope attachment** | Owned. 2× afocal, **70.6 mm** rear tube / **67 mm** rear thread (US turret). 180 mm pupil is 32 mm so coverage is the easy case. Theater focus (often 5–150 m) is fine at 50 m. | (bought) |
| 1 | **RafCamera 71 mm clamp → M77×0.75 male** | **This unit.** Clamp ID 70.65, made for Cinelux / US turret. | [71 mm / M77 M](https://rafcamera.com/clamp-71mm-to-m77x0-75m) |
| *or* 1 | **RafCamera custom: 72 mm clamp → M77×0.75 male** | Only if a different batch measures **72 mm** rear tube. | [custom](https://rafcamera.com/custom-adapter) |
| 1 | **RafCamera 76 mm clamp → M77×0.75 female** | On the 180. Measure `EL180_LENS_OD` first. Then: 180 → 76 mm clamp → M77 → attachment clamp. | [76 mm / M77 F](https://rafcamera.com/clamp-76mm-to-m77x0-75f-od80mm) |
| 1 | **1/4-20 support** (15 mm rod from the chassis, or a ~77–90 mm collar) | This one is a kilo. Hang it off the chassis **1/4-20**, not the M62 helicoid. Compact Iscorama brackets (**1101470** / **1103882**) will not fit the 90 mm front. | rail from the box 1/4-20 |

Compact Gold / Studio / Red (~52.5 mm rear) and Kowa 16-H / 8-Z are the
small 2× class. Not this build. Hang any adapter off the chassis **1/4-20**,
not the M62 helicoid — a kilo of glass on the printed boss is how it fails.

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
| ~1.5 spool | **PETG or ABS**, dark | Chassis, lid, tray, arms, stem, base, cradles. Not PLA — the M52 mouths and the cookie screws both see real load, and a 1 kg body hanging on a brittle mouth is how you break a D800. | [Amazon PETG](https://www.amazon.com/s?k=PETG+filament+1.75) |
| scraps | 4 accent colours | Only if you want the FXPAN badge in filament rather than paint: gold (FX), off-white (PAN), red (outline + stripe), grey (spec). A few grams each. | — |
| 12 | **M3 × 12 countersunk** (DIN 7991) + 12 **M3 nuts** | Port cookies, 4 per cookie into wall nut traps — two above the bore, two below. Three cookies: stem, arm R, arm T. Countersunk, not cap head: there is no wall outboard of a cookie any more, so its face is the outside of the camera and the D800 comes right up to it. | [M3 screws](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) · [M3 nuts](https://www.amazon.com/s?k=M3+hex+nuts) |
| 4 | **M3 × 20** + 4 **M3 nuts** | Lid to chassis, one per corner. Nuts drop into the corner pockets before the lid goes on. | as above |
| 8 | **M3 × 16–20** + 8 **M3 nuts** | Cradle to base, 4 per cradle. Heads sink into the plinth top, nuts sit under the base. | as above |
| 4 | **M3 × 6 grub screws** + 4 **M3 nuts** | Two per arm mouth, pinching the reverse-ring barrel. These hold your **roll alignment** — without them the ring can creep and one camera's horizon walks off the other's. The nuts sit in lugs *outboard* of the M52 thread rather than in pockets cut through it, and go in from the mouth end before the ring does; the ring's flange then closes over them. Headless, because the lug face is inside the space the D800's front panel occupies. | [M3 set screws](https://www.amazon.com/s?k=M3+set+screw+kit) |
| 2 | **1/4-20 heat-set insert, short 6.4 mm** | One in the chassis floor pad, one in the base tripod pad. Ø8.1 mm wells. Iron in **from the bed face** and leave the 1.2 mm keep so they stay blind. | [CNC Kitchen 1/4-20×6.4](https://cnckitchenus.store/products/heat-set-insert-1-4-20x6-4-camera-thread-short-version-20-pieces) · [Amazon](https://www.amazon.com/s?k=1/4-20+heat+set+insert) |
| 1 | **1/4-20 knurled thumbscrew** | Chassis onto the base origin pad, through the Ø24 mm counterbore. Hand-tight, no tool. | [1/4-20 camera thumbscrew](https://www.amazon.com/s?k=1%2F4-20+camera+thumbscrew+knurled) |
| 2 | **1/4-20 × 25 mm** | Up through the base slot and the cradle slot into each body's tripod socket. 18 mm of printed stack plus ~6 mm into the camera — **check the depth on your own bodies before you crank it down.** | [1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |
| 1 | **1/4-20 tripod screw** | Into the base insert at the combined centre of mass. Tripod goes there, **not** in the chassis. | as above |
| 1 sheet | **Flocking paper** or flat black paint | Chamber, tray faces, arm bores, and the F throats. The throats matter most: they are deliberately **unlined**. The throat is the tightest aperture in the body — 1.3 mm clear of the frame corners even at f/11 — so a 1.6 mm liner in there would vignette outright. | [camera flocking paper](https://www.amazon.com/s?k=camera+flocking+paper) |
| 2 | **TPU or cork pads**, ~1 mm | Optional, on the bare cradle tops so a body cannot creep on the plinth. Cut from sheet. | [cork sheet](https://www.amazon.com/s?k=2mm+cork+sheet+adhesive) |

## Print-only alternatives

Both of these work and both cost you something. Neither is the recommended
build.

| Part | Instead of | What it costs |
|------|-----------|---------------|
| `stem_el180_inf` | the M62 helicoid + short `stem` | One-piece cookie, 17.5 mm boss, 180 flange at infinity. **No focus travel.** Female M62 in the outer 8 mm. Same path as the helicoid at 17.5 mm, so it tracks `BOX_XY`. Print a second at +0.5 mm if the first lands long; shims can only add. |
| `m65_ring` | the flangeless M65→M62 ring, until it arrives. **EL-Nikkor only.** | Adds **8 mm**. Collapsed focus is about 4.5 m. Print `stem_m65` with it. |
| `stem_nw_m65` | the M62 Nikkor-W nose, on the M65 helicoid | Same Copal board, M65 male, **0 mm** added. Do not put the W on `m65_ring`. |
| `el180_adapter` | the M62 helicoid, keeping short `stem` | Two-piece stand-in: printed male into the 8 mm boss. Prefer `stem_el180_inf`. |
| `arm_r_f` / `arm_t_f` (`ARM_MOUNT = 1`) | the 52 mm reverse rings | Archive-663 male F. The lip is the mesh as shipped (40 mm). Plastic lugs still should not carry a D800 — the cradles take the weight. Dry-fit clocking with `F_MOUNT_CLOCK`. |
| `arm_r_focus` | `arm_r_fw`, and the R helicoid on the Nikkor-W | Same printed F and the same R cookie as `arm_r_fw`, including the W 8 mm, then 0.77 mm shorter so the bayonet is in focus when `arm_t_fw` is. Stamped `fxp_rw_focus`. |
| `arm_r_hw` / `arm_t_hw` | `arm_r_focus` / `arm_t_fw` and the shims | Nikkor-W. Needs the **M52-female / M42-male 17–31 helicoid** above and a **metal M52-to-F ring**, two of each. Cookie is the M42 female. The male's tip bottoms on a lip in the cookie; the body floats 0.4 mm off the face. On the measured 1.93 mm ring, collapsed is 25.68: R dials out 1.55 to focus, T 2.02. |

## Export

```
./export_fxpan.sh              # 35 STLs -> stls/fxpan/
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

- **S1 faces the lens** — the face with the black dot. Backwards puts the glass path on the
  reflect leg while the T arm's 0.303 mm compensation is still shortening the
  transmit leg — both legs then disagree by 0.6 mm and no shim stack fixes it
  cleanly.
- **Do not swap the arms.** T (+Y, straight back) is shorter than R (+X) by
  `bs_t_comp = 0.303 mm`. Flanges are engraved **▲ R** and **▲ T**. There is
  no tube toe on this body — each bore is translated 14.4 mm instead of tilted,
  so the arrow is for identification, not aiming.
- **The plinth carries, the bayonet locates.** A D800 is about 1 kg. Every
  printed F mount in this project is a weak point when it takes load; here it
  should never feel any. The cradles have no uprights — the bayonet fixes yaw
  far better than a 46 mm-wide flange could, and an upright would only stand
  in the way of bringing the body in and twisting it on.
- **This body's bore is not the others'.** `TUBE_ID` 46 and `F_BORE` 44.0
  against 52 and 40.3 elsewhere. Arms, stem and cookies are not
  interchangeable with `hybrid_shift` parts even where they look similar —
  which is why everything is stamped `fxp_`.
- **20.4° horizontal.** XPan's aspect ratio, not XPan's angle of view. 65 mm
  at 180 mm of focal length is a telephoto panorama. A 1.5× adapter on the
  front of the 180 takes that to 30.1° / 4.07:1 without touching the path.
- The two 50 mm first-surface mirrors are not used here. Keeping the stitch
  axis off every fold's foreshortened dimension forces all folds coplanar, and
  coplanar folds cannot make two bodies parallel. They stay with the V body.
