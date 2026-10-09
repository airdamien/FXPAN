# FXPAN 65

The camera as built is a **Nikkor-W 180/5.6** in a Copal No. 1, on `stem_m65`
plus the M65×1 helicoid and `stem_nw_m65`, with printed F-mounts on
`arm_r_wl` / `arm_t_wl`. The bodies bolt to the cradles. The bayonet only
takes the twist. Buy list and assembly order: [../../bom.md](../../bom.md).

Two D800 bodies sit behind a 50 × 75 × 1 mm 50/50 plate at 45°. Each sensor
takes one half of the field and the two frames stitch to

**64.80 × 23.9 mm · 2.711:1 · 13248 × 4912 · 65.1 MP**

XPan is 65 × 24 mm at 2.708:1, so the aspect is within 0.1%.

**Shot from f/5.6 to f/22.** The Nikkor-W covers the stitch wide open.
f/8.4 is the stop where a 44 mm mouth passes the last corner ray. At f/5.6
that corner still gets most of the pupil and the long axis gets all of it,
which is a mild shade, not a dark corner. The printed mouths are bored to
the same 44 mm. The plate is not what limits the frame.

Open [`WATCH_ME.scad`](WATCH_ME.scad) and read the console. It echoes the
optical budget, marks anything that clips, and tells you how many baffle
rings are worth printing at the aperture you picked. To check it, run
[`../../kraken/fxpan_paths.py`](../../kraken/fxpan_paths.py) — it ray traces
the body and exits non-zero if the geometry and the numbers stop agreeing.

| | |
| --- | --- |
| Plan view and the fold | [`fxpan_paths.png`](../../docs/kraken/fxpan_paths.png) |
| Body ghosts against the chassis face | [`fxpan_body_fit.png`](../../docs/fxpan_body_fit.png) |
| Each sensor's falloff at f/5.6 | [`fxpan_frames.png`](../../docs/kraken/fxpan_frames.png) |
| The stitch at f/11 | [`fxpan_pano.png`](../../docs/kraken/fxpan_pano.png) |
| What has to pass vs what is there | [`fxpan_margins.png`](../../docs/kraken/fxpan_margins.png) |

Shares no printed part with the earlier bodies. Everything is stamped
`fxp_*`. [`PLAN.md`](PLAN.md) has the derivations. [`bom.md`](bom.md) is the
longer parts list, including stems this camera does not use.

## Before you print

**Buy the 50 × 75 × 1.0 mm plate, and put the 75 across the fold.** A plate
at 45° presents only `size/√2` in its plane of incidence, and that is the
direction the 64.80 mm stitch has to cross: the frame needs 44.4 mm there at
f/5.6 and 75 mm gives 53.03. Along the fold there is no foreshortening and
nothing to carry but the 23.9 mm sensor height, so 50 mm is already plenty,
and that is the direction that sets chassis height. Fitted the other way
round the stitch crosses 35.36 mm and clips the long axis of the panorama.
The tray slot is keyed. The black dot (S1) faces the lens.

**The arms are printed F, at the registers this rig measured.** `arm_r_wl`
is 23.00 mm, `arm_t_wl` is 22.62 mm, so both bodies peak at the same setting
of the lens helicoid, about 1 mm out from collapsed. The cradles carry the
weight. Reprint `arm_r_wl` if a later pair does not meet; the alignment
section has the three numbers that move.

**The body's front panel has to clear the tube when you twist it on.** Lay a
straight edge across the D800's front and measure back to the bayonet
register. The default `D800_PROUD` is 13 mm. These arms clear by 3.12 mm (T)
and 3.50 mm (R). If a different body measures past that, change
`D800_PROUD` and reprint. The console says when the chassis can no longer
reach infinity.

## Print list

```
./export_fxpan.sh
```

STLs land in `stls/fxpan/`. This camera uses the rows below. PETG or ABS,
not PLA. The mouths and the cookie screws carry the bodies.

**Print `full`, one material.** Flock the chamber. The arms and the stem
should come off the same spool: the two legs have to agree to a fraction of
a millimetre.

| part | quantity | bed orientation |
| --- | --- | --- |
| `chassis` | 1 | floor down. The lens face is relieved to an 83.7 mm circle so the M65 helicoid seats on the cookie. On the logo side a 3 mm post rises from the logo window's sill to 6 mm over the floor, so the tray cannot slide into the window |
| `lid` | 1 | outer face down. Two screw holes, at the +Y corners, match the chassis. Six 2.2 mm blind holes, 5 deep, take the trigger stack's M2.5 standoffs |
| `fxp_tray` | 1 | floor down |
| `stem_m65` | 1 | cookie flange on the bed, boss up. Thread start turned 90° counter-clockwise facing the cookie (`STEM_W_CLOCK`), so the bottomed Nikkor-W has its shutter controls on top |
| `stem_nw_m65` | 1 | Copal board up, male down on a raft |
| `arm_r_wl`, `arm_t_wl` | 1 each | cookie flange on the bed, printed F up. Fixed registers 23.00 (R) and 22.62 (T). No camera helicoids |
| `base` | 1 | flat. Tripod insert and screw heads enter from the bed. 176 × 190 mm. Each camera slot runs along that camera's lens axis |
| `cradle_r`, `cradle_t` | 1 each | flat. 12 mm tall so the body sits on the plinth before the tripod screw is tightened |
| `baffle` | 2 sheets | flat. One arm's rings per sheet, four rings at the f/11 default |

Colour inlays, if you want the badge in filament rather than paint:

| STL | suggested |
| --- | --- |
| `chassis_logo_fx` | gold |
| `chassis_logo_word` | off-white |
| `chassis_logo_outline` | red |
| `chassis_logo_mp` | red (65MP) |
| `chassis_logo_rule` | any accent |
| `chassis_logo_spec` | grey (`NATIVE  13248×4912 · 2.71:1`) |
| `chassis_logo_ana_mp` | gold or a second red (130MP) |
| `chassis_logo_ana_rule` | any accent |
| `chassis_logo_ana` | grey or gold |
| `chassis_logo_stripe` | Nikon pro red |

The plugs overrun the pocket — 0.08 mm into the walls and floor, 0.06 mm
proud of the face — so the slicer resolves each colour. `chassis_logo` is
the lot merged if you would rather paint one part. The stripe is a 1.6 mm
groove 5 mm up from the floor.

**The cookies go down flat.** R6 corners, a 1.2 mm chamfer on the outer
edge, and the outer face clipped to the chassis profile, all of that on the
top. The bed face is the full flat plate. No supports. Each cookie is a
rectangle centred on its bore: **77.8 × 62 for an arm, 77.8 × 74 for the
stem**.

## Assembly

1. **Inserts.** Press a 1/4-20 insert into the `base` tripod pad from the
   underside, and one into the chassis floor pad.
2. **Flock** the chamber, the tray's inner faces, both arm bores, and both
   printed F throats. The tray's ribs and the arms' baffle ribs do most of
   the work. The throat has no liner on purpose; a liner there vignettes.
3. **Baffle rings**, if you printed them. One set per arm, pushed down the
   bore from the camera mouth: `fxp_bf1` first and deepest. Each ring is
   sized to its station, so they must not be shuffled. Four at the f/11
   default, five at f/16, none at f/5.6. Reprint the set if you change
   `FSTOP`.
4. **Plate into the tray.** The black dot faces the lens. The plate is
   **75 mm across, 50 mm up**. The slot is keyed for both. Two 2 mm holes on
   the cheeks take a scrap of 1.75 mm filament so the plate cannot lift.

   **Centring ribs.** Opposite ribs leave 1.10 mm for the 1.0 mm glass, so
   it sits on the slot centre. Off-centre glass moves R's focus and rolls
   the reflected image. Press it straight down. If it will not go, scrape
   the same amount off each rib.

5. **Lid nuts, then the tray.** Push an M3 nut into each of the two slots
   under the rim in the +Y corners, until it stops on the screw axis. Then
   the tray goes in, floor down, and its wall closes both slots. The
   retention posts go up into the lid.
6. **Cookies into their rebates.** Four M3 × 12 countersunk per cookie. The
   screws are the only thing holding a cookie in. The arm cookies read
   **▲ R FXP** and **▲ T FXP**; the chassis carries the same mark beside
   each pocket. The stem cookie is stamped `fxp_stem`.
7. **Lid** with two M3 × 20 into the +Y corner nuts. Edges flush with the
   chassis. The trigger stack goes on top, jacks toward R. Bottom up it is
   the Zero W with its header in from underneath, then the trigger board on
   the header. Four 10 mm M2.5 male-female standoffs into the inner four
   blind holes.
8. **Base.** Chassis onto the origin pad with a 1/4-20 thumbscrew. Each
   cradle gets four M3 × 16, heads in the plinth, nuts under the base.
9. **Bodies.** Start the 1/4-20 × 25 up through the slot and leave it loose.
   Bayonet the body onto the printed F, then tighten the screw where the
   body landed. Do not pull the body onto the mount with the screw. The
   plinth takes the weight. The bayonet takes the twist.
10. **Lens.** M65 helicoid into `stem_m65` until its body sits on the cookie.
    `stem_nw_m65` into the front. The helicoid body is 82.67 mm across, wider
    than the cookie's 80 mm rebate, which is why the chassis face is opened
    to 83.7 mm. Copal controls on top. Both bodies need a card before a
    synced release.

Before the bodies go on, check `D800_AXIS_BASE` (lens axis above the
baseplate, default 52.0 mm) and `D800_TRIPOD_IN` (along the base, default
44 mm) against your own cameras, then reprint `base` and the cradles if
they differ. The chassis skirt is solved from `D800_AXIS_BASE`. If it is
wrong, both cameras sit off the optical axis by the same amount.

## Alignment

Focus, then roll, then the overlap. These numbers are from this rig.

**Focus.** The field test with the lens seated straight in `stem_m65` put R's
camera-side focus at the end of its travel and T past it, so focus moved to
the M65 on the lens and the arms were shortened to meet it. The lens helicoid
lifts the lens 16.58 mm. T's arm is 22.62 mm. On the first prints the lens
helicoid (cookie face to lens face) peaked T at 17.81 and R at 20.38, so R
was reprinted 2.57 mm longer, at 23.00, and both peak together.

1. Collapse the helicoid, then open it until a distant target peaks on T.
   That is about a millimetre.
2. Check R on the Focus screen at the same setting.
3. If R peaks somewhere else, the difference in helicoid height is how far
   R's arm moves. Set `W_LENS_FOCUS_T` and `W_LENS_FOCUS_R` to the two
   heights, `W_WL_PRINTED_R` to the R arm you measured, and reprint
   `arm_r_wl`.

**Roll.** Shoot a level horizon on both. The seam is horizontal, so relative
roll is a wedge. `STEM_W_CLOCK` is 90°, which puts the Copal controls on
top. Body roll is the printed F. Set `F_MOUNT_CLOCK` and reprint that arm
if a body comes up on its side.

**Field.** Shoot something with detail across the frame and stitch it on the
phone. Overlap starts at 20%. Far from that means a cookie is in the wrong
port.

## Apertures

Stopping down shrinks the bundle, so the body does not start vignetting
again on the way to f/22. The corners are the place to read it: a
36 × 23.9 mm window's corner sits 21.6 mm from centre.

| f-stop | plate across the fold (53.03) | plate along it (50) | 44 mm bore | traced corner |
| --- | --- | --- | --- | --- |
| 5.6 | 44.4 mm · +19.5% | 29.1 mm · +72% | 46.8 mm · clips | 0.836 |
| 8 | 38.4 mm · +38.2% | 23.0 mm · +117% | 44.3 mm · clips | 0.951 |
| 11 | 34.5 mm · +53.6% | 19.2 mm · +161% | 42.7 mm · clears | 1.000 |
| 16 | 31.3 mm · +69.3% | 16.0 mm · +213% | 41.4 mm · clears | 1.000 |

The plate is never the constraint. The long axis of the panorama is clean at
every stop, including f/5.6. Only the corners shade, and they clear as the
lens stops down. The along-the-fold column is why the plate is 50 mm there
and not 75: that margin was never going to be spent, and buying it cost
25 mm of chassis height.

Set `FSTOP` in the customizer to see any aperture. Falloff maps:
[`fxpan_frames.png`](../../docs/kraken/fxpan_frames.png) and
[`fxpan_margins.png`](../../docs/kraken/fxpan_margins.png).

## What this body is not

It is a **20.4° horizontal** field. 65 mm of frame at 180 mm compresses
distant landscape. The aspect matches XPan. The angle of view does not.
Going wider means a shorter lens, and the path has to equal the focal
length, so that is a new body.

The two 50 mm first-surface mirrors are not used here. Coplanar folds cannot
make the two bodies parallel. They stay with the V body.

## Other parts the model still exports

`./export_fxpan.sh` also writes the earlier stems and mouths. They are not
on this camera. The longer list is [bom.md](bom.md). The derivations are in
[PLAN.md](PLAN.md).

| part | what it was |
| --- | --- |
| `stem`, `stem_el180_inf`, `el180_adapter`, `m65_ring` | EL-Nikkor 180/5.6N on an M62 helicoid. A different lens and a different flange. |
| `arm_r`, `arm_t` | M52 × 0.75 female for a metal 52 mm F reverse ring. `ringgauge` fits that thread. |
| `arm_r_f`, `arm_t_f`, `arm_r_fw`, `arm_t_fw`, `arm_r_focus` | Earlier printed-F lengths, before the measured `wl` registers. |
| `arm_r_hw`, `arm_t_hw` | Bought M52-female / M42-male camera helicoids and a metal F ring, if focus is on the cameras instead of the lens. |
| `stem_nw_direct` | Nikkor-W straight into `stem_m65`, no lens helicoid. The male is 0.8 mm fatter so it threads snug. This is the nose the field test was shot on, before focus moved to the M65. |
| `shims` | 0.2 / 0.5 / 1.0 mm, for a reverse-ring mouth. The `wl` arms are fixed; a miss there is a reprinted `arm_r_wl`. |
