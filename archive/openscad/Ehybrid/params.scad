// Sony Dual — hybrid pano L (toed FF A7 + one 50/50 plate)
// α7 bodies, E-mount. Each FF body is aimed at a different
// half of a ~64.4 mm image (sensor_shift / field_toe). That is the panorama.
// One uncut 50×50 plate at the origin: R → +X, T → +Y.
// 18 mm register → PATH_TOTAL ≈ 145 mm (135/5.6 focuses ~2 m).
// https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/

FLANGE_F = 18.0;          // Sony E register

D_LENS_TO_PLATE  = 55;
D_PLATE_TO_MOUNT = 72;
PATH_FOLD        = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;

// Sony α7 (ILCE-7)
SENSOR_W      = 35.8;
SENSOR_H      = 23.9;
OVERLAP_FRAC  = 0.20;
function path_after_knife()   = D_PLATE_TO_MOUNT + FLANGE_F;
function overlap_at_sensor()  = SENSOR_W * OVERLAP_FRAC;
function overlap_cross()      = overlap_at_sensor() * path_after_knife() / PATH_TOTAL;
function sensor_shift()       = SENSOR_W / 2 * (1 - OVERLAP_FRAC);
function field_toe()          = atan(sensor_shift() / path_after_knife());
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

PORT_PATCH     = 86;
PORT_PATCH_T   = 4;
PORT_SCREW_R   = 38.5;
PORT_SCREW_D   = 3.2;
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

// Female 52×0.75 — Sony E reversing ring (same mouth as the Nikon hybrid).
E_REV_MAJOR    = 52;
E_REV_PITCH    = 0.75;
E_REV_LEN      = 7;
E_REV_STACK    = 8;
E_REV_TOL      = 0.45;

// Printed male E (camera bayonets on). 46.1 inner / 18 flange.
E_THROAT       = 46.1;
E_BORE         = 46.1;
E_FLANGE_OD    = 48.0;
E_LUG_OD       = 50.5;
E_LUG_T        = 1.5;
E_LUG_SWEEP    = 45;
E_REGISTER_T   = 1.8;
E_FMOUNT_STACK = E_REGISTER_T;

// 1/4-20 heat-set in the chassis floor (print floor on the bed).
// CNC Kitchen short camera insert: 1/4-20 × 6.4 mm, hole Ø8.1.
TRIPOD_INSERT_D = 8.1;
TRIPOD_INSERT_L = 6.4;
TRIPOD_KEEP     = 1.2;
function tripod_hole_h() = min(WALL - TRIPOD_KEEP, TRIPOD_INSERT_L + 1.0);

SHIM_STEPS = [0.2, 0.5, 1.0];

// α7 CIPA, grip-to-monitor
BODY_W = 126.9;
BODY_H = 94.4;
BODY_D = 48.2;

$fn = 96;
EXPLODED = 0;
SHOW_GHOSTS = 0;
PART = is_undef(PART) ? "assembly" : PART;
// assembly | chassis | stem | arm_r | arm_t | lid | hybrid_tray | shims | elnikkor_adapter
