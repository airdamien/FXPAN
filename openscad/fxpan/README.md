# FXPAN 65

A clean-sheet FX panoramic body: two D800 bodies behind one EL-Nikkor 180/5.6N
and a 75 × 75 × 1 mm 50/50 plate beamsplitter at 45°. Each sensor takes one
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

**Buy the metal reverse rings.** They keep the real 44 mm F throat. The printed
F bayonet mesh is 38 mm clear, and because the frame corners need 38.47 mm even
at infinite f-number, **it never passes the whole frame at any aperture** —
f/22 still leaves the corners at 0.34. `ARM_MOUNT = 0` is the default for that
reason; the printed variant is a fitting aid for checking clocking and lug fit.

**Buy the 75 mm plate.** A plate at 45° only presents `size/√2` across the
fold, and the frame needs 44.4 mm there at f/5.6. 75 mm gives 53.03 mm — 19.5%
of margin, growing as you stop down. The 50 mm plate gives 35.36 and clips
until f/11, and it clips *the long axis of the panorama*, which is much worse
than losing corners. `BS_SIZE = 50` still builds and the chassis shrinks to
suit, but it is an f/11 body.

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
| `chassis` | 1 | floor down |
| `lid` | 1 | outer face down |
| `fxp_tray` | 1 | floor down |
| `stem` | 1 | cookie flange on the bed, M62 boss up |
| `arm_r`, `arm_t` | 1 each | cookie flange on the bed, camera mouth up |
| `base` | 1 | flat; tripod insert and screw heads enter from the bed |
| `cradle_r`, `cradle_t` | 1 each | flat, either way up |
| `baffle` | 2 sheets — one arm's worth per sheet (4 rings at the f/11 default) | flat |
| `shims` | 1 sheet of 3 | flat |
| `el180_adapter` | only if the helicoid has not arrived | male thread down |

Colour inlays, if you want the badge in filament rather than paint — drop each
into the chassis as a separate part and give it its own material:

| STL | suggested |
| --- | --- |
| `chassis_logo_fx` | gold |
| `chassis_logo_word` | off-white (PAN + its underline) |
| `chassis_logo_mp` | red (65MP) |
| `chassis_logo_rule` | any accent (hairline) |
| `chassis_logo_spec` | grey (`13248×4912 · 2.71:1`) |

The chassis pocket always contains all five. The plugs deliberately overrun
it — 0.08 mm into the walls and floor, 0.06 mm proud of the face — so no
surface is coplanar with the chassis and the slicer resolves each colour
instead of speckling the pocket. `chassis_logo` is all five merged if you
would rather paint one part.

Print the arms and the stem in the same material and from the same spool if
you can: the two camera legs have to agree to a fraction of a millimetre, and
a filament change between them is an easy way to lose that.

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
4. **Plate into the tray.** S1 — the 50/50 coated face, the one Edmund marks —
   goes **toward the lens**. Getting this backwards puts the glass path on the
   reflect leg instead of the transmit leg and the T arm's 0.303 mm
   compensation then works against you. The slot is keyed; the plate drops in
   from the top and sits on the shelf.
5. **Tray into the chassis**, floor down, then the two retention posts stand
   up through the lid's forks.
6. **Cookies down the C-channels.** Each of the three port cookies slides down
   its rebate from the lid side, stopping against the chamber wall behind it
   and captured on three sides. **Four M3 × 12 countersunk** per cookie into
   the nut pockets — two above the bore and two below. There is no wall
   outboard of the cookie, and the heads sit flush with its face, because that
   face is the outside of the camera and the D800 has to come right up to it.
   The screws are what hold a cookie in, so do all four. The two arm cookies
   read **▲ R FXP** and **▲ T FXP**; the chassis wall carries the same mark
   beside each slot, so put each cookie where its letter matches. The stem
   cookie is the odd one out and is stamped `fxp_stem`.
7. **Reverse rings.** Thread one M52→F ring into each arm mouth — this is the
   fit `ringgauge` was for. Each mouth has an engraved radial line at the body
   lock-pin azimuth; clock the ring to it, then lock with the two M3 set
   screws 120° apart. The set screws, not the thread, are what actually hold
   clock and roll.
8. **Lid** with four M3 × 20 into the corner nuts. Check the forks have
   captured the tray posts before you tighten.
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

Before step 10, measure your own bodies and set `D800_TRIPOD_ABOVE` (1/4-20
above the chassis bottom, default 10.0 mm) and `D800_TRIPOD_IN` (lens axis to
tripod socket along the base, default 44 mm) in the customizer, then reprint
`base` and the cradles. The defaults are carried over, not measured.

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

**Roll.** Shoot a level horizon on both. Both bodies sit upright and landscape,
and the seam is horizontal, so any relative roll shows up as a wedge in the
overlap that no stitcher will hide. Loosen the reverse ring set screws,
rotate, re-lock.

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
8 mm of the print. And it does not have to be perfect — the two M3 set
screws are what actually hold the ring's clock and roll. The thread only has
to pull it down square.

## Focus range

| helicoid | subject |
| --- | --- |
| 17.5 mm (near collapsed) | infinity |
| 20 mm | 13 m |
| 24 mm | 5.2 m |
| 31 mm (open) | 2.6 m |

If the helicoid has not arrived, `el180_adapter` is a printed fixed spacer
solved for infinity — no travel at all. Its length tracks the chassis, so it
stays correct if you change `BOX_XY`. Print a second at +0.5 mm if the first
lands long; shims can only add.

## Apertures

Stopping down shrinks the bundle at every station, so this body has no upper
limit where it starts to vignette again — **everything from f/8.4 down to f/22
is clean, and it only gets better.**

The numbers below are worked at the frame *corner*, because the bore is round
and the corner of a 36 × 23.9 mm window sits 21.6 mm from its centre against
the 18 mm the long axis alone suggests. Reading it off the long axis makes the
body look clean at f/5.6 when it isn't.

| f-stop | plate (53.03 available) | flange bore (44.0 available) | traced corner |
| --- | --- | --- | --- |
| 5.6 | 44.4 mm · +19.5% | 46.8 mm · **clips** | 0.836 |
| 8 | 38.4 mm · +38.2% | 44.3 mm · **clips** | 0.951 |
| 11 | 34.5 mm · +53.6% | 42.7 mm · clears | 1.000 |
| 16 | 31.3 mm · +69.3% | 41.4 mm · clears | 1.000 |

So the plate is never the constraint on the recommended build — the mouth is,
and 44 mm is as wide as an F mount gets. The long axis of the panorama is
clean at every aperture including f/5.6; only the corners shade.

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
