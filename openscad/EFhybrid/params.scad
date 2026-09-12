// Canon Dual — hybrid pano L (toed FF + one 50/50 plate)
// 5D Mark III bodies, EF mount. Each FF body is aimed at a different
// half of a ~64.8 mm image (sensor_shift / field_toe). That is the panorama.
// One uncut 50×50 plate at the origin: R → +X, T → +Y.
// https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/

FLANGE_F = 44.0;          // Canon EF register

D_LENS_TO_PLATE  = 55;
D_PLATE_TO_MOUNT = 72;
PATH_FOLD        = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;

// 5D Mark III
SENSOR_W      = 36.0;
SENSOR_H      = 24.0;
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

// Female 58×0.75 in the tube mouth — Canon EF reversing ring.
EF_REV_MAJOR    = 58;
EF_REV_PITCH    = 0.75;
EF_REV_LEN      = 7;
EF_REV_STACK    = 8;
EF_REV_TOL      = 0.45;

// Printed male EF (camera bayonets on). Wiki: 54 throat / 65 OD / 44 flange.
EF_THROAT       = 54.0;
EF_BORE         = 54.0;
EF_FLANGE_OD    = 61.0;
EF_LUG_OD       = 65.0;
EF_LUG_T        = 1.8;
EF_LUG_SWEEP    = 48;
EF_REGISTER_T   = 2.0;
EF_FMOUNT_STACK = EF_REGISTER_T;

// 1/4-20 heat-set in the chassis floor (print floor on the bed).
// CNC Kitchen short camera insert: 1/4-20 × 6.4 mm, hole Ø8.1.
TRIPOD_INSERT_D = 8.1;
TRIPOD_INSERT_L = 6.4;
TRIPOD_KEEP     = 1.2;
function tripod_hole_h() = min(WALL - TRIPOD_KEEP, TRIPOD_INSERT_L + 1.0);

SHIM_STEPS = [0.2, 0.5, 1.0];

// 5D Mark III CIPA body, no battery grip
BODY_W = 152.0;
BODY_H = 116.4;
BODY_D = 76.4;

$fn = 96;
EXPLODED = 0;
SHOW_GHOSTS = 0;
PART = is_undef(PART) ? "assembly" : PART;
// assembly | chassis | stem | arm_r | arm_t | lid | hybrid_tray | shims | elnikkor_adapter
