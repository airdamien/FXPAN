// Nikon Dual — hybrid_shift pano L (shifted DX or FX + one 50/50 plate)
// FX_MODE=0: D7000 DX, sensor_shift ~9.4 mm, stitch ~42.5 mm.
// FX_MODE=1: D800 FX, sensor_shift ~14.4 mm, stitch ~64.8 mm.
// Tubes stay square; each bore is translated by sensor_shift() so each
// sensor window sits on a half-field without Scheimpflug tilt.
// One uncut 50×50 plate at the origin: R → +X, T → +Y.
// https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/

// FX_MODE, D800_TRIPOD_* — WATCH_ME customizer or -D FX_MODE=1 on export.
function fx_mode() = is_undef(FX_MODE) ? 0 : FX_MODE;

FLANGE_F = 46.5;

D_LENS_TO_PLATE_LONG = 55;
D_LENS_TO_PLATE_F50  = 45;
D_LENS_TO_PLATE = (!is_undef(STEM) && STEM == 1)
    ? D_LENS_TO_PLATE_F50 : D_LENS_TO_PLATE_LONG;
D_PLATE_TO_MOUNT_LONG  = 72;
D_PLATE_TO_MOUNT_SHORT = 54;
D_PLATE_TO_MOUNT = (
    (!is_undef(ARMS) && ARMS)
    || (!is_undef(STEM) && STEM == 1)
    || (!is_undef(PART) && (
        PART == "arm_r_s" || PART == "arm_t_s"
        || PART == "arm_r_sf" || PART == "arm_t_sf"
    ))
) ? D_PLATE_TO_MOUNT_SHORT : D_PLATE_TO_MOUNT_LONG;
PATH_FOLD        = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;

SENSOR_W      = fx_mode() ? 36.0 : 23.6;
SENSOR_H      = fx_mode() ? 23.9 : 15.6;
OVERLAP_FRAC  = 0.20;
function path_after_knife()   = D_PLATE_TO_MOUNT + FLANGE_F;
function overlap_at_sensor()  = SENSOR_W * OVERLAP_FRAC;
function overlap_cross()      = overlap_at_sensor() * path_after_knife() / PATH_TOTAL;
function sensor_shift()       = SENSOR_W / 2 * (1 - OVERLAP_FRAC);
// Untilted tubes. Old hybrid toe was atan(sensor_shift / path_after_knife).
function field_toe()          = 0;
function stitch_w()           = SENSOR_W * (2 - OVERLAP_FRAC);

BS_SIZE    = 50;
BS_THICK   = 1.0;
BS_CLEAR   = 0.35;
BS_N       = 1.52;
function bs_t_comp() =
    let (ti = 45, tt = asin(sin(ti) / BS_N))
        BS_THICK * (BS_N / cos(tt) - 1 / cos(ti));

TUBE_ID       = 52;
TUBE_OD       = 68;
WALL          = (TUBE_OD - TUBE_ID) / 2;
JUNCTION_BOX  = 90;

PORT_PATCH     = 90;
PORT_PATCH_T   = 4;
PORT_PATCH_T_SHORT = 2;
// Port boss: cookies drop into a C-channel. Optical faces stay at
// JUNCTION_BOX/2 so the stem tube does not shrink.
PORT_FRAME        = 5;
PORT_SLOT_LIP     = 8;
PORT_SLOT_CLEAR   = 0.4;
PORT_RETAIN       = 4;
PORT_BOSS_R       = 12;
STEM_F50_PATCH = 1.6;
PORT_SCREW_R   = 38.5;
PORT_CLAMP_R   = 38;
PORT_CLAMP_SEP = 15;
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
PORT_SCREW_D   = 3.2;
PORT_HEAD_D    = 6.4;
PORT_HEAD_H    = 3.4;
PORT_NUT_AF    = 5.7;
PORT_NUT_T     = 2.6;

HELICOID_MAJOR = 42;
HELICOID_PITCH = 1.0;
HELICOID_LEN   = 28;
HELICOID_TOL   = 0.45;
STEM_FLANGE_T  = 6;

EL_M39_MAJOR   = 39;
EL_M39_PITCH   = 25.4 / 26;
EL_M39_LEN     = 6;
EL_M39_TOL     = 0.45;
EL_M42_LEN     = 7;
EL_ADAPTER_HEX = 4;
EL_ADAPTER_OD  = 50;
EL_BORE        = 34;

EL180_M62_MAJOR = 62;
EL180_M62_PITCH = is_undef(EL180_M62_PITCH) ? 1.0 : EL180_M62_PITCH;
EL180_M62_LEN   = 10;      // female at the hex rim — 180 thread is only next to the flange
EL180_M62_TOL   = 0.45;
EL180_ADAPTER_OD  = 76;
EL180_BORE        = 52;    // optical through the male / stem only
EL180_BARREL      = 61.2;  // 60 mm measured + clearance; hex behind the female, no 52 mm shelf
// Pixco-style M62×1 helicoid, collapsed 17 mm / open 31 mm.
EL180_HELI_MIN    = 17;
EL180_HELI_MAX    = 31;
EL180_HELI_MALE   = 8;     // bought helicoid male
EL180_ADAPTER_MALE = 16;   // printed spacer; stem nut is 20 mm, leave ~4 mm so it does not bottom
EL180_NUT_H       = 20;
EL180_STEM_OD     = 82;
EL180_LENS_OD     = 76;
EL180_LENS_L      = 62.6;
EL180_SNOUT_D     = 40;
function el180_nut_h() = EL180_NUT_H;

F_REV_MAJOR    = 52.0;    // M52×0.75 — Fotodiox 52 mm filter thread, ISO major
F_REV_PITCH    = 0.75;
F_REV_LEN      = 8;       // female thread in inner PETG sleeve
F_REV_STACK    = 8;
F_REV_TOL      = 0.12;    // PETG 6H-ish; do not use ScrewHole’s 1.01×+1.25× formula
F_BORE         = 40.3;
F_FMOUNT_STACK = 1.75;
F_REGISTER_T   = F_REV_STACK;
F_PEG_H        = 5.5;

TRIPOD_INSERT_D = 8.1;
TRIPOD_INSERT_L = 6.4;
TRIPOD_KEEP     = 1.2;
function tripod_hole_h() = min(WALL - TRIPOD_KEEP, TRIPOD_INSERT_L + 1.0);

D7000_TRIPOD_ABOVE = 9.4; // DX: measured on D7000
D7000_TRIPOD_IN    = 40;
function d800_tripod_above() =
    is_undef(D800_TRIPOD_ABOVE) ? 10.0 : D800_TRIPOD_ABOVE;
function d800_tripod_in() =
    is_undef(D800_TRIPOD_IN) ? 44 : D800_TRIPOD_IN;
function cam_tripod_above() =
    fx_mode() ? d800_tripod_above() : D7000_TRIPOD_ABOVE;
function cam_tripod_in() =
    fx_mode() ? d800_tripod_in() : D7000_TRIPOD_IN;
BRACE_T            = 8;
BRACE_CAM_LIFT     = cam_tripod_above();
BRACE_WEB          = 22;
BRACE_PAD_D        = 44;
BRACE_SLOT_L       = 18;
BRACE_SLOT_W       = 7;
BRACE_SCREW_D      = 6.6;
BRACE_HEAD_D       = 24;  // knurled 1/4-20 camera thumbscrew (was 13)
BRACE_HEAD_COUNTER_H = 4; // chassis screw pocket; leave ~4 mm clamp
BRACE_BOTTOM_RELIEF_H = 12; // through web + into pad underside
// Pull the R–T web off the R battery-door corner. Pads stay round.
BRACE_RT_ALONG = 52;  // along RT from R, past the pad
BRACE_RT_INSET = 32;  // toward origin from that point
BRACE_HEX_D        = 8.6;
BRACE_HEX_CELL     = 11;

// Inner PETG / CF-PETG lining vs outer PCTG shell.
INNER_LINING = 1.6;
FLOOR_SKIN   = 0;     // chamber floor is inner PETG (was 0.4 PCTG cap)
MARK_DEPTH   = 1.2;   // FXPan + 65MP (or DX D12600) on the blank −X wall
// Tube ID baffles (PETG liner). 45° tooth, camera face flat — cookie on the bed.
BAFFLE_H     = 1.6;
BAFFLE_PITCH = 4.0;
// Glare stop in the F throat, chassis side of the register (not into the body).
MASK_CLEAR   = 4.0;
MASK_T       = 1.4;

SHIM_STEPS = [0.2, 0.5, 1.0];

BODY_W = fx_mode() ? 146.0 : 132;
BODY_H = fx_mode() ? 123.0 : 105;
BODY_D = fx_mode() ? 81.5 : 77;

$fn = 96;
EXPLODED = 0;
SHOW_GHOSTS = 0;
