// Nikon Dual — hybrid pano L (toed DX + one 50/50 plate)
// Each DX body is aimed at a different half of a ~42.5 mm image
// (sensor_shift / field_toe). That is the panorama.
// One uncut 50×50 plate at the origin: R → +X, T → +Y.
// https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/

FLANGE_F = 46.5;

D_LENS_TO_PLATE  = 55;
D_PLATE_TO_MOUNT = 72;
PATH_FOLD        = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;

SENSOR_W      = 23.6;
SENSOR_H      = 15.6;
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

F_REV_MAJOR    = 52;
F_REV_PITCH    = 0.75;
F_REV_LEN      = 7;
F_REV_STACK    = 8;
F_REV_TOL      = 0.45;
F_BORE         = 40.3;
F_REGISTER_T   = F_REV_STACK;

TRIPOD_MAJOR   = 6.35;
TRIPOD_PITCH   = 1.27;
TRIPOD_TOL     = 0.45;
TRIPOD_KEEP    = 1.8;

SHIM_STEPS = [0.2, 0.5, 1.0];

BODY_W = 132;
BODY_H = 105;
BODY_D = 77;

$fn = 96;
EXPLODED = 0;
SHOW_LID = 0;
SHOW_GHOSTS = 0;
PART = is_undef(PART) ? "assembly" : PART;
// assembly | chassis | stem | arm_r | arm_t | lid | hybrid_tray | shims | elnikkor_adapter
