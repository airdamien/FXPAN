# FXPAN 65

A clean-sheet FX panoramic body: two D800 bodies behind one EL-Nikkor 180/5.6N
and a 50 × 75 × 1 mm 50/50 plate beamsplitter at 45°. Each sensor takes one
half of the field and the two frames stitch to

**64.80 × 23.9 mm · 2.711:1 · 13248 × 4912 · 65.1 MP**

XPan is 65 × 24 mm at 2.708:1, so the aspect is within 0.1%. The name finally
means something: 65 mm of frame and 65 megapixels.

**Working aperture is f/8 to f/22, and the frame is corner-to-corner clean
from f/8.4.** At f/5.6 the four corners lose light — 0.84 of full — while the
panorama's long axis stays perfectly clean, so it reads as corner shading
rather than a broken stitch. The cause is the 44 mm Nikon F throat, which is a
hard physical ceiling: an unshifted D800 needs 40.35 mm there at f/5.6, so the
14.4 mm shift spends almost all the margin the mount ever had. Since a
180 mm enlarger lens is at its best around f/8–f/11 anyway, this is a cheap
limit to live with.

Open [`WATCH_ME.scad`](WATCH_ME.scad) and read the console. It echoes the
whole optical budget with margins, marks anything that clips, and tells you
how many baffle rings are worth printing at the aperture you picked. To check
it rather than trust it, run [`../../kraken/fxpan_paths.py`](../../kraken/fxpan_paths.py) —
it ray traces the body and exits non-zero if the geometry and the numbers stop
agreeing.

| | |
| --- | --- |
| Plan view and the fold | [`fxpan_paths.png`](../../docs/kraken/fxpan_paths.png) |
| Body ghosts against the chassis face | [`fxpan_body_fit.png`](../../docs/fxpan_body_fit.png) |
| Each sensor's falloff at f/5.6 | [`fxpan_frames.png`](../../docs/kraken/fxpan_frames.png) |
| The stitch at f/11 | [`fxpan_pano.png`](../../docs/kraken/fxpan_pano.png) |
| What has to pass vs what is there | [`fxpan_margins.png`](../../docs/kraken/fxpan_margins.png) |

Shares no printed part with the other bodies: the bore here is 46 mm with a
44 mm mouth against their 52 / 40.3, because a 14.4 mm sensor shift clips a
40.3 mm bore badly. Everything is stamped `fxp_*`. [`PLAN.md`](PLAN.md) has the
derivations and the numbers you must not move; [`bom.md`](bom.md) is the
shopping list.

## Four things to get right before you build

**Print `ringgauge` first.** It is four M52 × 0.75 rings at stepped clearances,
ten minutes on the bed, and it settles the one fit this body cannot recover
from later. Thread a Fotodiox reverse ring into each, keep the tightest that
still runs down by hand without rocking, and put its number into
`F_REV_CLEAR`. Details under [M52 mouth](#the-m52-mouth) below.

**Measure how far your body's front stands past its flange.** Lay a straight
edge across the D800's front panel and measure back to the bayonet's register
face. The default `D800_PROUD` is 13 mm. That one number sets the arm tube
length and therefore the whole chassis, because the F register has to stand
off the chassis face by at least that much or the body cannot be twisted on —
and the body is wider than the chassis, so there is nowhere to relieve
locally. As shipped the standoff is 16 mm, 3 mm of slack. If yours measures
more than 16, change `D800_PROUD` and reprint; the console will tell you if
the chassis can no longer reach infinity.

**Buy the metal reverse rings if you want the last 0.5 mm.** They keep the real 44 mm F throat (clean from f/8.4). The printed Archive-663 bayonet on `arm_r_f` / `arm_t_f` is 43.5 mm after a through-bore, clean from f/9.2. `ARM_MOUNT = 0` is still the default. Plastic lugs locate; the cradles carry the bodies.

**Buy the 50 × 75 plate, and put the 75 across the fold.** A plate at 45°
presents only `size/√2` in its plane of incidence, and that is the direction
the 64.80 mm stitch has to cross: the frame needs 44.4 mm there at f/5.6 and
75 mm gives 53.03, 19.5% of margin that grows as you stop down. Along the
fold there is no foreshortening and nothing to carry but the 23.9 mm sensor
height, so 50 mm is already +72% — and that is the direction that sets chassis
height, which is why the plate is not square. Fitted the other way round the
stitch crosses 35.36 mm, clips until f/11, and clips *the long axis of the
panorama* rather than its corners. The tray slot is keyed, but nothing stops
you rotating a plate 90° in your hand before it goes in.

## Print list

```
./export_fxpan.sh
```

35 STLs into `stls/fxpan/`, each stamped with the render minute.

**Print `full`, one material.** The `_inner` / `_outer` PETG-lining split is
carried over from `hybrid_shift` and still works, but on a body this small it
buys little light-tightness for two extra failure modes. Flock the chamber
instead.

| part | quantity | bed orientation |
| --- | --- | --- |
| `ringgauge` | 1, before anything else | flat |
| `chassis` | 1 | floor down. The lens face is relieved to an 83.7 mm circle so the M65 lens helicoid seats on the cookie. On the logo side a 3 mm post rises from the logo window's sill to 6 mm over the floor, where the wall would be, so the tray cannot slide into the window |
| `lid` | 1 | outer face down. Two screw holes, at the +Y corners, to match the chassis |
| `display_mount` | 1 pair | rails on their flat face |
| `fxp_tray` | 1 | floor down |
| `stem` | 1 (with an M62 helicoid) | cookie flange on the bed, boss up |
| `stem_m65` | 1 (with the M65 helicoid) | cookie flange on the bed, boss up. Thread start turned 90° counter-clockwise facing the cookie (`STEM_W_CLOCK`), so the bottomed Nikkor-W has its shutter controls on top |
| `m65_ring` | 1, until the flangeless metal ring arrives. EL-Nikkor only | lens seat up, male down on a raft |
| `stem_nw_m65` | 1, Nikkor-W on the M65 helicoid | Copal board up, male down on a raft |
| `stem_nw_direct` | 1, Nikkor-W straight into `stem_m65`, no lens helicoid | Copal board up, male down on a raft. The male is 0.8 mm fatter (`NW_DIRECT_GROW`) so it threads snug into the printed female; focus on the camera helicoids |
| `stem_el180_inf` | 1 until the helicoid arrives | cookie flange on the bed, M62 boss up |
| `arm_r`, `arm_t` | 1 each | cookie flange on the bed, camera mouth up |
| `arm_r_focus` | 1, Nikkor-W, instead of `arm_r_fw` or the R helicoid | cookie flange on the bed, F bayonet up. Stamped `fxp_rw_focus`. The W 8 mm is in the tube, then the register is 0.77 mm closer than `arm_r_fw`, so it focuses with `arm_t_fw` |
| `arm_r_wl`, `arm_t_wl` | 1 each, Nikkor-W focusing on its M65 lens helicoid with `stem_nw_m65` | cookie flange on the bed, printed F up. Fixed registers 23.00 (R) and 22.62 (T), so both peak at the same lens helicoid setting, about 1 mm into its travel. No camera helicoids; the bodies bolt to the cradles 3.0 (R) and 2.6 (T) mm past the slot's EL mark |
| `arm_r_hw`, `arm_t_hw` | 1 each, Nikkor-W on the camera helicoids | cookie flange on the bed. Flat face with an M42 female for the bought helicoid; a metal F ring goes in its front |
| `base` | 1 | flat; tripod insert and screw heads enter from the bed. 176 × 190 mm. Each camera slot runs along that camera's lens axis, 24 mm long, from 2 mm inside the EL register to 22 mm past it, so a camera helicoid has its whole travel |
| `cradle_r`, `cradle_t` | 1 each | flat, either way up. 12 mm tall (`CRADLE_EXTRA` 2 mm over the chassis solve) so the body sits on it before the tripod screw is tightened; the same M3s still reach |
| `baffle` | 2 sheets — one arm's worth per sheet (4 rings at the f/11 default) | flat |
| `shims` | 1 sheet of 3 | flat |
| `el180_adapter` | only if the helicoid has not arrived | male thread down |

Colour inlays, if you want the badge in filament rather than paint — drop each
into the chassis as a separate part and give it its own material:

| STL | suggested |
| --- | --- |
| `chassis_logo_fx` | gold (FX monogram + sweep, from `logos/fxpan_fx_gold.stl`) |
| `chassis_logo_word` | off-white (`logos/fxpan_pan_white.stl`) |
| `chassis_logo_outline` | red (`logos/fxpan_outline_red.stl`) |
| `chassis_logo_mp` | red (65MP) |
| `chassis_logo_rule` | any accent (hairline under 65MP) |
| `chassis_logo_spec` | grey (`NATIVE  13248×4912 · 2.71:1`) |
| `chassis_logo_ana_mp` | gold or a second red (130MP) |
| `chassis_logo_ana_rule` | any accent (hairline under 130MP) |
| `chassis_logo_ana` | grey or gold (`ANA 2×  26496×4912 · 5.42:1`) |
| `chassis_logo_stripe` | Nikon pro red (the D3/D4/D5 line around the plinth) |

The chassis pocket always contains every layer. The plugs deliberately overrun
it — 0.08 mm into the walls and floor, 0.06 mm proud of the face — so no
surface is coplanar with the chassis and the slicer resolves each colour
instead of speckling the pocket. `chassis_logo` is the lot merged if you
would rather paint one part. The stripe is a 1.6 mm groove 5 mm up from the
floor, around all four walls and the R9 corners; load `chassis_logo_stripe`
on the chassis as red, or fill the pocket with paint.

Print the arms and the stem in the same material and from the same spool if
you can: the two camera legs have to agree to a fraction of a millimetre, and
a filament change between them is an easy way to lose that.

**The cookies are meant to go down flat and stay there.** A cookie's face is
the outside of the camera, not a patch behind a wall, so it is drawn to
disappear into the chassis: R6 corners, a 1.2 mm chamfer round the outer edge
to read as a shadow line, and the outer face clipped to the chassis's own R9
plan profile where it curves away underneath. All of that is on the *top*.
The bed face is the full flat plate, every one of those features only narrows
the part going up, and the arm's mouth lugs flare down onto the plate instead
of overhanging it. No supports, no brim under the tube.

They are also no bigger than they have to be. Each one is a rectangle centred
on its bore — **77.8 × 62 for an arm, 77.8 × 74 for the stem** — sized off the
clamp screws one way and the tube or a lock lug the other, which is 36.6% less
plate and print time than the 90 mm squares they replace.

## Assembly

1. **Inserts.** Press the 1/4-20 threaded insert into the `base` tripod pad
   from the underside, and one into the chassis floor pad.
2. **Flock** the chamber, the tray's inner faces, both arm bores and the F
   throats. The tray's sawtooth ribs and the arms' integral baffle ribs do most
   of the work, but the F throat has no liner on purpose (see `PLAN.md`) and
   needs the flocking.
3. **Baffle rings**, if you printed them. One set per arm, pushed down the bore
   from the camera mouth in numbered order: `fxp_bf1` first and deepest. Each
   ring is sized to its own station so none of them shadows the bundle at
   `FSTOP`, which is why they are numbered and **must not be shuffled** — the
   apertures grow from bf1 outward. The count depends on the aperture: four at
   the f/11 default, five at f/16, and none at f/5.6, where the bundle already
   fills the bore and `baffle.stl` comes out empty. **If you change `FSTOP`,
   reprint them** — a set cut for f/16 vignettes at f/11.
4. **Plate into the tray.** Two things to get right and both are easy to get
   wrong. S1 — the 50/50 coated face, the one Edmund marks with a **black
   dot** — goes **toward the lens**; backwards puts the glass path on the
   reflect leg instead of the transmit leg and the T arm's 0.303 mm
   compensation then works against you. And the plate is **75 mm across,
   50 mm up**: that way round the stitch crosses 53 mm of glass, the other way
   it crosses 35 and clips. The slot is keyed for both; the plate drops in
   from the top and sits on the shelf. Two **2 mm holes** on the top of the
   plate frame, one on each cheek and inboard of the glass ends, take
   **1.75 mm filament**. Each bore drops in and then crosses the slot just
   above the glass. Lid off, push a scrap into each hole so the plate cannot
   lift out of the slot.

   **Centring ribs.** Each cheek has a rib at each end of the slot, outside
   the beam window, full height, tapered at the top. Opposite ribs leave
   1.10 mm for the 1.0 mm glass, so it sits on the slot centre, where the R
   arm is cut for it, and cannot lean. Off-centre glass moves R's focus
   about 0.4 mm and rolls the reflected image. Press the glass straight
   down; it should go in with a firm push. If it will not, scrape the ribs
   with a blade, the same amount off each side, so the glass stays centred.

5. **Lid nuts, then the tray.** First push an **M3 nut** flat into each of
   the two slots 12 mm under the rim in the +Y corners of the chamber, one in the +X wall
   and one in the −X end of the +Y wall, until it stops on the screw axis.
   The slot fits the nut's flats, so it cannot turn. Then the **tray** goes
   in, floor down, and its wall closes both slots. One retention post stands on the
   plate frame in the dead corner between the cameras; the other stands on
   the inactive beam under the −X wall, so the lid forks are not in the cup
   walls and not on the monitor-rail screws. Both go up through the lid.
6. **Cookies into their rebates.** Each of the three port cookies drops
   straight into a blind pocket in its face, closed all the way round, and
   stops against the chamber wall behind it. **Four M3 × 12 countersunk** per
   cookie into the nut pockets — two above the bore and two below. There is no
   wall outboard of the cookie, and the heads sit flush with its face, because
   that face is the outside of the camera and the D800 has to come right up to
   it. The screws are the only thing holding a cookie in, so do all four. The
   two arm cookies read **▲ R FXP** and **▲ T FXP** along their lower edge;
   the chassis wall carries the same mark beside each pocket, so put each
   cookie where its letter matches. The stem cookie is the odd one out and is
   stamped `fxp_stem`.
7. **Reverse rings.** Drop an **M3 nut** into each of the two lugs on the arm
   mouth first — they go in from the mouth end, down a slot, and the ring's
   flange closes over them once it is on, so there is no doing this later.
   Then thread the ring in; this is the fit `ringgauge` was for. Each mouth
   has an engraved radial line at the body lock-pin azimuth; clock the ring to
   it, then run the two **M3 × 6 grub screws** down onto the barrel. The grubs,
   not the thread, are what actually hold clock and roll — and once a body is
   on you cannot reach them, so finish this before step 10.
8. **Lid** with two M3 × 20 into the +Y corner nuts. The other corners are
   cookie rebate at nut height, so the −Y edge is held by the lid lip. It sits on an unbroken rim
   and its edges should be flush with the chassis on all four sides — the
   cookie pockets are blind and do not break the top. Check the forks have
   captured the tray posts before you tighten. Six M3 holes with nut traps
   under the lid take the `display_mount` rails (same easel as the other
   bodies).
9. **Base.** Chassis onto the origin pad with a 1/4-20 thumbscrew. Bolt each
   cradle to its camera pad with four M3 × 16, heads sunk into the plinth top
   and nuts under the base. The cradles are bare plinths — nothing stands up
   off them, so nothing is in the way of the next step.
10. **Bodies.** Start the 1/4-20 × 25 up through the base slot and the cradle
    slot but leave it loose, so the body can still slide along the axis.
    Bring the body in until the bayonet meets the reverse ring, twist to lock,
    then tighten the 1/4-20 where it sits. Don't drive the body toward the
    mount with the screw — the slot is there so the screw follows the bayonet
    rather than fighting it. **The plinth takes the weight, the bayonet takes
    the twist.**
11. **Lens.** M62 helicoid into the stem's 8 mm female boss, EL-Nikkor 180 into
    the helicoid. Collapsed is infinity.

Before step 10, measure your own bodies and set `D800_AXIS_BASE` (lens axis
above the camera's baseplate, default 52.0 mm) and `D800_TRIPOD_IN` (lens axis
to tripod socket along the base, default 44 mm) in the customizer, then
reprint `base` and the cradles. The defaults are reported figures, not
measured ones. `D800_AXIS_BASE` is the one that matters: the chassis skirt is
solved from it, so if it is wrong both cameras sit off the optical axis by the
same amount and neither leg will focus where the other does.

## Alignment

The two legs have to agree in focus, in roll, and in where their half of the
field starts. In that order.

**Focus.** Collapse the helicoid and shoot a distant hard edge on the T camera.
`PATH` at the collapsed end is 179.5 mm, 0.5 mm short of the 180 mm the lens
wants, so infinity is just inside the travel — rack out until it snaps in and
note the setting. Now shoot the same target on R. If R focuses at a different
helicoid setting, the two legs disagree: add shims between the arm mouth and
the reverse ring on whichever leg focuses *long*. The set gives 0.2 / 0.5 /
1.0 mm and they stack.

Both legs should agree within one 0.2 mm shim. The transmit leg is already
0.303 mm shorter to pay for the glass path, so if T comes out long by roughly
that much, check that S1 really is facing the lens.

**Lens helicoid (Nikkor-W).** `arm_r_wl` / `arm_t_wl` put focus back on the
lens. The field test with `stem_nw_direct` focused R with its camera
helicoid body at 29.18 mm, 12.50 past the 16.68 collapsed. T read 2.19 mm
longer than R on the same caliper, so 31.37, at the end of its travel. The
M65 lens helicoid lifts the lens 16.58 mm, so the arms come in by that plus
1 mm of margin: T 22.62. On the first prints the lens helicoid (cookie face
to lens face) peaked T at 17.81 and R at 20.38, with R at 20.43, so R
reprints 2.57 longer at 23.00 and both peak together. The D800 front panel
clears by 3.12 (T) and 3.50 (R).

1. Screw the M65 helicoid into `stem_m65` until its body sits on the cookie
   face. Screw `stem_nw_m65` into its front. The body is 82.67 mm across,
   wider than the cookie's 80 mm rebate, so the chassis face is relieved to
   an 83.7 mm circle round the lens bore, 0.3 mm under the cookie face
   (`M65_HELI_OD`). On an older chassis, open the rim to that circle; it is
   about 1 mm at the middle of each side, 2.3 mm deep.
2. Collapse the helicoid fully, then open it until a distant target peaks on
   T. That is about a millimetre.
3. Check R on the Focus screen's sharpness match at the same setting. The
   bodies are bayoneted to fixed arms, so the cradles only carry weight;
   tighten both tripod screws wherever the bodies land. If R peaks at a
   different lens setting, the difference in helicoid height is how far R's
   arm moves: set `W_LENS_FOCUS_T` / `W_LENS_FOCUS_R` to the two heights
   and `W_WL_PRINTED_R` to the R arm you measured on, and reprint `arm_r_wl`.

**Camera helicoids (Nikkor-W).** `arm_r_hw` / `arm_t_hw` replace the fixed
arms and the shims. Each takes a bought M52-female / M42-male 17–31 helicoid
(body 69 mm, 16.68 mm collapsed past a 4.67 mm male) and a metal F ring in
its front. The body is wider than the cookie and overhangs the chassis skin,
so it does not seat on either: the male's tip stops on a lip at the foot of
the cookie thread, and the body face stands 0.4 mm clear.

1. Screw the helicoid's M42 male into the cookie until its tip stops on the
   lip. Screw the metal F ring into the helicoid front until it bottoms.
2. Collapsed, the register is 25.51 mm off the cookie back on the 1.93 mm
   ring (`CAM_F_RING`). The fixed arms found best focus at 27.23 (R) and
   27.70 (T), so R extends about 1.7 mm and T about 2.2 mm. The cradle slot lets
   the body follow; the tripod screw is the lock.
3. Focus the lens on T. Then turn only R's helicoid until R peaks on the
   Focus screen's sharpness match, and tighten R's tripod screw.

**Roll.** Both threads bottom where their helicoid's thread starts, the
same place every time. If a body comes out rolled, set `CAM_HELI_CLOCK_R`
or `CAM_HELI_CLOCK_T` to the measured roll in degrees and reprint that
cookie: it turns the cookie's thread start, so the bottomed body stops that
much further round. If the next shot doubles the roll, flip the sign.

**Roll.** Shoot a level horizon on both. Both bodies sit upright and landscape,
and the seam is horizontal, so any relative roll shows up as a wedge in the
overlap that no stitcher will hide. Loosen the reverse ring grubs, rotate,
re-lock — with the body off, since the grubs sit inside the space its front
panel occupies.

**Field.** Shoot a scene with detail across the whole frame and run it through
`cam/pano.py`, whose default overlap is **0.20** for this body. `find_overlap()`
measures the real overlap and auto-detects which body needs flipping — the R
leg takes one reflection and T takes none, so exactly one frame is mirrored and
you do not have to care which one is image-left. What you are checking is that
the measured overlap lands near 20%; far off means a cookie is in the wrong
port or a bore is shifted the wrong way.

## The M52 mouth

The reverse-ring mouths on the earlier bodies never took a ring properly —
they felt too loose to start and would not run down. That was a profile
problem, not a clearance problem, and it is fixed here.

`lib/threads.scad` cuts a **sharp, full-height V** unless you tell it not to.
At a 0.75 mm pitch that is 0.650 mm of radial depth, where a real M52 × 0.75
female is 0.406 mm. The printed crests therefore stood about a quarter of a
millimetre proud, reaching into the ring's thread roots. The ring rode on
those crests instead of on its flanks, which is line contact on a knife edge:
it rocks, it starts crooked, and it feels exactly like a bore that is too big.

`F_REV_TOOTH` truncates the crest back to the real minor diameter and the
clearance moves onto the major, where it belongs. There is also a 0.9 mm 45°
lead-in at the mouth now so the first turn can start square.

That leaves one number for your printer: **`F_REV_CLEAR`**, the diametral
clearance on the 52.0 mm major, default 0.15 mm.

```
./export_fxpan.sh ringgauge
```

Four 7 mm rings, stamped `fxp_m52_0`, `_15`, `_30`, `_45` — hundredths of a
millimetre. Print them the same way you will print an arm: flat, mouth up,
same material, same layer height. Thread a real Fotodiox ring into each.

- If none of them start, go lower and reprint.
- If they all spin freely and rock, go higher — but suspect under-extrusion
  first, because it thins the crests that do the gripping.
- Keep the tightest one that runs down by hand for the full 7 mm without
  binding or rocking, and set `F_REV_CLEAR` to its number before you print
  the arms.

A 0.75 mm pitch is fine work for FDM. If the crests come out ragged, drop to
0.15 mm layers and slow the outer perimeter for the arms; the mouth is only
8 mm of the print. And it does not have to be perfect — the two M3 grubs are
what actually hold the ring's clock and roll. The thread only has to pull it
down square.

Which the old lock was not helping with either. An M3 nut wants 2.8 mm of
radial depth and the wall over the M52 female is 3.0 mm, so the nut pocket
came out the far side: a 5.7 mm window straight through the thread, twice,
over 7 of the 8 mm of engagement. Two gaps for the ring to jump on every
turn. The nuts now sit **outboard** of the thread in a pair of lugs, and only
the 3.2 mm screw crosses it.

The lugs stop at the reverse ring's own outside diameter. That is the only
thing that can be said about clearing the camera's front panel without
measuring the panel: whatever the lug is, it is never proud of the metal ring
that already has to live in that gap. So the strength comes from flaring each
lug down onto the cookie rather than from standing it further out — which
also means they print with no overhang at all, arm-up, straight off the plate.
They sit at **135° and 225° from camera-up**, square about the far side of the
tube: camera-up itself is raked back for the pentaprism nose and had 1.4 mm
of wall under the old first screw, and the azimuth 90° from it is where the
cookie runs out of plate. Sitting the pair symmetrically about the opposite
edge is also what keeps them from driving the plate wider, now that the plate
is sized off whatever sticks out furthest. There is 0.93 mm of wall left
between each nut pocket and the thread, and it is not a loaded face — driving
the screw reacts the nut outward, into the 1.2 mm cap.

## Focus range

| helicoid | subject |
| --- | --- |
| 17.5 mm (near collapsed) | infinity |
| 20 mm | 13 m |
| 24 mm | 5.2 m |
| 31 mm (open) | 2.6 m |

If the helicoid has not arrived, print `stem_el180_inf` instead of `stem`.
It is the same cookie with a 17.5 mm boss — the 180's flange lands where the
collapsed-plus-a-hair helicoid would have put infinity. Female M62 is the
outer 8 mm; no printed male. Swap for `stem` + the bought helicoid when that
lands. `el180_adapter` is the older two-piece stand-in (male into the short
boss) and is not needed if you print the inf stem.

## Apertures

Stopping down shrinks the bundle at every station, so this body has no upper
limit where it starts to vignette again — **everything from f/8.4 down to f/22
is clean, and it only gets better.**

The numbers below are worked at the frame *corner*, because the bore is round
and the corner of a 36 × 23.9 mm window sits 21.6 mm from its centre against
the 18 mm the long axis alone suggests. Reading it off the long axis makes the
body look clean at f/5.6 when it isn't.

| f-stop | plate across the fold (53.03) | plate along it (50) | flange bore (44.0) | traced corner |
| --- | --- | --- | --- | --- |
| 5.6 | 44.4 mm · +19.5% | 29.1 mm · +72% | 46.8 mm · **clips** | 0.836 |
| 8 | 38.4 mm · +38.2% | 23.0 mm · +117% | 44.3 mm · **clips** | 0.951 |
| 11 | 34.5 mm · +53.6% | 19.2 mm · +161% | 42.7 mm · clears | 1.000 |
| 16 | 31.3 mm · +69.3% | 16.0 mm · +213% | 41.4 mm · clears | 1.000 |

So the plate is never the constraint on the recommended build — the mouth is,
and 44 mm is as wide as an F mount gets. The long axis of the panorama is
clean at every aperture including f/5.6; only the corners shade. The
along-the-fold column is why the plate is 50 there and not 75: that margin was
never going to be spent, and buying it cost 25 mm of chassis height.

Set `FSTOP` in the customizer to see any aperture. The red outline in the
preview is the plate footprint the bundle actually needs, and the console
marks any station that clips. Falloff maps per aperture:
[`docs/kraken/fxpan_frames.png`](../../docs/kraken/fxpan_frames.png) and
[`fxpan_margins.png`](../../docs/kraken/fxpan_margins.png).

## What this body is not

It is a **20.4° horizontal** field. 65 mm of frame at 180 mm of focal length
compresses distant landscape; it is not an XPan-like wide sweep. The aspect
ratio matches XPan, the angle of view does not. Going wider means a shorter
lens, and `PATH` has to equal the focal length, so that is a new body rather
than a setting.

The two 50 mm first-surface mirrors are not used here. Keeping the stitch axis
off every fold's foreshortened dimension forces all folds coplanar, and
coplanar folds cannot make the two bodies parallel. They stay with the V body.
