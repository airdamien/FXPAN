# Bill of materials — FXPAN, Nikkor-W

This is the camera as built. Two D800 bodies, upright, behind a Nikkor-W
180 mm f/5.6 in a Copal No. 1. Focus is the M65 helicoid on the lens, not a
helicoid on each camera. The iPhone runs the app. The Pi Zero only fires
the shutters.

![Rig](docs/build/rig.jpg)

| | |
| --- | --- |
| Frame | 64.80 × 23.9 mm, 2.711:1, 13248 × 4912, 65.1 MP |
| Overlap | 20% |
| Taking lens | Nikkor-W 180/5.6, flange distance 178.8 mm on this stack |
| Plate | Edmund 50 × 75 × 1.0 mm, **75 across the fold** |
| Aperture | f/5.6 to f/22. The lens covers the stitch wide open. Extreme corners are fully lit from f/8.4; at f/5.6 they still pass most of the light |
| Viewfinder | iPhone, FXPAN app |
| Release | 10-pin, both bodies together, then the frames come off USB from camera RAM |

Drawings and the measured arm lengths: [openscad/fxpan/README.md](openscad/fxpan/README.md).
Why the plate is this rectangle: [openscad/fxpan/PLAN.md](openscad/fxpan/PLAN.md).
Export: `./export_fxpan.sh`.

Earlier bodies, including the EL-Nikkor D7000 kits, are in
[archive/](archive/EARLIER.md).

## Optics

| Qty | Item | Why |
| --- | --- | --- |
| 1 | **Nikkor-W 180 mm f/5.6**, Copal No. 1 | The taking lens. 5×7 coverage, so the 64.80 mm stitch is inside the circle. Rear thread is the Copal ring, not M62. Used, search `nikkor-w 180mm f/5.6`. |
| 1 | **Pixco M65×1 helicoid, 17–31 mm** | Focus. Male into `stem_m65`, `stem_nw_m65` into the front. Infinity is about 1 mm out from collapsed. [Pixco 17–31](https://www.amazon.com/Pixco-Adjustable-Focusing-Helicoid-Shooting/dp/B01N1GOL39). |
| 1 | **Edmund #37201**, stock 35-947. 50 × 75 × **1.0 mm** 50R/50T, S2 broadband AR | 75 mm goes **across the fold**. At 45° that presents 53.03 mm; the frame needs 44.39 mm at f/5.6. The black dot is S1 and faces the lens. Do not cut it. [Edmund #37201](https://www.edmundoptics.com/p/50-x-75mm-50-50rt-vis-plate-beamsplitter/37201/). |
| 0 | Edmund **#17536**, the 50 × 75 × **3 mm** plate | Same page, same price, wrong thickness. It will not enter the slot, and the tilt astigmatism needs f/16. Check the thickness on the box. |

The EL-Nikkor 180/5.6N and its M62 helicoid are a different stem
(`stem` + `stem_el180_inf`). They are not on this camera. Their parts stay
listed in [openscad/fxpan/bom.md](openscad/fxpan/bom.md).

## Cameras, phone, sync

| Qty | Item | Why |
| --- | --- | --- |
| 2 | **Nikon D800**, no lens | 36 × 23.9 mm, 46.5 mm register. Both sit upright. |
| 2 | **Memory card**, CF or SD, any size that the body accepts | A D800 with Slot empty release lock set will ignore the 10-pin when the slot is empty. USB capture still works with no card, because that command writes to camera RAM directly. The 10-pin does not. Put a card in each body. The app still downloads the new frame from RAM. |
| 1 | **iPhone** running FXPAN | Live view, exposure, the 10-pin release, and the stitch. The screen replaces the Pi touch display. Build and install from [ios/](ios/). |
| 1 | Printed phone tray | [openscad/phone/WATCH_ME.scad](openscad/phone/WATCH_ME.scad). `./export_stls.sh --phone` writes `stls/phone/`. The 17 Pro Max cradle is `pm17_cradle` + `pm17_shoe`, one M3×16 and a nut. |
| 1 | **USB hub** the phone can see both bodies through | One session per D800. The phone has to drop both sessions before the 10-pin will fire, then open them again to download. |
| 1 | **Raspberry Pi Zero W** | USB gadget at 10.55.0.1. The phone sends `FIRE` to port 2323. Setup: [pi0w/README.md](pi0w/README.md). |
| 1 | **FXPAN trigger board** on the Zero's header | Four 4N35 optocouplers, two 3.5 mm jacks. Parts and the PCBWay zip: [gpio_trigger/bom.md](gpio_trigger/bom.md). |
| 2 | **3.5 mm TRS male to Nikon 10-pin male** | One per body. 3-pole, not TRRS. [Keabroir](https://www.amazon.com/dp/B0CYHL1B7F). |

![The app](docs/build/ios.jpg)

The app's Drive screen is where Release is set. **Sync** closes USB, pulses
the board (100 ms focus, then 300 ms shutter), and downloads both frames
from camera RAM. **USB** fires over PTP and does not use the 10-pin.

## Print

`./export_fxpan.sh` writes `stls/fxpan/`. This build uses these parts.
PETG or ABS, not PLA. The mouths and the cookie screws carry the bodies.

| Part | Qty | On the bed |
| --- | --- | --- |
| `chassis` | 1 | floor down. The lens face is opened to an 83.7 mm circle so the M65 helicoid can sit on the cookie. |
| `lid` | 1 | outer face down. Two M3 holes at the +Y corners. Six blind M2.5 holes on top take the Zero's standoffs. |
| `fxp_tray` | 1 | floor down. |
| `stem_m65` | 1 | cookie on the bed, boss up. Thread start is clocked so the Copal controls come out on top. |
| `stem_nw_m65` | 1 | Copal board up, male down on a raft. |
| `arm_r_wl`, `arm_t_wl` | 1 each | cookie on the bed, printed F up. Fixed registers 23.00 mm (R) and 22.62 mm (T), so both bodies peak at the same helicoid setting. |
| `base` | 1 | flat. Tripod insert and screw heads from the bed. |
| `cradle_r`, `cradle_t` | 1 each | flat. |
| `baffle` | 2 sheets | flat. One arm's rings per sheet. |

Logo inlays are optional. They drop into the chassis pocket as separate
filaments: gold FX, off-white PAN, red outline and 65MP, grey spec line.
The file names are `chassis_logo_*` in `stls/fxpan/`.

## Hardware

| Qty | Item |
| --- | --- |
| 12 | M3×12 countersunk, and 12 M3 nuts. Four per cookie, into the wall traps. |
| 2 | M3×20, and 2 M3 nuts. Lid to the chassis, +Y corners. Nuts go in before the tray. |
| 8 | M3×16, and 8 M3 nuts. Four per cradle, heads in the plinth, nuts under the base. |
| 2 | 1/4-20 heat-set insert, 6.4 mm long. One in the base, one in the chassis floor. Iron them in from the bed face. [CNC Kitchen 1/4-20×6.4](https://cnckitchenus.store/products/heat-set-insert-1-4-20x6-4-camera-thread-short-version-20-pieces). |
| 1 | 1/4-20 knurled thumbscrew. Chassis onto the base. |
| 2 | 1/4-20 × 25 mm. Up through the base and the cradle into each body. Check the socket depth before you tighten. |
| 1 | 1/4-20 tripod screw, into the base insert. The tripod is not in the chassis. |
| 4 | M2.5 × 10 mm male-female standoffs. Zero to the lid, header tails toward the lid. |
| 1 | Flocking, or flat black paint, in the chamber, the tray, both bores, and both F throats. The throats are unlined on purpose. A liner there vignettes. |

`arm_r_wl` and `arm_t_wl` are printed F-mounts. The cradles carry the
weight. The bayonet only takes the twist.

## Assembly

![Lid off, plate in the tray.](docs/build/assembly-open.png)

![The same parts pulled apart.](docs/build/assembly-exploded.png)

1. Heat-set the 1/4-20 insert into the base, and the other into the chassis floor, both from the bed face.
2. Flock the chamber, the tray, both bores, and both F throats.
3. Push the baffle rings in from the camera mouth, `fxp_bf1` first. They are numbered. Do not shuffle them. Reprint the set if you change `FSTOP`.
4. Plate into the tray. **Black dot toward the lens. 75 mm horizontal, 50 mm up.** The other way round, the stitch crosses 35 mm of glass and clips until f/11. Press it straight down between the centring ribs. A scrap of 1.75 mm filament through each 2 mm hole on the cheeks keeps it from lifting.
5. M3 nuts into the two lid slots, then the tray. The tray closes the slots.
6. Cookies into their pockets. **▲ R** with the R mark on the chassis, **▲ T** with T. Four M3×12 countersunk each. The stem cookie is stamped `fxp_stem`.
7. Lid on with two M3×20. The trigger stack sits on top, jacks toward R. Zero underneath, board on the 2×20 header, four standoffs into the lid.
8. Chassis onto the base with the thumbscrew. Cradles on with four M3×16 each.
9. Bodies. Start each 1/4-20 × 25 through the slot and leave it loose. Bayonet the body, then tighten the screw where the body landed. Do not pull the body onto the mount with the screw.
10. Lens. M65 helicoid into `stem_m65` until the body sits on the cookie. `stem_nw_m65` into the helicoid. Copal controls on top.

Both bodies need a card before the first synced release.

## Alignment

Focus, then roll, then the overlap. The numbers below are from this rig,
not from the drawing.

**Focus.** Collapse the M65 helicoid. Open it until a distant edge peaks on
T. That is about a millimetre. Check R on the Focus screen at that same
setting. The arms were reprinted so the two peaks meet: T at 17.81 mm of
helicoid (cookie face to lens face) and R at 20.38 mm on the first prints,
so R's arm is 23.00 mm and T's is 22.62 mm. If a later print does not meet,
the difference in helicoid height is how far to move R's arm. Set
`W_LENS_FOCUS_T`, `W_LENS_FOCUS_R`, and `W_WL_PRINTED_R`, and reprint
`arm_r_wl`.

**Roll.** A level horizon on both. The seam is horizontal, so relative roll
is a wedge. `STEM_W_CLOCK` is 90°, which puts the Copal controls on top.
Body roll is the printed F clock. `F_MOUNT_CLOCK` if a body comes up on its
side.

**Field.** Shoot something with detail across the frame and stitch it. The
app's overlap starts at 20%. Match will find the real overlap. Far from 20%
means a cookie is in the wrong port.

The measured arm lengths and the reprint numbers are in the
[FXPAN README](openscad/fxpan/README.md#alignment).

## What the simulation says

![Fold](docs/kraken/fxpan_paths.png)

![Frames at f/5.6. The corners fall off. The long axis does not.](docs/kraken/fxpan_frames.png)

![Stitch at f/11](docs/kraken/fxpan_pano.png)

![Margins](docs/kraken/fxpan_margins.png)

![How wide a front anamorphic would make the same lens](docs/kraken/fxpan_anamorph_scene.png)

`python kraken/fxpan_paths.py` ray-traces the body and fails if the geometry
drifts from these pictures.

## Pictures from the camera

![Field](docs/build/field.jpg)

![The same field, printed, and a second stitch of the tree line](docs/build/prints.jpg)
