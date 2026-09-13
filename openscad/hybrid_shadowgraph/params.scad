// Nikon Dual — hybrid shadowgraph (same-image DX + one 50/50 plate)
// Both bodies see the same frame. T is the conjugate tube. R is the
// shadowgraph tube: 0.6 mm longer (~7.4 mm object defocus) + razor slot.
// field_toe is zero — do not stitch.
// One uncut 50×50 plate at the origin: R → +X, T → +Y.
// https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/

FLANGE_F = 46.5;

D_LENS_TO_PLATE  = 55;
D_PLATE_TO_MOUNT = 72;
PATH_FOLD        = D_LENS_TO_PLATE + D_PLATE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;

SENSOR_W      = 23.6;
SENSOR_H      = 15.6;
OVERLAP_FRAC  = 1.00;   // same frame — not a stitch
R_LEN_EXTRA   = 0.60;   // shadowgraph R tube vs T (not a stacked shim)
function path_after_knife()   = D_PLATE_TO_MOUNT + FLANGE_F;
function overlap_at_sensor()  = SENSOR_W * OVERLAP_FRAC;
function overlap_cross()      = overlap_at_sensor() * path_after_knife() / PATH_TOTAL;
function sensor_shift()       = 0;
function field_toe()          = 0;
function stitch_w()           = SENSOR_W;

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
F_FMOUNT_STACK = 1.75;
F_REGISTER_T   = F_REV_STACK;

// 1/4-20 heat-set in the chassis floor (print floor on the bed).
// CNC Kitchen short camera insert: 1/4-20 × 6.4 mm, hole Ø8.1.
TRIPOD_INSERT_D = 8.1;
TRIPOD_INSERT_L = 6.4;
TRIPOD_KEEP     = 1.2;
function tripod_hole_h() = min(WALL - TRIPOD_KEEP, TRIPOD_INSERT_L + 1.0);

SHIM_STEPS = [0.2, 0.5, 1.0];

BODY_W = 132;
BODY_H = 105;
BODY_D = 77;

$fn = 96;
EXPLODED = 0;
SHOW_GHOSTS = 0;
PART = is_undef(PART) ? "assembly" : PART;
// assembly | chassis | stem | arm_r | arm_t | lid | display_mount | hybrid_tray | shims | elnikkor_adapter
