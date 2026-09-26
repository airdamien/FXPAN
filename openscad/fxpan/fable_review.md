# FXPAN 65 — design review (Fable, 2026-09-26)

Configuration reviewed: **two D800 on printed F-mount tubes** (`arm_r_fw` /
`arm_t_fw`, `ARM_MOUNT = 1`) behind the **Nikkor-W 180 mm f/5.6 in Copal 1**
on the M62 helicoid (`STEM = 2`: `stem_w` + `stem_nw180`), chassis at
`5281288`. Printer: Bambu Lab H2C, 0.4 mm nozzle, PETG (or ASA/ABS; the H2C
chamber heats to 65 °C so either is fine).

Everything below was checked against the code, not the README. The numbers
come from `WATCH_ME.scad`'s own functions, evaluated with OpenSCAD
2026.06.12 (`-D ARM_MOUNT=1 -D STEM=2`), plus a few things the diagnostics
do not currently print. Where I estimate a camera dimension I say so; the
D800 mesh in the preview is known to be rough and I did not trust it.

Contents

1. Verdict
2. Numbers as built
3. Blocking issues (fix before printing a chassis)
4. Functional improvements
5. Printability on the H2C at 0.4 mm
6. Nice to have
7. Measure-first checklist
8. Documentation drift
9. How to verify each fix

---

## 1. Verdict

**The optics and the path are self-consistent for the Nikkor-W build.**
The lens flange lands at 178.8 mm from the sensor with the helicoid at
17.5 mm, the T leg is shortened for the glass, the plate has 50 % margin
across the fold at f/11, and the tube bore is never the limit. The chassis,
tray, lid, base and cookies are a coherent, printable set of parts. As a
proof of concept it will form two images that stitch.

**It will not deliver the advertised f/8–f/11, 65 MP result with printed
F-mount tubes**, and there are three mechanical problems that will stop the
first build regardless of mount:

| # | Issue | Severity |
| --- | --- | --- |
| A | Printed F mouth is 40 mm; the frame corners are only clean from **f/30** | blocks the optical goal |
| B | Camera R's grip almost certainly hits camera T's front corner (both bodies upright) | blocks assembly |
| C | Base camera pads are 8 mm off for the W arms; the 1/4-20 sits at the end of its slot | blocks assembly |
| D | Nikkor-W infinity has 0.5 mm of helicoid margin and the nose leaves 2 mm of thread for the Copal ring | likely no infinity |

A and B are the ones to think about before anything else. A is a limit of
putting a 14.4 mm shifted full-frame bundle through a printed F barrel —
the fix is a different mouth. B is a property of two upright D800 bodies at
90° with registers 71.5 mm from the fold; the fix is buying separation with
the Nikkor-W's extra 20.3 mm of path, which the current W design spends on
a helicoid stack instead.

---

## 2. Numbers as built (`ARM_MOUNT=1`, `STEM=2`)

```
BOX_XY 92, BOX_Z 83, outer 100 × 100 × 103.5, plinth 20.5
ARM_TUBE 8, W_ARM_EXTRA 8, F_FMOUNT_STACK 3
reflect_tube_len 21.0, transmit_tube_len 20.697 (T shorter by bs_t_comp 0.303)
register from plate: d_plate_to_mount + arm_extra = 63.5 + 8 = 71.5
sensor from plate: 71.5 + 46.5 = 118.0
Nikkor-W flange: nw_flange_z 14.8 (stem frame) → plate→flange 60.8
PATH = 60.8 + 118.0 = 178.8 = NW_FFD          ✓ infinity at helicoid 17.5 of 17–31
nose rise (helicoid front → Copal flange) 3.3 mm, NW_BOARD 3.0
standoff skin→register: 21.5 mm with W arms (13.5 mm without)
base_cam_d 107.5  vs  register 71.5 + D800_TRIPOD_IN 44 = 115.5   ✗ 8 mm short
mouth: printed F lip 40 mm → corner-to-corner clean from f/30.3
need_bore at the flange: f/8 44.28, f/11 42.69, f/16 41.37, f/22 40.58, f/∞ 38.47
floor honeycomb: cells z −60 … −35.1, chamber floor −35.5 (cells open into the chamber under the tray)
logo cookie: −X skin, z −53.8 … 41.5 (95.3 × 100 × 4 mm), 4× M3 CSK
```

The diagnostics echo **does not know about `STEM=2` or the W arms**: it
reports the EL-Nikkor path (158.5) and the non-W standoff (13.5 mm, 0.5 mm
to twist the body on). See §4.6.

---

## 3. Blocking issues

### 3.A — The printed F mouth vignettes the frame corners until f/30

`mouth_clear()` returns `F_STL_THROAT = 40` for `printed_f()`. The corner
of a 36 × 23.9 frame shifted 14.4 mm needs, at the flange,

```
need_bore(N, 46.5) = 38.47 + 46.5 / N      (mm; from params.scad need_bore())
```

so the aperture at which a given mouth passes the whole frame is
`N = 46.5 / (D − 38.47)`:

| mouth clear D | corners clean from | note |
| --- | --- | --- |
| 40.0 (Archive-663 lip as shipped, `F_STL_THROAT`) | **f/30** | what `arm_*_fw` prints today |
| 41.0 | f/18 | 1.25 mm barrel wall left if the barrel OD is 43.5 |
| 41.5 | f/15 | 1.0 mm wall |
| 42.0 | f/13 | probably what a real metal reverse ring measures |
| 43.5 | f/9.2 | what README/PLAN claim for the printed mouth; not what the code does |
| 44.0 (`F_THROAT`, camera-side throat) | f/8.4 | no lens-side part can be this — it has to have a wall |

Rough corner illumination with the 40 mm lip (circular-cap estimate, extreme
corner only): ~0.67 at f/8, ~0.73 at f/11, ~0.82 at f/16, ~0.92 at f/22.
That is hard mechanical vignetting with a steep edge, not the gentle
cos⁴ roll-off a flat-field correction handles gracefully.

At the apertures where the 40 mm lip is clean, diffraction on a 4.88 µm
pixel has already taken the 65 MP away: Airy diameter 2.2 px at f/8,
3.0 px at f/11, 4.4 px at f/16, 6 px at f/22.

**Fix options, in order of preference**

1. **Use the metal reverse rings (`ARM_MOUNT = 0`) and caliper their clear
   aperture.** Put the measured value into `F_THROAT` (it is currently
   assumed equal to the camera throat, 44.0, which is not physically
   possible for a lens-side part). Expect ~42 → f/13. This is the
   configuration the whole body was designed around.
2. **If printed F is a must:** re-bore the Archive-663 lip. In
   `fxp_f_mount.scad`, `f_mount_stl_raw()` is imported whole; add a
   `difference()` with a cylinder of `F_STL_THROAT_BORED` (41.0–41.5) over
   the lip's height only. Keep ≥1.0 mm of wall under the bayonet barrel
   (the comment in that file says the barrel is 43.5; verify by measuring
   the mesh, not by reading the comment). Set `F_STL_THROAT` to the bored
   value so `mouth_fstop()` tells the truth. This is an f/15–f/18 body.
3. **Longer term:** replace the mesh with a parametric F bayonet whose
   barrel is 43.8 OD / 42.0 ID with no lip. Then printed and metal mouths
   are equivalent (~f/13).

Also: with an integral printed bayonet there is **no shim interface**. The
`shims` part only works between the arm mouth and a reverse ring. If the
two printed legs disagree in register by 0.2 mm (easy at 0.16 mm layers),
the only fix is a reprint. Add `ARM_TRIM_R` / `ARM_TRIM_T` customizer
numbers that add to `reflect_tube_len()` / `transmit_tube_len()` so a
0.2 mm correction is one parameter, not a redesign.

### 3.B — Camera R's grip collides with camera T's front-left corner

Both bodies are upright (`body_roll_r = 90`, `body_roll_t = 180`, both
landscape, horizontal seam). R sits on +X facing −X; its right-hand grip is
therefore on **+Y**, toward camera T. T sits on +Y facing −Y; its grip is on
−X, away from R. The shift senses are forced by the fold (`cam_axis`: R
shifted −Y, T shifted +X), so R's axis is at world Y = −14.4 and T's front
panel is at world Y = 71.5 − (front-panel proud).

The ghost box in the model (`ghost_body_at`) is a symmetric 146 mm cube
centred on the tube axis; the two ghosts touch exactly at Y = 58.5/58.6.
The D800 is not symmetric about its mount. **Estimate** (measure this):
axis → non-grip edge ≈ 60 mm, axis → grip edge ≈ 86 mm, grip protrudes
≈ 15–20 mm past the flange, non-grip front panel ≈ 8–13 mm past it.

```
R grip edge, world Y:   −14.4 + 86  = 71.6
T front-left corner, Y:  71.5 − 13  = 58.5   (71.5 − 8 = 63.5 if the non-grip panel is shallower)
                                     → 8–13 mm of interference
R grip front, world X:   71.5 − 20  = 51.5
T non-grip edge, X:      14.4 + 60  = 74.4   → the overlap is real in X as well
```

Collision iff (axis → grip edge) > 72.9 mm with `D800_PROUD = 13`. Any
D800 I know of exceeds that. The EL-Nikkor build is worse (register at
63.5, T front at ~50.5).

Things that do **not** fix it: swapping shift senses (R would shift toward
T), rolling R upside down (the cradle holds the body by its tripod socket),
shrinking `BOX_XY` (path-locked).

**Fix:** move T's front panel past R's grip edge. T's front moves 1:1 with
the register distance; R's grip edge does not move. You need the register
at ≈ 71.5 + (71.6 − 58.5) ≈ **85 mm from the plate**, i.e. about 13 mm
more standoff on both legs. The Nikkor-W has exactly 20.3 mm more flange
focal distance than the EL-Nikkor, and the current W design spends 12.3 of
it on the lens side (helicoid + 3.3 mm nose) and 8 on the arms. Spend it
the other way round:

- `W_ARM_EXTRA` → 18–20 (params.scad line ~185). Standoff becomes
  31.5–33.5 mm, T's front lands at 76.5–78.5 mm, clear of a 71.6 mm grip
  edge by 5–7 mm.
- The lens side then has 0.3–2.3 mm left, which does not fit a 17 mm
  helicoid. Two ways out:
  - **Fixed-infinity W nose**: an M62 male screwed straight into `stem_w`
    (thread −6 … 2), board face at `flange_z(NW_FFD) − W_ARM_EXTRA`, no
    helicoid. Focus with the **camera helicoid arms** (`arm_r_hw` /
    `arm_t_hw`, M52 female / M42 male 17–31 units); they put the register
    at the same station (`cam_heli_register_z`) so they cost no path. This
    also gives each leg independent focus, which you want anyway (§4.1).
  - Or keep the lens helicoid and take `W_ARM_EXTRA` as high as the nose
    allows (≈ 12 with a 2 mm board and infinity at helicoid 17.5). That
    buys 4 mm, not 13; it only works if the measured grip edge comes in
    under ~77 mm. Measure before choosing.
- Add a **real asymmetric ghost**: replace the cube in `ghost_body_at()`
  with two boxes (grip block and body block) parameterised by
  `D800_GRIP_HALF`, `D800_BODY_HALF`, `D800_GRIP_PROUD`, `D800_PANEL_PROUD`,
  rolled the same way as the real body, and echo the R-grip-vs-T-front gap
  in `diagnostics()`. Do not use `d800_body.stl` for this.

Also check the 10-pin remote and PC-sync terminals: they are on the **front,
non-grip side** of the D800 (~40 mm from the axis). For both cameras that
lands ~4 mm outside the chassis face edge with the plug body straddling the
R9 corner. Use a right-angle or slim 10-pin plug, or verify with the plug in
hand before printing.

### 3.C — Base pads ignore `W_ARM_EXTRA`

`base_cam_d()` (WATCH_ME.scad ~1639) is `d_plate_to_mount() +
d800_tripod_in()` = 107.5. With W arms the register is at 71.5, so the
tripod socket wants to be at 115.5. `BASE_SLOT_L = 18` gives ±9 mm, so the
screw sits 1 mm from the end of the slot with no float left — and the slot
exists precisely so the screw follows the bayonet in.

```scad
function base_cam_d() = d_plate_to_mount() + arm_extra() + d800_tripod_in();
```

Also carry `arm_extra()` into `base_r_xy()`/`base_t_xy()` (they read
`base_cam_d()` so they follow), and re-export `base`, `cradle_r`,
`cradle_t` for the W build. Add `arm_extra()` to the tripod-socket centre of
mass too (`base_tripod_xy()` uses the pad positions, so it follows).

### 3.D — Nikkor-W infinity margin and the Copal ring

- `heli_at_infinity()` = 17.5 mm on a 17–31 helicoid: **0.5 mm** of
  margin, against a bought part whose collapsed length is a nominal
  "~17 mm". If it arrives at 17.6 you cannot reach infinity; shims only add.
  With the fixed nose from §3.B this becomes a print dimension you control
  (0.1 mm), plus the camera helicoids' 14 mm of travel — which is the right
  place for the margin.
- If you keep the lens helicoid: `nw_rise()` is 3.3 mm and `NW_BOARD` is
  3.0, so the nose is already as thin as the board allows and cannot buy
  margin. Drop `W_ARM_EXTRA` to 6 and `NW_BOARD` to 2.0–2.5 to land infinity
  at helicoid ≈ 19 mm (2 mm margin).
- The Copal 1 neck is 5.1 mm with a 4 mm M39×0.75 thread. A 3.0 mm board
  leaves **2.1 mm** of neck for a retaining ring that is ~2.5–3 mm thick.
  Use `NW_BOARD = 2.0`. Also verify the ring OD fits `NW_CLEAR = 56`.
- The Ø54 rear cell reaches 22.3 mm behind the flange: through the nose,
  through the helicoid, and 1.5 mm past the stem's inner wall face into the
  chamber. **Measure the helicoid's clear inside diameter** (needs ≥ 55)
  and its **body OD** (must pass `heli_pass_d()` = 70 to sit in the
  `stem_w` recess; M62 17–31 units are commonly 72–78 mm). If the body is
  wider than 70 it sits on the skin 2 mm further out and infinity is gone.
  `HELI_NUT_OD` / `heli_pass_d()` are the knobs; the clamp screws cap the
  pass at ~75.

---

## 4. Functional improvements

### 4.1 Per-leg focus

Two legs, one lens helicoid: the legs have to agree in register to within
the depth of focus (0.3 mm at f/8) with no adjustment other than shims —
and with printed F there is no shim interface (§3.A). The camera helicoid
arms (`arm_*_hw` + `fmount_h_*`) give each leg 14 mm of travel. That
removes the need for the lens helicoid entirely on the W build and lets
§3.B spend the path on body clearance. Recommend making `arm_*_hw` the W
default and documenting `stem_w` + fixed nose as the W stem.

### 4.2 Field stop for the Nikkor-W

The Nikkor-W covers 70° (Ø253 mm image circle at f/22). The chassis passes
it through a Ø74.8 hole into a 92 mm chamber whose walls are 40 mm from the
axis. Everything outside the 65 × 24 field lights up the chamber, the tray
ribs, and the back of the plate, and comes back as veiling flare on both
sensors. The EL-Nikkor has the same problem to a lesser degree (5×7
coverage).

The bundle the sensors actually need at the stem inner face (158 mm from
the sensor with W arms, P ≈ 180):

| f-stop | across the fold (X) | along it (Z) |
| --- | --- | --- |
| 5.6 | 36.1 mm | 31.2 mm |
| 8 | 27.6 mm | 22.6 mm |
| 11 | 22.3 mm | 17.3 mm |

The W's rear cell protrudes 1.5 mm past the stem inner face, so the stop
cannot sit in the stem's Ø61.2 relief. Put it on the **inside face of the
tray's −Y wall** (`fxp_tray.scad`, `chamber_ports()` lens window,
currently a Ø61.2 round): for `STEM = 2` make that window a rounded
rectangle ≈ **41 × 35 mm (X × Z)** in a 1.5 mm plate at Y ≈ −36 (station
≈ 153 mm; bundle there 37 × 31 at f/5.6). Flock it. Keep the round window
for the EL-Nikkor, whose barrel passes through.

### 4.3 Beamsplitter polarization and colour

A 45° plate 50/50 is polarization dependent: Rs and Rp typically differ by
10–20 % for a "50/50 average of s and p" coating. Skylight at 90° from the
sun and water/glass reflections are strongly polarized, so **R and T will
differ in brightness by up to a stop in exactly the places a landscape
panorama has sky** — a scene-dependent seam that no flat-field or gain
fixes. The 7.2 mm overlap gives `cam/pano.py` something to blend across,
but blending hides, it does not remove.

- Pull the s/p curves for Edmund #37201 and put the worst-case split in
  `bom.md`.
- If it is bad, look at Edmund's **non-polarizing** plate beamsplitters
  (they exist in 50 × 50 and larger; check for 50 × 75 × 1 or accept the
  f/11 50 mm fallback already documented).
- Test early: shoot a polarized sky through the finished body and look at
  the seam before flocking anything.

Related: the 50/50 split costs each camera one stop (f/11 marked ≈ T/16 per
sensor), and the ±10 % over 400–700 nm becomes a colour cast difference
between halves. Shoot a grey card once, store per-camera channel gains in
`pano.py`.

### 4.4 The D800 mirror box is not in the ray trace

`kraken/fxpan_paths.py` stops at the flange. Behind it the D800 has a
rectangular mirror-box throat, a mirror at 45°, and the sensor's own
rectangular light shield, all designed for an on-axis pupil. The shifted
bundle enters up to ~11° off-axis at the far corner and its centroid is
displaced ~4 mm toward the shift at the flange plane. Before printing
anything final, mount one D800 on one printed arm and cookie (no chassis
needed, just hold it in front of the lens on a rail) and shoot a flat wall
at f/8 and f/11; look for straight-edged shading on the shifted side.

### 4.5 Light-tightness of the −X wall

With the logo frame window open, the −X wall is the 4 mm cookie over a
76 × 89 mm opening. The engraving pockets are 2.5 mm deep, leaving 1.5 mm
behind each glyph. If the inlays are printed in white/gold filament (both
translucent), light through the letters has 1.5 mm of body plastic to get
through. Either print the cookie body in a dark opaque filament and keep
the inlays as the top 1.2 mm only (`MARK_DEPTH` for the cookie = 1.2, so
2.8 mm remains), or leave `MARK_DEPTH` and paint the pockets. The tray wall
behind it shields the plate either way; this is about veiling glare, not a
hard leak.

The cookie perimeter gap (0.3 mm/side, `PORT_SLOT_CLEAR`) → frame window →
0.4 mm tray/chassis slip → over the tray wall top is a real path. A strip
of black felt on the cookie's inside face over the frame window kills it.

### 4.6 Diagnostics do not cover the W build

`diagnostics()` echoes the EL path, the non-W standoff (13.5 mm, "0.5 mm
to twist it on" — the README says 16/3), and nothing about the nose or the
W infinity margin. Add, gated on `nw_stem()`:

```
NW path: plate→flange (BOX_XY/2 + nw_flange_z()) + plate→mount (d_plate_to_mount() + arm_extra()) + 46.5 = … vs NW_FFD
NW infinity at helicoid heli_at_infinity() of EL180_HELI_MIN..MAX, margin heli_at_infinity() − EL180_HELI_MIN
nose rise nw_rise(), board NW_BOARD, neck left for the Copal ring 5.1 − NW_BOARD
standoff with arm_extra(): patch_t() + mount_standoff() + arm_extra() − skin_z()   vs d800_proud()
base pad vs register: base_cam_d() − (d_plate_to_mount() + arm_extra() + d800_tripod_in())   (must be 0)
R grip edge vs T front (from §3.B ghost parameters)
```

And make `body fit:` use `arm_extra()`.

### 4.7 Non-CPU lens on the D800

The printed F bayonet has no CPU contacts and no AI ridge. Both bodies must
be in **M** (or A with "Non-CPU lens data" set to 180 mm f/5.6). Confirm
the Archive-663 mesh has the lock-pin notch; without it the body can rotate
on the mount and roll alignment walks.

---

## 5. Printability — H2C, 0.4 mm nozzle

General: PETG or ASA, 0.16 mm layers for everything with a thread or a
register (arms, stems, nose), 0.20 mm for chassis/lid/tray/base. Walls
0.42 mm line width, ≥3 perimeters on the arms. Chamber heat on for ASA.

### 5.1 Chassis (`chassis`, floor down, 100 × 100 × 103.5)

- **Three round wall holes need support or a redesign.** The camera pass
  holes are Ø47 (`TUBE_ID + 1`) and the stem hole Ø74.8, printed as
  vertical-wall circles: the crown is a horizontal bridge. On the Ø47 holes
  a 1 mm droop lands **in the optical path** (the arm bore is Ø46, so the
  margin is 0.5 mm). Options: paint supports inside all three holes (they
  are hidden behind cookies), or open the pass holes to `TUBE_ID + 4` —
  the cookies cover them and the rebate is blind — or give them a pointed
  arch top. The tray's Ø46.6 windows have the same crown but the sag is at
  the top (along the fold), where the bundle has 20 mm of margin; harmless
  optically, still worth a support.
- **Honeycomb floor.** `FLOOR_HEX_WALL = 1.0` is two perimeters over a
  25 mm tall web — prints, but set "detect thin walls" on or use 1.2.
  `FLOOR_HEX_SKIN = 2.0` on the bed: at 0.2 mm layers Bambu's default
  3 bottom + 3 top shell layers is 0.6 + 0.6 mm of solid, so the middle
  0.8 mm of that skin is sparse infill under every cell. Set bottom shell
  layers to 10 for the chassis, or raise the skin to 2.4 and set 6/6.
- **Tripod insert wall is ~1 mm.** `floor_hex_cut()` fills cells with
  `norm([x, y]) < TRIPOD_INSERT_D/2 + hx` (8.67 mm). The six neighbouring
  cells sit at 9.0 mm and stay hollow; the closest hex edge is 5.0 mm from
  the axis against a 4.05 mm insert radius, so a heat-set insert goes in
  with ~1 mm of PETG around it (`TRIPOD_KEEP` intended 1.2 *above* it, not
  beside it). Change the test to `norm([x, y]) < TRIPOD_INSERT_D / 2 + hx
  + 2.5` — that fills exactly the centre plus its six neighbours and leaves
  the next ring hollow.
- The honeycomb opens into the chamber floor by 0.4 mm and the tray covers
  it. Fine, but say so in the README; it will surprise whoever slices it.
- Lid nut pockets and port nut traps are fed from the chamber side — good,
  no supports. The blind cookie rebates are 6.85 mm bridges — fine.
- Logo frame gussets are 45° — fine.

### 5.2 Arms with printed F (`arm_r_fw`, `arm_t_fw`)

- `cookie_print_flat()` chamfers one long edge at 45° on the chassis side
  so the part can be laid on that face and printed at 45°, layers running
  diagonally through the plate. That works and needs no support, but the
  README still says "flange on the bed, camera mouth up". Pick one and
  document it. **My recommendation: print flat, cookie down**, because the
  register distance is then a pure Z dimension (±0.05 mm) rather than a
  45° mix; the chamfer becomes a 45° overhang, which prints. Paint supports
  under the Ø62 collar (2 mm × 90° step over the Ø58 tube) and under the
  bayonet tabs.
- The chamfer leaves a knife edge along one side of the outer face; expect
  chipping. Consider stopping the chamfer 0.8 mm short of the outer face.
- Bayonet: 0.12–0.16 mm layers, slow outer wall, no elephant foot
  compensation surprises — the tabs are ~1.5 mm and the lock notch is
  small. Test-fit on a body before printing the second arm.
- The rear peg (`F_PEG_OD 52`, bore 44, 10.5 mm deep) merges into the tube
  wall cleanly.

### 5.3 Stems (`stem_w`, `stem_nw180`)

- `stem_w` has an M62×1 female (−6 … 2) under a Ø70 pocket (2 … 6). Printed
  skin-down that pocket floor is a 4.7 mm-wide horizontal ring overhang
  over the thread. Either print at the intended 45° (`stem_bed_chamfer`
  face on the bed — the code's plan), or print skin-down and support the
  ring, or chamfer the pocket floor 45° from Ø70 to Ø61. Female threads at
  45° print acceptably at `EL180_M62_TOL = 0.45`.
- `stem_nw180`: print **board face down** (Ø72 disc on the bed, M62 male
  up). Thread-down would leave a 5 mm × 90° disc overhang. The Ø41.8 board
  hole narrowing to Ø56 is an upward step, no support.
- M62×1 male: 0.12 mm layers, `tip_height`/lead-in already there.

### 5.4 Logo cookie (`logo_cookie`, 100 × 95 × 4)

Flat, outer face up so the inlays are top surfaces (import
`chassis_logo_*.stl` as parts of the same object in Bambu Studio — they are
generated in the same world frame). Brim; PETG will want to lift a plate
this size. The 45° bottom chamfer is on the bed side — a 45° overhang,
fine.

### 5.5 Fits at 0.4 mm

| feature | value | comment |
| --- | --- | --- |
| `PORT_SCREW_D` 3.2 | M3 clearance | prints ~3.0–3.1; use 3.4 for a true clearance hole |
| `PORT_NUT_AF` 5.7 | M3 nut trap | 5.5 nominal nut, prints tight; 5.8–5.9 |
| `PORT_SLOT_CLEAR` 0.6 | cookie in rebate | fine |
| `TRIPOD_INSERT_D` 8.1 | 1/4-20 heat-set | fine for CNC Kitchen short |
| `EL180_M62_TOL` 0.45 | M62×1 | fine |
| `CAM_HELI_TOL` 0.30 | M42/M52×1 | fine, verify with `cam_helicoid` gauge first |
| `LOGO_FIT` / `LOGO_PROUD` 0.08 / 0.06 | inlay interference | correct, keep |

### 5.6 Print order

1. `ringgauge` only if you go metal ring (recommended).
2. `cam_helicoid` gauge if you go camera helicoids.
3. One `arm_*_fw` (or `_hw`) + one cookie; test-fit a D800 and shoot the
   flat-field test in §4.4.
4. `stem_nw180` / fixed nose; test-fit the Copal ring.
5. Only then chassis, tray, lid, base, cradles.

---

## 6. Nice to have

- **Asymmetric D800 ghost** driven by four measured numbers (§3.B) and a
  collision echo. This is the single most valuable model improvement.
- **`ARM_TRIM_R/T`** register trims (§3.A).
- **Field stop** on the tray for the W (§4.2).
- **Thermal note**: 180 mm of PETG at ~6×10⁻⁵/K moves 0.2 mm over 20 °C —
  about the depth of focus at f/5.6. Camera helicoids make this a
  non-issue; a fixed build should refocus after the body warms.
- **Cable release / shutter**: leave the Copal on T (or B with a locking
  release) and fire both D800s from the 10-pin Y-lead. Note it in the
  README so nobody tries to sync three shutters.
- **Anamorphic**: unchanged; the ISCO hangs off the chassis 1/4-20 not the
  nose, as `bom.md` already says.
- Make `export_fxpan.sh`'s header stop saying "75×75×1" and "F_BORE 43.5".

---

## 7. Measure-first checklist (D800 in hand)

| what | where it goes | why |
| --- | --- | --- |
| axis → grip edge, axis → non-grip edge | new ghost params | §3.B collision |
| grip front and non-grip panel front, both past the flange | `D800_PROUD` → split into two | §3.B; standoff echo |
| lens axis above the baseplate | `D800_AXIS_BASE` | cradle height, both legs on axis |
| axis → tripod socket along the base | `D800_TRIPOD_IN` | base slot centre |
| 10-pin terminal position and plug length | — | corner clearance |
| reverse ring clear aperture (if metal) | `F_THROAT` | §3.A honest f-stop |
| M62 helicoid: collapsed length, body OD, clear ID | `EL180_HELI_MIN`, `HELI_NUT_OD`/`heli_pass_d`, new `EL180_HELI_ID` | §3.D |
| Copal 1 ring OD and thickness | `NW_CLEAR`, `NW_BOARD` | §3.D |
| Nikkor-W barrel OD at the clamp land (73?) | `NW_D_TUBE` | ISCO clamp |

---

## 8. Documentation drift (README / PLAN / bom vs code)

| doc says | code does |
| --- | --- |
| PATH 179.5–193.5, infinity at helicoid 17.5 against 180 | `EL_FFD = 158.5`; PATH 158–172; seats recessed |
| standoff 16 mm, 3 mm to twist on | 13.5 mm, 0.5 mm (non-W); 21.5 mm (W) |
| printed F 43.5 mm / f/9.2 | `F_STL_THROAT = 40`, f/30; mesh not bored |
| "cookies flange on the bed, camera mouth up" | printed-F cookies have a 45° bed face (`cookie_print_flat`) |
| stem "cookie flange on the bed, M62 boss up" | `stem_bed_chamfer` intends a 45° print |
| badge inlays in the chassis wall, 10 mm wall, 7 mm behind the pocket | badge on a 4 mm screw-in cookie, 1.5 mm behind the pocket, open frame behind |
| chassis floor "solid slab" (code comment) | honeycomb open to the chamber |
| `export_fxpan.sh`: 75×75 plate, F_BORE 43.5 | 50×75, F_BORE 44 |
| bom: "M62 helicoid … do not substitute a longer one" | true, and also do not accept a wider one (§3.D) |
| Nikkor-W not mentioned in README/PLAN at all | `STEM=2`, `stem_w`, `stem_nw180`, `arm_*_w/fw/hw`, `W_ARM_EXTRA` |

---

## 9. How to verify each fix

```sh
O=/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD
cd openscad/fxpan

# Echo the W build's numbers (after adding the §4.6 echoes)
$O -o /tmp/x.echo -D 'PART="shims"' -D ARM_MOUNT=1 -D STEM=2 WATCH_ME.scad; cat /tmp/x.echo

# Top view with the (new) asymmetric ghosts — look at the +X+Y corner
$O --preview -o /tmp/top.png --projection=o --imgsize=1600,1600 \
   --camera=40,40,0,0,0,0,560 -D ARM_MOUNT=1 -D STEM=2 -D SHOW_GHOSTS=1 -D SHOW_LID=0 WATCH_ME.scad

# Base pad vs register: must print 0 after the §3.C fix
#   echo(base_cam_d() - (d_plate_to_mount() + arm_extra() + d800_tripod_in()));

# Mouth f-stop after re-boring or setting F_THROAT from a measured ring
#   look for "mouth: ... corner-to-corner from f/…" in the echo

# Ray trace still agrees (update FSTOP claims in fxpan_paths.py if F_THROAT changes)
python ../../kraken/fxpan_paths.py

# Export just the W parts
./export_fxpan.sh stem_w stem_nw180 arm_r_fw arm_t_fw base cradle_r cradle_t
```

Acceptance for "will it work": a D800 twists onto each arm with the other
body in place (§3.B), the 1/4-20 sits mid-slot (§3.C), the Copal ring runs
down ≥ 2.5 mm of thread (§3.D), the echo says infinity margin ≥ 1.5 mm, and
a flat wall at f/11 shows no straight-edged corner shading on either sensor
(§3.A, §4.4).
