// Nikon Dual — FXPAN 65: two D800 behind one EL-Nikkor 180/5.6 and a
// 75×75×1 50/50 plate. 64.80 × 23.9 mm stitch, 2.711:1 (XPan is 2.708:1),
// 13248 × 4912 = 65.1 MP. Infinity inside the helicoid's travel, and the
// frame corner-to-corner clean from f/8.4.
// Lens −Y. Plate at the origin: R → +X, T → +Y. No tube toe.
// https://www.edmundoptics.com/p/75-x-75mm-50-50rt-vis-plate-beamsplitter/37202/
//
// Three things drive every number here, and they pull against each other.
// kraken/fxpan_paths.py ray traces all of it and fails loudly if any of these
// stops holding.
//
// 1. A plate tilted 45° presents only size/√2 across its plane of incidence,
//    and cam/pano.py needs landscape sensors with a horizontal seam, so the
//    wide stitch axis is forced onto exactly that foreshortened dimension.
//    The 65 mm frame needs 44.7 mm there at f/5.6. A 50 mm plate gives 35.36
//    and clips the stitch axis until f/11; a 75 mm plate gives 53.03, an 18%
//    margin that grows as you stop down. So: 75 mm plate.
//
// 2. The F throat has to pass the frame CORNERS, and mostly can't — this is
//    the constraint that actually limits the body. 44 mm is the real Nikon F
//    throat and no printed part beats it, against the 46.8 mm the corners
//    need at f/5.6. So the frame is fully lit from f/8.4, not f/5.6; wide of
//    that the corners shade while the stitch axis stays clean. See need_bore()
//    for why this must be worked at the corner and not along the stitch axis.
//
// 3. PATH_TOTAL — lens flange to sensor along the fold — has to land on the
//    EL-Nikkor's 180 mm flange focal distance. The path is
//      BOX_XY + 2·PORT_PATCH_T + arm tube + mount stack + FLANGE_F
//      + stem M62 boss + helicoid
//    so every millimetre of chassis costs two millimetres of budget. This is
//    why the chamber is NOT a cube: a cube tall enough for a 75 mm plate on
//    its diagonal is 111 mm, which puts the shortest possible path at 207 mm
//    and makes infinity unreachable. BOX_Z carries the plate; BOX_XY is set
//    by the path budget and only has to clear the shifted port windows.
//
// BS_SIZE = 50 still builds — BOX_Z follows it — but it clips the stitch axis
// itself until f/11, which is worse than the corner shading above because it
// eats the ends of the panorama. See bom.md.

FLANGE_F = 46.5;
EL_FOCAL = 180.0;   // EL-Nikkor 180/5.6N; PATH_TOTAL must reach this

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

PORT_PATCH     = 90;
PORT_PATCH_T   = 4;
function patch_t() = PORT_PATCH_T;

// --- beamsplitter ----------------------------------------------------------
// 1.00 mm only. A tilted plate puts astigmatism on the transmit path alone
// (S1 faces the lens, so the reflect path never enters glass): 0.172 mm at
// 1 mm, inside the 0.224 mm depth of focus at f/5.6. A 3 mm plate is
// 0.515 mm and would need f/16.
BS_SIZE  = 75;
BS_THICK = 1.0;
BS_CLEAR = 0.35;
BS_N     = 1.52;
function bs_in_plane() = BS_SIZE / sqrt(2);
function bs_t_comp() =
    let (ti = 45, tt = asin(sin(ti) / BS_N))
        BS_THICK * (BS_N / cos(tt) - 1 / cos(ti));   // 0.303 mm

// --- camera mouth ----------------------------------------------------------
F_REV_MAJOR    = 52.0;    // M52×0.75, Fotodiox 52 mm F reverse ring
F_REV_PITCH    = 0.75;
F_REV_LEN      = 8;
F_REV_STACK    = 8;       // ring thickness: tube end → F register
F_REV_TOL      = 0.12;
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
F_FMOUNT_STACK = 1.75;
F_PEG_H        = 5.5;
FX_FMOUNT_EXTRA = 5.0;
ARM_TUBE        = 5.0;    // tube past the cookie; the M52 female needs ~8 mm
                          // of material and the cookie only gives 4

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
EL180_STEM_OD   = 82;
EL180_LENS_OD   = 76;
EL180_LENS_L    = 62.6;
EL180_SNOUT_D   = 40;
STEM_BORE       = 40;     // rear cell clears; the bundle needs 37 mm here

// --- chassis ---------------------------------------------------------------
// BOX_Z carries the plate: cartridge frame + retention posts + lid shelf.
CARTRIDGE_WALL = 4.5;
POST_H         = 8.0;
LID_LIP_SEAT   = 3;
function frame_top_z() = (BS_SIZE + BS_CLEAR * 2) / 2 + CARTRIDGE_WALL;
function box_z_calc()  = ceil(2 * (frame_top_z() + POST_H + LID_LIP_SEAT + 0.5));
BOX_Z = box_z_calc();     // 108 at BS_SIZE 75, 84 at 50

// BOX_XY comes out of the path budget. Working backwards from PATH_TOTAL at
// the helicoid's collapsed end:
//   PATH = BOX_XY + 2·patch + ARM_TUBE + F_REV_STACK + FLANGE_F
//          + EL180_M62_LEN + (EL180_HELI_MIN − EL180_HELI_MALE)
// Solved and rounded DOWN to a whole mm, because the shims can only ever add
// length — a chassis 1 mm too big can never reach infinity.
function box_xy_path() =
    floor(EL_FOCAL - (2 * PORT_PATCH_T + ARM_TUBE + F_REV_STACK + FLANGE_F
                      + EL180_M62_LEN + (EL180_HELI_MIN - EL180_HELI_MALE)));
// Floor: the shifted port window has to land inside the chamber, with a
// couple of mm of wall left beside it.
function box_xy_ports() = 2 * (sensor_shift() + (TUBE_ID + 0.6) / 2 + WALL + 2);
BOX_XY = max(box_xy_path(), box_xy_ports());   // 94

// Now the path follows from the geometry instead of being asserted, so the
// echo() report is the real number and not a wish.
function d_plate_to_mount() =
    BOX_XY / 2 + patch_t() + ARM_TUBE + F_REV_STACK;
function path_after_plate() = d_plate_to_mount() + FLANGE_F;
function d_plate_to_flange(heli) =
    BOX_XY / 2 + patch_t() + EL180_M62_LEN + (heli - EL180_HELI_MALE);
function path_total(heli)   = d_plate_to_flange(heli) + path_after_plate();
function path_min()         = path_total(EL180_HELI_MIN);
function path_max()         = path_total(EL180_HELI_MAX);
// Helicoid extension that puts the lens at infinity.
function heli_at_infinity()  = EL180_HELI_MIN + (EL_FOCAL - path_min());
// Printed stand-in for the bought helicoid: a fixed spacer at infinity.
function el180_spacer_add() = EL_FOCAL - path_min() + EL180_HELI_MIN
                              - EL180_HELI_MALE;

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
PORT_SLOT_CLEAR = 0.4;
PORT_RETAIN     = 4;
PORT_BOSS_R     = 14;
PORT_SCREW_R    = 38.5;
PORT_CLAMP_R    = 38;
PORT_CLAMP_SEP  = 15;
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
function clamp_xy(mark, side, sh = undef) =
    let (ax = cam_axis(mark, sh), u = port_up(mark), v = [-u.y, u.x])
        [ax.x + u.x * PORT_CLAMP_R + v.x * side * PORT_CLAMP_SEP,
         ax.y + u.y * PORT_CLAMP_R + v.y * side * PORT_CLAMP_SEP];
PORT_SCREW_D = 3.2;
PORT_HEAD_D  = 6.4;
PORT_HEAD_H  = 3.4;
PORT_NUT_AF  = 5.7;
PORT_NUT_T   = 2.6;

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
function d800_tripod_above() =
    is_undef(D800_TRIPOD_ABOVE) ? 10.0 : D800_TRIPOD_ABOVE;
function d800_tripod_in() =
    is_undef(D800_TRIPOD_IN) ? 44 : D800_TRIPOD_IN;
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
CRADLE_WALL     = 5;
CRADLE_H        = 26;     // up the body side from the plinth
CRADLE_PAD_T    = 2.4;    // TPU / cork facing pocket

// --- shell, light trap, marks ---------------------------------------------
INNER_LINING = 1.6;
FLOOR_SKIN   = 0;
MARK_DEPTH   = 1.2;   // FXPAN badge + 65MP on the blank −X wall
// Colour plugs vs the pocket they drop into. Matching them exactly leaves the
// slicer two coincident faces per surface and it renders the pair as garbage,
// so the plugs bite into the pocket and stand off the wall.
LOGO_FIT     = 0.08;
LOGO_PROUD   = 0.06;
// The lockup was drawn for the 90 mm hybrid box; scale it to this wall.
// Applied inside the plug fit, so LOGO_FIT and LOGO_PROUD stay in real mm.
LOGO_SCALE   = 1.15;
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
