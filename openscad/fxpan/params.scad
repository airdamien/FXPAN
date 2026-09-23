// Nikon Dual — FXPAN 65: two D800 behind one EL-Nikkor 180/5.6 and a
// 50×75×1 50/50 plate. 64.80 × 23.9 mm stitch, 2.711:1 (XPan is 2.708:1),
// 13248 × 4912 = 65.1 MP. Infinity inside the helicoid's travel, and the
// frame corner-to-corner clean from f/8.4.
// Lens −Y. Plate at the origin: R → +X, T → +Y. No tube toe.
// https://www.edmundoptics.com/p/50-x-75mm-50-50rt-vis-plate-beamsplitter/37201/
//
// Four things drive every number here, and they pull against each other.
// kraken/fxpan_paths.py ray traces all of it and fails loudly if any of these
// stops holding.
//
// 1. A plate tilted 45° presents only size/√2 across its plane of incidence,
//    and cam/pano.py needs landscape sensors with a horizontal seam, so the
//    wide stitch axis is forced onto exactly that foreshortened dimension.
//    The 65 mm frame needs 44.4 mm there at f/5.6, so BS_W has to be 75:
//    53.03 presented, a 19% margin that grows as you stop down. 50 there
//    gives 35.36 and clips the stitch axis until f/11.
//
// 2. The F throat has to pass the frame CORNERS, and mostly can't — this is
//    the constraint that actually limits the body. 44 mm is the real Nikon F
//    throat and no printed part beats it, against the 46.8 mm the corners
//    need at f/5.6. So the frame is fully lit from f/8.4, not f/5.6; wide of
//    that the corners shade while the stitch axis stays clean. See need_bore()
//    for why this must be worked at the corner and not along the stitch axis.
//
// 3. PATH_TOTAL — lens flange to sensor along the fold — has to land on the
//    EL-Nikkor's 158.5 mm flange focal distance. 180 mm is the focal length,
//    used for the bundle, not the register. The seats are recessed into the
//    lens wall and the camera cookies sit CAM_RECESS deeper, so the path is
//    the seat position plus the shortened camera stack, not a boss standing
//    on the skin. BOX_Z carries BS_H and nothing else; BOX_XY stays on the
//    port floor. Shrinking it does not reach the register.
//
// 4. A D800 is not flat at its flange. Its front panel stands D800_PROUD
//    past the register, and it goes on by pushing that panel at the chassis
//    and twisting to lock. So the register has to stand off the chassis face
//    by at least that much or the body simply cannot be fitted — and the
//    body is wider than the chassis, so there is nowhere to relieve locally.
//    The standoff is ARM_TUBE + F_REV_STACK and nothing else, which is why
//    ARM_TUBE is solved from the camera and BOX_XY gets what is left.
//
// BS_W = 50 still builds — the tray follows it — but it clips the stitch axis
// itself until f/11, which is worse than the corner shading above because it
// eats the ends of the panorama. BS_H = 50 costs nothing. See bom.md.

FLANGE_F = 46.5;
EL_FOCAL = 180.0;   // focal length: bundle, baffles, mouth. Not the register.
EL_FFD   = 158.5;   // flange focal distance, sheet. Path target.

// D800 FX only. 20% overlap lands the stitch on the XPan aspect.
SENSOR_W      = 36.0;
SENSOR_H      = 23.9;
SENSOR_PX_W   = 7360;
SENSOR_PX_H   = 4912;
function overlap_frac()  = 0.20;
function sensor_shift()  = SENSOR_W / 2 * (1 - overlap_frac());   // 14.40
function stitch_w()      = SENSOR_W * (2 - overlap_frac());       // 64.80
function stitch_px()     = round(SENSOR_PX_W * (2 - overlap_frac()));
function stitch_aspect() = stitch_w() / SENSOR_H;                 // 2.711
// Untilted tubes; each bore is translated by sensor_shift() instead.
function field_toe()     = 0;

// --- tubes -----------------------------------------------------------------
// TUBE_ID passes the 48.2 mm the frame corners need at the box wall from
// f/6.95, so it is never the binding aperture -- the 44 mm F throat is.
TUBE_ID  = 46;
TUBE_OD  = 58;
WALL     = (TUBE_OD - TUBE_ID) / 2;   // 6

PORT_PATCH_T   = 4;
function patch_t() = PORT_PATCH_T;

// --- beamsplitter ----------------------------------------------------------
// Edmund #37201 (stock #35-947), 50 × 75 × 1.0, 50/50 VIS, S2 AR.
//
// The plate's two directions do completely different jobs, so it does not
// want to be square. Across the plane of incidence it is foreshortened by
// √2 and that is the direction the 64.80 mm stitch has to cross: 75 there
// presents 53.03. Along the fold there is no foreshortening and nothing to
// carry but the 23.9 mm sensor height, which needs 29.05 at f/5.6, so 50 is
// already +72%. Edmund cut it for exactly this — their note on the
// rectangular plates is that they square up at 45°, and 75/√2 = 53.0 ≈ 50.
//
// BS_H is the one that costs: it sets BOX_Z, and the 75 × 75 was carrying
// 25 mm of chamber height for a margin nothing needed.
//
// 1.00 mm only. A tilted plate puts astigmatism on the transmit path alone
// (S1 faces the lens, so the reflect path never enters glass): 0.172 mm at
// 1 mm, inside the 0.224 mm depth of focus at f/5.6. A 3 mm plate is
// 0.515 mm and would need f/16, and Edmund's 50 × 75 in the other family
// (#17536) is exactly that — check the thickness, not just the size.
BS_W     = 75;    // across the plane of incidence; carries the stitch
BS_H     = 50;    // along the fold; carries the sensor height, and BOX_Z
BS_THICK = 1.0;
BS_CLEAR = 0.35;
BS_N     = 1.52;
function bs_in_plane() = BS_W / sqrt(2);
function bs_t_comp() =
    let (ti = 45, tt = asin(sin(ti) / BS_N))
        BS_THICK * (BS_N / cos(tt) - 1 / cos(ti));   // 0.303 mm

// --- camera mouth ----------------------------------------------------------
F_REV_MAJOR    = 52.0;    // M52×0.75, Fotodiox 52 mm F reverse ring
F_REV_PITCH    = 0.75;
F_REV_LEN      = 8;
F_REV_STACK    = 8;       // ring thickness: tube end → F register
// The thread profile, not the clearance, is why the older arms never took a
// ring. lib/threads.scad cuts a sharp full-height V: at P = 0.75 that is
// 0.650 mm of radial depth, against the 0.406 mm an ISO M52×0.75 female
// actually has. The printed crests stand a quarter of a millimetre proud
// into the ring's thread roots, so the ring bottoms on them before its
// flanks touch anything, rocks on that line contact and cross-threads — it
// feels exactly like a bore that is too big. Truncate the crest back to the
// real minor and put the clearance on the major instead.
//
// F_REV_CLEAR is the one number to tune. Print PART=ringgauge first: it is
// four 7 mm rings at ±0.15 mm around this value, ten minutes on the bed,
// and it tells you what your printer wants before you commit to an arm.
F_REV_CLEAR    = 0.15;    // diametral clearance on the 52.0 major
F_REV_TOOTH    = 0.52;    // axial tooth base → 0.450 mm radial, ISO-ish
F_REV_LEAD     = 0.9;     // 45° lead-in so the first turn starts square
F_REV_GAUGE    = [-0.15, 0, 0.15, 0.30];   // ringgauge steps about F_REV_CLEAR
function f_rev_minor() = F_REV_MAJOR + F_REV_CLEAR - F_REV_TOOTH / tan(30);
// Set-screw lock on the ring barrel: see REV_LOCK_* under ports.
// Flush with the metal reverse ring's throat, so the printed part is never the
// limit and the bought ring is. 43.5 cost a third of a stop for nothing. The
// other bodies use 40.3, which clips a 14.4 mm shift badly.
//
// 44 mm is also the ceiling: it is the real Nikon F throat, and no printed
// part can beat it. See need_bore() for what that costs -- the full 64.80 mm
// frame is corner-to-corner clean from f/8.4, not from f/5.6. Buying a bigger
// plate fixed the plate; nothing fixes the F mount.
F_BORE         = 44.0;
F_THROAT       = 44.0;    // metal M52 -> F reverse ring = a real F throat
F_COLLAR_OD    = 62;      // F bayonet collar, and the cap on the lock lugs
F_FMOUNT_STACK = 3.0;  // Archive-663 lens mount: register is 3 mm from the back
F_PEG_H        = 5.5;
FX_FMOUNT_EXTRA = 5.0;
// --- how far the body has to stand off the chassis -------------------------
// The D800's front panel reaches D800_PROUD past its own F flange, and the
// body has to go on by sliding that panel toward the chassis and twisting.
// So the F register must sit at least that far outside the chassis face or
// the camera physically will not mount.
//
// Everything between the chassis face and the register is arm tube and
// reverse ring, and the chassis half-width cancels:
//     standoff = ARM_TUBE + F_REV_STACK − (shell outboard of the cookie)
// The shell outboard of the cookie is now zero — see chassis_shell_t() — so
// the arm tube is what buys the standoff, and it is solved from the body
// rather than picked. BOX_XY then takes whatever the path budget has left.
// D800_PROUD is the customizer knob in WATCH_ME.scad; measure yours.
function d800_proud() = is_undef(D800_PROUD) ? 13.0 : D800_PROUD;
MOUNT_CLEAR = 3.0;    // what the 16 mm standoff used to leave in front of a D800
// Spent on the register. The arm tube stays F_REV_LEN; the cookies sit this
// much deeper, so the body clears the skin by MOUNT_CLEAR − CAM_RECESS.
CAM_RECESS = 2.5;
// Also has to be deep enough to hold the whole M52 female.
ARM_TUBE = max(F_REV_LEN, d800_proud() + MOUNT_CLEAR - F_REV_STACK);

// --- EL-Nikkor 180/5.6N on an M62×1 helicoid -------------------------------
// The stem carries a short M62 female boss and nothing else. hybrid_shift's
// 20 mm nut would eat the whole focus budget: 20 + 17 of helicoid puts the
// shortest path at 207 mm. An 8 mm boss lets the bought helicoid's male
// bottom straight onto the cookie.
EL180_M62_MAJOR = 62;
EL180_M62_PITCH = is_undef(EL180_M62_PITCH) ? 1.0 : EL180_M62_PITCH;
EL180_M62_LEN   = 8;      // female boss on the cookie = the whole stem
EL180_M62_TOL   = 0.45;
// Pixco-style M62×1 helicoid: 17 mm overall collapsed, 31 mm open, of which
// ~8 mm is its own male thread. So it adds (len − male) past the boss face.
EL180_HELI_MIN  = 17;
EL180_HELI_MAX  = 31;
EL180_HELI_MALE = 8;
EL180_ADAPTER_OD = 76;
EL180_BORE      = EL180_M62_MAJOR - 1.6;
EL180_BARREL    = 61.2;   // 60 mm measured barrel + clearance
EL180_PAST      = 9.2;    // that barrel, past the 8 mm mount thread
// The boss was 82 across and nothing asked it to be. An M62×1 female needs
// a wall, not a flange: the helicoid bottoms on the cookie's face, not on
// this, so the only load it takes is the thread's own hoop. At 82 it reached
// r 41 against clamp screws at 40.85, so the countersinks came out inside its
// footprint with 8 mm of thread standing over them — you could start a screw
// and then not turn it. It also set how wide the stem cookie had to be.
//
// So take the wall as the number and check it clears the heads rather than
// the other way round.
EL180_M62_WALL  = 4;
function el180_stem_od() =
    min(EL180_M62_MAJOR + 2 * EL180_M62_WALL,
        2 * (norm(clamp_xy("", 1, 1)) - PORT_CSK_D / 2 - 1.0));
EL180_LENS_OD   = 76;
EL180_LENS_L    = 62.6;
EL180_SNOUT_D   = 40;
STEM_BORE       = 40;     // rear cell clears; the bundle needs 37 mm here

// --- chassis ---------------------------------------------------------------
// BOX_Z carries the plate: cartridge frame + retention posts + lid shelf.
CARTRIDGE_WALL = 4.5;
POST_H         = 8.0;
LID_LIP_SEAT   = 3;
function frame_top_z() = (BS_H + BS_CLEAR * 2) / 2 + CARTRIDGE_WALL;
function box_z_calc()  = ceil(2 * (frame_top_z() + POST_H + LID_LIP_SEAT + 0.5));
BOX_Z = box_z_calc();     // 83 at BS_H 50, 108 at 75

// The port floor already wins. Recessing the seats is what reaches EL_FFD;
// shrinking BOX_XY does not, and the shifted windows still need this width.
function box_xy_path() =
    floor(EL_FOCAL - (2 * PORT_PATCH_T + ARM_TUBE + F_REV_STACK + FLANGE_F
                      + EL180_M62_LEN + (EL180_HELI_MIN - EL180_HELI_MALE)));
// Floor: the shifted port window has to land inside the chamber, with a
// couple of mm of wall left beside it.
function box_xy_ports() = 2 * (sensor_shift() + (TUBE_ID + 0.6) / 2 + WALL + 2);
BOX_XY = max(box_xy_path(), box_xy_ports());   // 92, against a 91.4 port floor

// Stem frame: z = 0 on the BOX_XY face, +z outward. Skin at +patch, air at −WALL.
// A flange at `path` sits at flange_z. The helicoid's collapsed 9 mm stays in
// the path, so its nut is deeper than the infinity seat by that 9 mm.
// HELI_SHORT keeps infinity 0.5 mm off the collapsed stop. Shims only add.
HELI_SHORT = 0.5;
function d_plate_to_mount() =
    BOX_XY / 2 + patch_t() + ARM_TUBE + F_REV_STACK - CAM_RECESS;
function path_after_plate() = d_plate_to_mount() + FLANGE_F;
function flange_z(path) = path - path_after_plate() - BOX_XY / 2;
function path_heli(heli) = EL_FFD - HELI_SHORT + (heli - EL180_HELI_MIN);
function inf_seat_z() = flange_z(EL_FFD);
function heli_flange_z(heli) = flange_z(path_heli(heli));
// Male bottoms here. The 8 mm female runs outward from this face.
function heli_bottom_z() = heli_flange_z(EL180_HELI_MIN) - EL180_HELI_MIN;
function heli_boss_z() = heli_bottom_z() + EL180_HELI_MALE;
function d_plate_to_flange(heli) = BOX_XY / 2 + heli_flange_z(heli);
function path_total(heli)   = d_plate_to_flange(heli) + path_after_plate();
function path_min()         = path_total(EL180_HELI_MIN);
function path_max()         = path_total(EL180_HELI_MAX);
function path_inf()         = d_plate_to_flange_inf() + path_after_plate();
function d_plate_to_flange_inf() = BOX_XY / 2 + inf_seat_z();
// Helicoid extension that puts the lens at infinity.
function heli_at_infinity()  = EL180_HELI_MIN + (EL_FFD - path_min());
// Air between the chassis skin and the F register. The cookies moved in by
// CAM_RECESS; the skin did not.
function mount_standoff() = ARM_TUBE + F_REV_STACK - CAM_RECESS;
function mount_standoff_ok() = mount_standoff() >= d800_proud();
// Clamp screws cap a nut at about 75 mm. 74 leaves a millimetre, and the
// passage is 2 mm of wall under that. A bought helicoid body has to be
// under HELI_PASS to reach the female. A fatter one means moving the screws.
HELI_NUT_OD = 74;
function heli_pass_d() = HELI_NUT_OD - 4;
// Printed stand-in for the bought helicoid: male plus enough shank that the
// lens flange lands on the infinity seat.
function el180_spacer_add() =
    inf_seat_z() - heli_bottom_z() - EL180_HELI_MALE;

// --- optics envelope -------------------------------------------------------
// Exit pupil at the lens, EL_FOCAL from the sensor. At a station d ahead of
// the sensor the bundle envelope for a field half-width ym is
//   ym·(P−d)/P + (P/2N)·(d/P).
// It is largest at the sensor and shrinks toward the lens, so stopping down
// only ever helps and the plate wants to be as far forward as it will go.
function pupil_d(fstop) = EL_FOCAL / fstop;
function bundle_r(ym, fstop, d) =
    ym * (EL_FOCAL - d) / EL_FOCAL + pupil_d(fstop) / 2 * (d / EL_FOCAL);
// Whole frame, both sensors. The plate is a square, so its two directions are
// independent: across the fold it carries the stitch axis, along the fold only
// the sensor height.
function need_clear(fstop, d)   = 2 * bundle_r(stitch_w() / 2, fstop, d);
function need_clear_v(fstop, d) = 2 * bundle_r(SENSOR_H / 2, fstop, d);

// One camera, as a round bore centred on its own shifted mount axis.
//
// This has to be worked at the frame CORNER, not along the stitch axis. A
// bore is round, so what matters is distance from the axis, and the corner
// of a 36 x 23.9 window is 21.6 mm from its centre against the 18 mm the
// stitch axis alone would suggest. Reading it off the stitch axis understates
// the bore by 3.4 to 4.3 mm, which is the difference between believing the
// frame is clean at f/5.6 and it actually being clean at f/8.4.
//
// At station b the corner's bundle is centred at
//   c = corner·(P−b)/P + shift·(b/P)
// and has radius (P/2N)·(b/P) about that. The binding corner is the one on
// the same side as the shift.
function _bore_cu(fstop, b) =
    SENSOR_W / 2 * (EL_FOCAL - b) / EL_FOCAL + sensor_shift() * (b / EL_FOCAL);
function _bore_cv(fstop, b) = SENSOR_H / 2 * (EL_FOCAL - b) / EL_FOCAL;
function need_bore(fstop, b) =
    2 * (norm([_bore_cu(fstop, b), _bore_cv(fstop, b)])
         + pupil_d(fstop) / 2 * (b / EL_FOCAL));
// Same thing along the stitch axis only, for comparison against the other
// bodies' numbers. Not a design limit; the corner is.
function need_bore_u(fstop, b) =
    2 * (_bore_cu(fstop, b) + pupil_d(fstop) / 2 * (b / EL_FOCAL));

// --- ports -----------------------------------------------------------------
PORT_FRAME      = 5;
PORT_SLOT_LIP   = 8;
PORT_SLOT_CLEAR = 0.6;   // the rebate is closed on all four sides now
// A cookie is a square 90 on a side and it has no business being one. It is
// centred on the face while everything it carries — the bore, the tube, the
// four clamp screws, the two lock lugs — is centred on cam_axis(), 14.4 mm
// off it. So the plate reaches 45 mm to catch a tube that ends at 43.4 on one
// side, and spends the other 25 mm reaching out over nothing at all.
//
// Centre it on the bore instead and size each direction from what is actually
// out there. Along camera-up that is the clamp screws; across, the tube OD or
// a lock lug, whichever is wider. Both are one rim short of the last feature.
PORT_PLATE_RIM  = 2.0;
function port_patch_u() =                              // along camera-up
    2 * (port_clamp_r() + PORT_CSK_D / 2 + PORT_PLATE_RIM);
function port_patch_v(mark = "") =                     // across it
    2 * PORT_PLATE_RIM + (mark == ""
        ? max(el180_stem_od(), EL180_LENS_OD)          // seat has to catch the Ø76
        : 2 * max(TUBE_OD / 2, rev_lock_reach_v()));
PORT_PLATE_R    = 6;     // corner of the seam, cosmetic
// The chassis corner has to stay behind the cookie, and a 14 mm one does not.
// A cookie's outboard edge lands 45.4 mm off the middle of its face, by which
// point a 14 mm corner has curved 3.3 mm away — so the plate hangs over air,
// and the rebate behind it takes the corner off the chassis as well. Whatever
// the chassis has receded at that edge is exactly how proud the plate stands.
//
// Hold that inside PORT_EDGE_CHAM and the mismatch disappears into the
// chamfer the cookie already has. R − √(R²−d²) ≤ c at d = R − 4.6 solves to
// R ≤ 9.12, so: 9. Still a corner you can see; diagnostics() reports what it
// costs and says so if anything here moves.
PORT_BOSS_R     = 9;
function chassis_face_at(v) =
    let (o = (BOX_XY + 2 * PORT_PATCH_T) / 2,
         f = o - PORT_BOSS_R,
         d = min(PORT_BOSS_R, max(0, abs(v) - f)))
        f + sqrt(PORT_BOSS_R * PORT_BOSS_R - d * d);
function port_edge_proud() =
    (BOX_XY + 2 * PORT_PATCH_T) / 2
    - chassis_face_at(sensor_shift() + port_patch_v("R") / 2);
// 45° off the outer edge. The cookie prints arm-up, so the outer face is the
// last thing off the bed and a chamfer there only ever narrows — the bed face
// stays the full flat plate.
PORT_EDGE_CHAM  = 1.2;
PORT_SCREW_R    = 38.5;
// Outside the tube and outside a lock lug, by a countersink and a little.
function port_clamp_r() =
    max(TUBE_OD / 2, rev_lock_reach_u()) + PORT_CSK_D / 2 + 1.5;
// Spread wide rather than tucked in beside the bore. It is a better clamp on
// a plate this size, and on the stem face it is what leaves the M62 boss
// somewhere to stand: at ±15 the 82 mm boss overhung both screws.
PORT_CLAMP_SEP  = 25;
// cam_axis() centres the bore off the face, so ±SEP parks two screws past the
// flat and into the rounded corner — no wall left there for a trapped M3 nut.
// Pull only those two inboard; the stem face is centred and does not need it.
PORT_CLAMP_CORNER_INSET = 13;
function clamp_across_sep(mark, side, up = 1) =
    let (u = port_up(mark) * up, v = [-u.y, u.x],
         outbound = mark == "R" ? (v.y * side < 0)
                    : mark == "T" ? (v.x * side > 0)
                    : false)
        PORT_CLAMP_SEP - (outbound ? PORT_CLAMP_CORNER_INSET : 0);
// R and T shift in opposite senses so the two sensors sample opposite halves
// of the field. Which one ends up image-left is settled by find_overlap() and
// flip_r in cam/pano.py, not here.
function cam_axis(mark, sh = undef) =
    let (s = is_undef(sh) ? sensor_shift() : sh)
        mark == "R" ? [0, -s] :
        mark == "T" ? [s, 0] : [0, 0];
function port_up(mark) =
    mark == "R" ? [-1, 0] :
    mark == "T" ? [0, -1] : [0, 1];
// Same thing as an azimuth about the tube, for the mouth features that clock
// off camera-up: the lock-pin line and the set-screw pads.
function port_up_az(mark) =
    let (u = port_up(mark)) atan2(u.y, u.x);
// Four per cookie, two above the bore and two below. With the outboard
// retaining wall gone (it was what the camera's front panel hit) these are
// the only thing holding a cookie out of its rebate, so they are no longer
// a pair on the lid side alone.
function clamp_xy(mark, side, up = 1, sh = undef) =
    let (ax = cam_axis(mark, sh), u = port_up(mark) * up, v = [-u.y, u.x],
         sep = clamp_across_sep(mark, side, up))
        [ax.x + u.x * port_clamp_r() + v.x * side * sep,
         ax.y + u.y * port_clamp_r() + v.y * side * sep];
PORT_SCREW_D = 3.2;
PORT_HEAD_D  = 6.4;
PORT_HEAD_H  = 3.4;
PORT_NUT_AF  = 5.7;
PORT_NUT_T   = 2.6;
// M3 DIN 7991 flat head. The cookie face is now the outside of the body, so
// the heads sink flush into it instead of into a counterbore in a wall that
// no longer exists — a 3.4 mm cap head would leave 0.6 mm of a 4 mm cookie,
// and stand in the camera's way besides.
PORT_CSK_D   = 6.4;
PORT_CSK_H   = 1.9;

// --- reverse-ring lock -----------------------------------------------------
// Two M3 grub screws pinch the ring barrel and hold its clock.
//
// There is no meat in the tube wall for this. An M3 nut wants 2.8 mm of radial
// depth and the wall left over the M52 female is (TUBE_OD − F_REV_MAJOR)/2 =
// 3.0 mm, so a pocket sunk into it has to come out the other side, and the old
// one did: it opened a 5.7 mm window straight through the thread, twice, over
// 7 of the 8 mm of engagement. Two gaps for the ring to jump on every turn,
// which cannot have helped the threading either.
//
// So the nut goes outboard of the thread, in a lug that stands proud of the
// OD, and only the 3.2 mm screw crosses the thread. The lug stops at the
// reverse ring's own OD: whatever it is, it is then never proud of the metal
// ring that already has to live in the gap between the chassis and the
// camera's front panel, which is the only clearance statement that can be made
// about that panel without measuring it. Meat comes from flaring the lug down
// onto the cookie instead of from standing it further out.
REV_LOCK_WALL   = 1.2;                  // over the nut, outboard
REV_LOCK_NUT_T  = PORT_NUT_T + 0.2;
REV_LOCK_NUT_AF = PORT_NUT_AF + 0.25;
REV_LOCK_W      = 13.0;                 // lug width at the mouth, tangential
REV_LOCK_FLARE  = 3.0;                  // extra half-width down at the cookie
function rev_lock_r_out() = F_COLLAR_OD / 2;
function rev_lock_r_in()  = rev_lock_r_out() - REV_LOCK_WALL - REV_LOCK_NUT_T;
// Wall left between the nut pocket and the thread. It is not the loaded face
// — driving the screw in reacts the nut outboard, against REV_LOCK_WALL — but
// diagnostics() reports it, because it is what goes first if F_REV_CLEAR or
// F_COLLAR_OD ever move.
function rev_lock_thread_wall() =
    rev_lock_r_in() - (F_REV_MAJOR + F_REV_CLEAR) / 2;

// Where the pair sits, measured off camera-up.
//
// Two things are already spoken for, and on both faces they sit the same way
// round: the prism rakes the OD back at camera-up (TUBE_FLASH_KEEP), and the
// cookie runs out of plate at the shift azimuth, which is +90° from camera-up
// on the R face and on the T face alike. That leaves the far side, and
// REV_LOCK_HOME bisects the half of it furthest from both. The screws used to
// sit at camera-up itself and 120° off it, so the first of the two had 1.4 mm
// of raked wall to work with.
// 225 was picked when the cookie was a 90 mm square and had room to spare on
// every side. It does not now: the plate is sized off the features, so a lug
// swung toward the shift azimuth is a lug the plate has to grow to cover. Sit
// the pair square about the edge furthest from the lid instead, which is the
// one azimuth neither the prism rake nor the shift has a claim on, and the
// two lugs then cost the same in both directions and nothing across.
REV_LOCK_HOME   = 180;
REV_LOCK_SPREAD = 90;
// A lug is a slab clipped to rev_lock_r_out(), so its corners land on that
// circle and nothing about it ever reaches further than the circle does.
function rev_lock_half_ang() =
    asin(min(0.99, (REV_LOCK_W / 2 + REV_LOCK_FLARE) / rev_lock_r_out()));
function rev_lock_edges() =
    let (h = rev_lock_half_ang())
        [for (s = [-1, 1], e = [-1, 1])
            REV_LOCK_HOME + s * REV_LOCK_SPREAD / 2 + e * h];
function rev_lock_reach_v() =
    rev_lock_r_out() * max([for (a = rev_lock_edges()) abs(sin(a))]);
function rev_lock_reach_u() =
    rev_lock_r_out() * max([for (a = rev_lock_edges()) -cos(a)]);

LID_T        = 6;
LID_LIP      = LID_LIP_SEAT;
LID_GAP      = 0.5;
LID_CAP      = 5;
LID_SCREW    = 5;
LID_NUT_DROP = 12;

// --- base and cradles ------------------------------------------------------
// A D800 is ~1 kg. The bayonet locates; the base carries.
TRIPOD_INSERT_D = 8.1;
TRIPOD_INSERT_L = 6.4;
TRIPOD_KEEP     = 1.2;
function tripod_hole_h() = min(WALL - TRIPOD_KEEP, TRIPOD_INSERT_L + 1.0);
// Where the lens axis sits above the camera's own baseplate. This is a
// property of the body, not of this design, so it is the thing to measure:
// stand a D800 on a flat surface and measure to the centre of the mount.
//
// Everything under the chassis is then solved from it, which matters because
// BOX_Z is not a free number — it follows BS_H, and BS_H just dropped 25 mm.
// The old knob was "1/4-20 above the chassis bottom", which reads off a datum
// that moves with the plate: shorten the chamber and the cameras rise with
// it, off the optical axis, for no reason anyone would notice in the model.
function d800_axis_base() = is_undef(D800_AXIS_BASE) ? 52.0 : D800_AXIS_BASE;
function d800_tripod_in() =
    is_undef(D800_TRIPOD_IN) ? 44 : D800_TRIPOD_IN;
// The cradle is a fixed plinth — enough for a 1/4-20 slot and four sunk M3
// heads — and the chassis grows a skirt to make up whatever is left between
// its own floor and the plane the cameras have to stand on.
CRADLE_T = 10;
function chassis_plinth() =
    max(PORT_SLOT_LIP, d800_axis_base() + CRADLE_T - BOX_Z / 2);
BASE_T          = 8;
BASE_WEB        = 24;
BASE_PAD_D      = 46;
BASE_SLOT_L     = 18;
BASE_SLOT_W     = 7;
BASE_SCREW_D    = 6.6;
BASE_HEAD_D     = 24;     // knurled 1/4-20 camera thumbscrew
BASE_HEAD_COUNTER_H = 4;
BASE_RT_ALONG   = 56;
BASE_RT_INSET   = 34;
BASE_HEX_D      = 8.6;
BASE_HEX_CELL   = 11;
// The cradle is a bare plinth: no uprights. The bayonet takes yaw and the
// 1/4-20 takes the weight, which is all a camera plate ever does, and an
// upright is one more thing in the way of getting the body onto the mount.

// --- shell, light trap, marks ---------------------------------------------
INNER_LINING = 1.6;
FLOOR_SKIN   = 0;
// Into the −X wall. 1.2 was three 0.4 mm perimeters and nothing else, so the
// plugs came out as skins. 2.4 is real meat. The wall is 10 mm here, so the
// pocket still leaves about 7 mm of chassis behind it.
MARK_DEPTH   = 2.4;
// Colour plugs vs the pocket they drop into. Matching them exactly leaves the
// slicer two coincident faces per surface and it renders the pair as garbage,
// so the plugs bite into the pocket and stand off the wall.
LOGO_FIT     = 0.08;
LOGO_PROUD   = 0.06;
// The lockup was drawn for the 90 mm hybrid box; scale it to this wall.
// The imported mark is sized to SPEC_W first, then this factor, so the
// spec lines and the artwork stay the same width. Applied inside the plug
// fit, so LOGO_FIT and LOGO_PROUD stay in real mm.
LOGO_SCALE   = 1.15;
// D3/D4/D5 red line around the plinth. Same bite as the wall type; fill it
// with chassis_logo_stripe (or paint). Depth is MARK_DEPTH.
STRIPE_LIFT  = 5.0;   // mm above the floor, so the bed layers stay solid
STRIPE_H     = 1.6;   // the painted line on a D3 is about this
BAFFLE_H     = 1.6;
BAFFLE_PITCH = 4.0;
// Glare stop in the F throat. The window has to pass the whole shifted
// bundle (21.3 mm off axis at f/5.6), so the clearance is wider than the
// other bodies'.
MASK_CLEAR   = 5.0;
MASK_T       = 1.4;

SHIM_STEPS = [0.2, 0.5, 1.0];

BODY_W = 146.0;
BODY_H = 123.0;
BODY_D = 81.5;

$fn = 96;
EXPLODED = 0;
SHOW_GHOSTS = 0;
