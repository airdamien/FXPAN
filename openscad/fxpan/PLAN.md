# FXPAN 65 — design plan

Read this before changing anything in `openscad/fxpan/`. It records the
numbers, where each one comes from, and which ones you are not free to move.
The body is a clean sheet: it shares no printed part with `hybrid_shift/`,
`hybrid/` or `v/`, and its bore is deliberately wider than theirs.

**What it is.** Two D800 bodies behind one EL-Nikkor 180/5.6N and a
75 × 75 × 1 mm 50/50 plate beamsplitter at 45°. Each sensor takes one half
of the field; the two frames stitch to **64.80 × 23.9 mm, 2.711:1,
13248 × 4912 = 65.1 MP**. XPan is 65 × 24 mm and 2.708:1, so the aspect is
within 0.1%. Horizontal field is **20.4°** — read the honest limits below
before you get excited about that.

The frame is corner-to-corner clean from **f/8.4**, limited by the 44 mm
Nikon F throat. Verify it yourself with `kraken/fxpan_paths.py`, which ray
traces the thing and exits non-zero if the geometry stops agreeing with
`params.scad`.

## The three constraints that set everything

Every number in `params.scad` falls out of these pulling against each other.
If you change one, re-derive the others.

### 1. The plate has to pass the whole frame

A plate tilted 45° presents only `size/√2` across its plane of incidence.
`cam/pano.py` requires landscape sensors with a horizontal seam, so the wide
stitch axis is forced onto exactly that foreshortened dimension — there is no
orientation trick available.

The exit pupil sits at the lens, `EL_FOCAL` from the sensor. At a station `d`
ahead of the sensor, a field half-width `ym` fills

```
ym·(P−d)/P + (P/2N)·(d/P)          P = EL_FOCAL = 180, N = f-number
```

That is largest at the sensor and smallest at the lens, so **the plate wants
to be as far forward as it will go, and stopping down only ever helps.** With
the plate at `d = 112.5 mm` and `ym = 32.4` (half the 64.80 stitch):

| f-stop | need in plane | 75 mm plate (53.03) | 50 mm plate (35.36) |
| --- | --- | --- | --- |
| 5.6 | 44.39 mm | +19.5% | clips |
| 8 | 38.72 mm | +37.0% | clips |
| 11 | 34.93 mm | +51.8% | +1.2% |
| 16 | 31.78 mm | +66.9% | +11.3% |

So: **75 mm plate, clean from f/3.9. A 50 mm plate only works from f/11.**
This is the whole reason the body is not just a rebore of `hybrid_shift`.

### 2. The F throat has to pass the frame corners, and mostly can't

This is the constraint that actually limits the body, and the one that is
easiest to get wrong — I got it wrong first time round and the ray trace
caught it.

A bore is round, so what matters is **distance from the bore axis**, and the
corner of a 36 × 23.9 mm window is 21.6 mm from its centre against the 18 mm
the stitch axis alone suggests. Working the bore along the stitch axis
understates it by 3.4 to 4.3 mm. So `need_bore()` is evaluated at the corner:

```
c  = corner·(P−b)/P + shift·(b/P)        corner = (18, 11.95)
r  = |c| + (P/2N)·(b/P)
```

At the F flange (`b = 46.5`) that gives **46.77 mm at f/5.6**, against the
**44.0 mm** a real Nikon F throat provides. So:

| f-stop | corner needs | 44 mm throat | traced corner illumination |
| --- | --- | --- | --- |
| 5.6 | 46.77 mm | clips | 0.836 |
| 8 | 44.28 mm | clips | 0.951 |
| 11 | 42.69 mm | clears | 1.000 |
| 16 | 41.37 mm | clears | 1.000 |

**The frame is fully lit from f/8.4.** Wide of that the corners lose light
while the stitch axis stays perfectly clean, so it shows up as corner
shading, not as a broken stitch.

Three things follow, and none of them are fixable by printing differently:

- **44 mm is a ceiling, not a choice.** `F_BORE` is set to 44.0 so the printed
  part is flush with the ring and the bought ring is the sole limit. It used
  to be 43.5, which cost a third of a stop for nothing.
- **An unshifted D800 needs 40.35 mm there at f/5.6.** The F throat only ever
  had 3.65 mm of margin; a 14.4 mm shift spends essentially all of it. This is
  a property of putting a shifted full-frame bundle through an F mount, not of
  this design.
- **The printed bayonet never works.** Its corner term alone is 38.47 mm and
  the mesh is 38.0, so a printed F mouth clips the frame corners at *every*
  aperture, including f/22. See the mouth section below.

The only way to buy f/5.6 back is to shrink the shift to 8.29 mm, which drops
the stitch to 52.6 mm and 2.20:1 — it stops being an XPan frame. Not worth it.

### 3. The path has to land on 180 mm

`PATH` is lens flange to sensor along the fold, and it has to reach the
EL-Nikkor's flange focal distance for infinity. It is

```
PATH = BOX_XY + 2·PORT_PATCH_T + ARM_TUBE + F_REV_STACK + FLANGE_F
       + EL180_M62_LEN + (helicoid − EL180_HELI_MALE)
```

Note `BOX_XY` appears once but spans both legs — **every millimetre of
chassis costs two millimetres of budget.** That is the trap. Two earlier
attempts died here:

- **A cube chassis does not fit.** A cube tall enough for a 75 mm plate on its
  diagonal is 111 mm, which makes `PATH ≥ 207 mm`. Infinity is then
  unreachable at any helicoid setting. This is why `BOX_Z` and `BOX_XY` are
  separate: `BOX_Z` (108) carries the plate, `BOX_XY` (92) comes out of the
  path budget and only has to clear the shifted port windows.
- **A 20 mm M62 nut does not fit.** `hybrid_shift` puts a 20 mm female nut on
  its stem. 20 mm of nut plus 17 mm of collapsed helicoid is 37 mm on the lens
  side and blows the budget on its own. The stem here is an **8 mm female boss
  on the cookie and nothing else**; the bought helicoid's male bottoms
  straight onto it.

Result: `BOX_XY = 92` gives **PATH 179.5 … 193.5 mm**, so 180 mm lands at
17.5 mm of the helicoid's 17–31 mm travel.

| helicoid | PATH | subject |
| --- | --- | --- |
| 17.5 mm | 180.0 mm | infinity |
| 20 mm | 182.5 mm | 13.1 m |
| 24 mm | 186.5 mm | 5.2 m |
| 31 mm | 193.5 mm | 2.6 m |

`BOX_XY` is rounded **down** to a whole mm on purpose. Shims can only add
length, so a chassis 1 mm too large can never reach infinity, while one 1 mm
too small is fixed with a 1.0 mm shim.

### 4. The camera has to be able to physically go on

A D800 is not flat at its flange. Its front panel stands `D800_PROUD` ≈ 13 mm
past the bayonet's register face, and the body goes on by pushing that panel
toward the chassis and twisting to lock. So the F register has to stand off
the chassis face by at least that much, and the body is 146 × 123 mm against
a 100 mm chassis face, so there is **nowhere to relieve locally** — the whole
face has to be behind the line.

Everything between the chassis face and the register is arm tube and reverse
ring, and the chassis half-width cancels out of both sides:

```
standoff = ARM_TUBE + F_REV_STACK − (shell outboard of the cookie)
```

`BOX_XY` does not appear. That is worth stating plainly, because the instinct
is to shrink the chassis and it does nothing: shrinking `BOX_XY` frees path
budget, which is only useful because it lets `ARM_TUBE` grow by the same
amount. The first cut of this body had `ARM_TUBE = 5`, a 4 mm retaining wall
outboard of each cookie, and therefore **9 mm of standoff** — a D800 would
have hit the chassis 4 mm before the bayonet seated. For comparison,
`hybrid_shift`'s long variant, which has actually been built, has 19 mm.

Two changes, neither of which touches an optical number:

- **The outboard retaining wall is gone** (`chassis_shell_t()` is now just
  `patch_t()`). On the camera faces that wall was precisely what the front
  panel landed on. The cookie is stopped inboard by the chamber wall it sits
  against, on three sides by its rebate, and outboard by four countersunk
  M3s — a better joint than the wall was, and worth 4 mm.
- **`ARM_TUBE` is solved from the camera rather than picked**, and `BOX_XY`
  takes what the path budget has left. 5 mm becomes 8 mm, 95 becomes 92, and
  `PATH` is unchanged at 179.5 mm because the two trade 1:1.

That gives **16 mm of standoff against 13 mm of camera**, 3 mm to twist it on.
The lever is nearly spent: the floor on `BOX_XY` is 91.4 mm, where the shifted
port bore starts to break into the adjacent chamber wall, so `ARM_TUBE` cannot
go much past 9 without the helicoid running out of travel. If your bodies
measure more than 16 mm proud, `WATCH_ME.scad` will tell you infinity has gone
out of range rather than quietly building something that cannot focus.

### 5. A 0.75 mm pitch female thread has to be truncated

The reverse-ring mouths on the earlier bodies never took a ring: too loose to
start, would not run down. That is a profile fault, not a clearance fault.

`lib/threads.scad` cuts a sharp full-height V unless `tooth_height` says
otherwise. At P = 0.75 that is 0.650 mm of radial depth, against the 0.406 mm
a real M52 × 0.75 female has. The printed crests stand a quarter of a
millimetre proud, into the ring's thread *roots*. The ring then rides on those
crests rather than its flanks — line contact on a knife edge — so it rocks,
starts crooked and never bites. It feels like a bore that is too big, which
is why it was read that way for so long.

`F_REV_TOOTH = 0.52` truncates the crest back to the real minor and
`F_REV_CLEAR` puts the clearance on the major where it belongs, plus a 0.9 mm
lead-in at the mouth. `F_REV_CLEAR` is the only number a builder should have
to touch, and `PART = ringgauge` exists so they can find it in ten minutes
instead of in a three-hour arm print.

## Locked numbers

Treat these as fixed inputs. `WATCH_ME.scad` echoes every one of them on
open, with a margin report — check the echo before you trust this table.

| | |
| --- | --- |
| `SENSOR_W` / `SENSOR_H` / `FLANGE_F` | 36.0 / 23.9 / 46.5 mm |
| `overlap_frac()` | 0.20 |
| `sensor_shift()` | 14.40 mm |
| `stitch_w()` | 64.80 mm, 2.711:1, 13248 × 4912, 65.1 MP |
| `BOX_XY` × `BOX_Z` | 92 × 108 mm chamber (outer 100 × 100 × 116) |
| `BS_SIZE` / `BS_THICK` / `BS_N` | 75 / 1.0 / 1.52, 45°, S1 toward the lens |
| `bs_t_comp()` | 0.303 mm — shortens the T arm only |
| `TUBE_ID` / `TUBE_OD` / `WALL` | 46 / 58 / 6 mm |
| `F_BORE` / `F_THROAT` | **44.0** mm, flush with the ring (others use 40.3) |
| `ARM_TUBE` | 8.0 mm past the cookie — solved from `D800_PROUD`, not picked |
| `D800_PROUD` / standoff | 13.0 mm of camera against 16.0 mm of air |
| `EL180_M62_LEN` | 8 mm — the entire stem |
| `PATH` | 179.5 … 193.5 mm, infinity at helicoid 17.5 |

### The two mouths are not equivalent

| mouth | clear | frame corners |
| --- | --- | --- |
| metal M52→F reverse ring | 44.0 mm (real F throat) | clean from **f/8.4** |
| printed F bayonet (`f-mount_raw.stl`) | **38.0 mm** | **never clean** |

That 38 mm is measured off the mesh, not guessed. Raising `F_BORE` only opens
the peg and collar *behind* the bayonet; the mesh is its own stop and cannot
be `difference()`d without shredding preview and render. Since the corner term
alone is 38.47 mm, no aperture ever brings the printed mouth inside the frame:
at f/22 the corners still sit at 0.34 illumination.

**So the metal reverse ring is not optional, and `ARM_MOUNT = 0` is the
default for that reason.** The printed variant is a fitting aid — use it to
check clocking and lug fit, not to shoot with. `WATCH_ME.scad` says so in its
echo when `ARM_MOUNT = 1`.

`TUBE_ID = 46` is not the binding aperture: it clears the corners from f/6.95,
comfortably wide of the f/8.4 the mouth allows.

### Plate thickness is 1.00 mm, not 3 mm

A tilted plate puts astigmatism on the **transmit path only** — S1 faces the
lens, so the reflect path never enters glass.

| thickness | astigmatism | needs |
| --- | --- | --- |
| 1.0 mm | 0.172 mm | inside the 0.224 mm depth of focus at f/5.6 |
| 3.0 mm | 0.516 mm | f/16 |

So 1 mm is a non-issue and 3 mm is not. The transmit tube is shortened by
`bs_t_comp() = 0.303 mm` to pay back the glass path; nothing else changes.

## Honest limits — document these, do not bury them

- **f/8.4, not f/5.6.** The corners lose light wide open: 0.836 illumination at
  f/5.6 and 0.951 at f/8, clean by f/11. The stitch axis is never affected, so
  it reads as corner shading. The 44 mm F throat is the cause and nothing in
  this repo can change it.
- **20.4° horizontal.** 65 mm of frame at 180 mm of focal length is a
  telephoto panorama for distant compression, not an XPan-like wide sweep. The
  aspect matches; the angle of view does not. A shorter lens means a whole new
  path budget — `PATH` must equal the new focal length, which changes `BOX_XY`,
  which changes the plate size that fits.
- **The 50 mm plate you already own is an f/11 build.** `BS_SIZE = 50` still
  builds and `BOX_Z` shrinks to 83 automatically, but it clips the stitch axis
  itself at f/5.6 and f/8 — a worse failure than the corner shading above,
  because it eats the ends of the panorama rather than its corners.
- **The two 50 mm first-surface mirrors are not in the imaging path.** Keeping
  the stitch axis off every fold's foreshortened dimension forces all folds
  coplanar, and coplanar folds cannot make the two bodies parallel. Two D800s
  side by side would need their axes 146 mm apart, which does not fit in a
  180 mm path. They stay with the V body.
- **Cradle dimensions are unmeasured.** `D800_TRIPOD_ABOVE` and
  `D800_TRIPOD_IN` default to 10.0 and 44 mm. Measure your own bodies and set
  them in the customizer before printing `base` or the cradles.
- **`D800_PROUD` is unmeasured too**, and it is the one that bites hardest:
  get it wrong and the camera will not go on at all. 13.0 mm is the reported
  figure, not a measured one, and the standoff is 16 mm. Measure before you
  print a chassis.
- **The M52 mouth is printer-dependent.** `F_REV_CLEAR = 0.15` is a starting
  point, not a result. Print `ringgauge` and set it from a real ring.

## Files

| file | what |
| --- | --- |
| `params.scad` | every number above, with the derivations as comments |
| `WATCH_ME.scad` | customizer, `assembly()`, all part modules, `export_part()`, `diagnostics()` |
| `fxp_tray.scad` | 75 mm plate cartridge, sized off `BS_SIZE` |
| `fxp_f_mount.scad` | local F-mount copy bound to this body's bore |
| `shims.scad` | 0.2 / 0.5 / 1.0 mm focus shims |
| `../../kraken/fxpan_paths.py` | the ray trace that checks all of the above |

`fxp_f_mount.scad` exists because `openscad/f_mount_male.scad` `include`s the
top-level `openscad/params.scad`. With `use`, its modules keep *those* values
(`F_BORE` 40.3, `TUBE_ID` 52) rather than this body's. The bayonet mesh itself
is shared and untouched.

Reused unchanged: `../lib/part_stamp.scad`, `../lib/threads.scad`,
`../camera_body.scad`, `../../f-mount_raw.stl`.

The `SHELL = full | inner | outer | logo` split and `mm_split()` are kept from
`hybrid_shift`: the inner PETG lining matters for light-tightness and the
badge inlay path depends on `logo`. **`full` is the recommended print** — the
inner/outer split is there if you want it, but it buys little on a body this
small and adds two more failure modes.

One deliberate omission: `tube_lining_mask()` does **not** line the F throat.
The throat is the tightest aperture in the body — 1.3 mm clear of the frame
corners even at f/11 — so a 1.6 mm liner in there would vignette outright.
Flocking handles glare in the throat instead.

The drop-in baffle rings are sized from `need_bore()` at `FSTOP`, and
`baffle_ring_fits()` drops any ring the bundle has already filled. At f/5.6
that is all five, so `baffle.stl` comes out empty and the echo says so; at the
f/11 default four survive and at f/16 all five do. **If you change `FSTOP`,
reprint them** — a set cut for f/16 vignettes at f/11.

## Parts and stamps

Every part carries `fxp_` + its name + the export timestamp, via `fxp_tag()`.

| part | stamp | where |
| --- | --- | --- |
| `fxp_chassis` (+`_inner`/`_outer`) | `box_floor_stamp` | chamber floor |
| `fxp_lid` | `plate_stamp` | outer face |
| `fxp_tray` | `part_stamp_cut` | −Y chamber wall, readable from the stem |
| `fxp_stem` | `flange_stamp` | cookie, camera side |
| `fxp_arm_r` / `fxp_arm_t` (+`f`) | `flange_stamp` | cookie, camera side |
| `fxp_el180` | `part_stamp_stack_cut` | hex flat |
| `fxp_base`, `fxp_cradle_r/t` | `part_stamp_cut` | top face |
| `fxp_bf1`…`fxp_bf5` | `part_stamp_stack_cut` | each surviving baffle ring |

`box_floor_stamp` is written for a cube, so the chassis call feeds it `BOX_XY`
and then drops it `-(BOX_Z − BOX_XY)/2` to reach the real floor.

The −X wall carries the FXPAN badge inlay: the D3-era Nikon FX body badge
standing in for the X of the XPan wordmark, then PAN with its underline, then
65MP over `13248×4912 · 2.71:1`. Badge and PAN are drawn geometry traced off
the originals; the two text lines are Futura, which ships with macOS —
re-exporting on Linux needs the same family installed.

`LOGO_FIT = 0.08` and `LOGO_PROUD = 0.06` are load-bearing. The colour plugs
bite 0.08 mm into the pocket walls and floor and stand 0.06 mm proud of the
wall, so **no face is coplanar with the chassis**. Match them exactly and the
slicer gets two coincident faces per surface and renders the pair as speckled
garbage. `LOGO_SCALE = 1.15` fits the lockup to this wall; it is applied
inside the plug fit, so the two fit numbers stay in real mm.

## Load path

A D800 is about 1 kg, and hanging it off a printed F bayonet is the weak point
in the other bodies. `fxp_base` is an L-shaped web carrying four pads: one
under the chassis (its 1/4-20), one per camera, and one for the tripod. Each
camera bolts through its own 1/4-20 into an `fxp_cradle`, so **the bayonet
locates and never carries load.**

The cradle is a bare plinth. It briefly had an anti-twist flange up the back
of the body, and that was wrong on both counts. The bayonet already fixes yaw
far better than a flange 46 mm wide could — anything narrow enough to sit on
the pad has almost no leverage, and anything with leverage would have to span
most of the D800's 146 mm width. More importantly, mounting the camera means
bringing it in along the axis and twisting to lock, so anything standing up
off the plinth is in the way of the one motion the whole build depends on.
The 1/4-20 slot runs along the axis so the screw follows the bayonet in
rather than fighting it: start it loose, seat the mount, then tighten.

Tripod socket goes under the combined centre of mass — `base_tripod_xy()`
weights the chassis-plus-lens at the origin against 1 kg at each camera pad.

## Export

```
./export_fxpan.sh              # all 35 STLs -> stls/fxpan/
./export_fxpan.sh chassis lid  # just these
```

That wraps `./export_stls.sh --fxpan`. Every part is stamped with the render
minute. All 35 export manifold with no warnings; if yours do not, say so
rather than shipping it.

## Verification

```
pip install -r kraken/requirements.txt
python kraken/fxpan_paths.py
```

Ray traces the system and **exits non-zero** if any of these stops holding:

- the stitch spans 64.80 mm with a 7.20 mm overlap, at every aperture
- the stitch axis is never clipped, at every aperture
- the frame corners are fully lit at and beyond the aperture the model claims
  (f/8.4), and *not* fully lit wide of it — so the model cannot quietly drift
  pessimistic either
- the two shift senses are opposite

Writes `docs/kraken/fxpan_paths.png`, `fxpan_frames.png`, `fxpan_pano.png`
and `fxpan_margins.png`.

One thing to know if you extend it: **KrakenOS's tilted-surface convention
does not fold correctly.** An `obj → thin lens f=180 → 45° mirror (AxisMove=2)`
system puts a 5° field at −3.674 mm where the unfolded one correctly gives
15.748 mm, and a tilted 1 mm plate puts the axial ray 55 mm off centre instead
of 0.303 mm. `reflect_system()` in `hybrid_paths.py` draws a fold that does not
trace. So `fxpan_paths.py` traces the imaging unfolded, where KrakenOS is
exact, and handles the fold with explicit reflection algebra — the √2
foreshortening at the plate and the sense reversal, both derived from the
reflection matrix rather than asserted. Round bores are fold-invariant and are
tested directly.

## If you change something

- **Moved `BS_SIZE`?** `BOX_Z` follows automatically. Re-read the plate margin
  line in the echo.
- **Moved `BOX_XY`, `ARM_TUBE`, `EL180_M62_LEN` or the mount?** You changed
  `PATH`. Check the `infinity:` echo line still says *in range*.
- **Moved `overlap_frac()`?** `sensor_shift()` and `stitch_w()` both move, so
  the port windows move and so does the required bore. Check the
  `chamber half … vs port reach` and `arm bore` echo lines, update `OVERLAP` in
  `cam/pano.py` to match, and mirror the change into `kraken/fxpan_paths.py`
  and rerun it — a bigger shift buys width and costs corners.
- **Changed the lens?** `EL_FOCAL` must equal the new focal length *and* the
  new flange focal distance has to be reachable. This is a new body, not a
  parameter change.
- **Touched `need_bore()`?** Work it at the corner. The stitch-axis version is
  4.3 mm optimistic at f/5.6 and it will tell you the body is clean wide open
  when it is not.
