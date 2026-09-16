// Nikon Dual — hybrid pano L (toed DX + one 50/50 plate)
// Each DX body is aimed at a different half of a ~42.5 mm image
// (sensor_shift / field_toe). That is the panorama.
// One uncut 50×50 plate at the origin: R → +X, T → +Y.
// https://www.edmundoptics.com/p/50-x-50mm-50r50t-plate-beamsplitter/4985/

FLANGE_F = 46.5;

D_LENS_TO_PLATE_LONG = 55;
// F 50 stem sits on the cookie (no 10 mm stub). 135/180 keep 55.
D_LENS_TO_PLATE_F50  = 45;
D_LENS_TO_PLATE = (!is_undef(STEM) && STEM == 1)
    ? D_LENS_TO_PLATE_F50 : D_LENS_TO_PLATE_LONG;
// 72 mm for EL 135/180. F 50 camera tubes: 16 mm in (body clearance)
// plus 2 mm thinner cookies. Do not mix.
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

PORT_PATCH     = 90;
PORT_PATCH_T   = 4;
// F 50 camera cookies. 2 mm = 0.8 mm flange mark + ~3 perimeters.
PORT_PATCH_T_SHORT = 2;
// F 50 stem cookie is also the female-F back (no 3 mm stack). 1.6 mm
// still holds M3 + the stamp.
STEM_F50_PATCH = 1.6;
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

// EL-Nikkor 180/5.6 barrel (not L39). Pitch is often 1.0; dry-fit and
// set EL180_M62_PITCH=0.75 if the first print binds or will not start.
EL180_M62_MAJOR = 62;
EL180_M62_PITCH = is_undef(EL180_M62_PITCH) ? 1.0 : EL180_M62_PITCH;
EL180_M62_LEN   = 8;
EL180_M62_TOL   = 0.45;
EL180_ADAPTER_HEX = 6;
EL180_ADAPTER_OD  = 72;
EL180_BORE        = 56;

F_REV_MAJOR    = 52.0;
F_REV_PITCH    = 0.75;
F_REV_LEN      = 8;
F_REV_STACK    = 8;
F_REV_TOL      = 0.12;
F_BORE         = 40.3;
F_FMOUNT_STACK = 1.75;
F_REGISTER_T   = F_REV_STACK;

// 1/4-20 heat-set in the chassis floor (print floor on the bed).
// CNC Kitchen short camera insert: 1/4-20 × 6.4 mm, hole Ø8.1.
TRIPOD_INSERT_D = 8.1;
TRIPOD_INSERT_L = 6.4;
TRIPOD_KEEP     = 1.2;
function tripod_hole_h() = min(WALL - TRIPOD_KEEP, TRIPOD_INSERT_L + 1.0);

D7000_TRIPOD_ABOVE = 9.4; // body 1/4-20 above chassis bottom plane (measured)
D7000_TRIPOD_IN    = 40;
BRACE_T            = 8;
BRACE_CAM_LIFT     = D7000_TRIPOD_ABOVE;
BRACE_WEB          = 22;
BRACE_PAD_D        = 44;
BRACE_SLOT_L       = 18;
BRACE_SLOT_W       = 7;
BRACE_SCREW_D      = 6.6;
BRACE_HEAD_D       = 24;
BRACE_HEAD_COUNTER_H = 4;
BRACE_BOTTOM_RELIEF_H = 12;
BRACE_HEX_D        = 8.6;
BRACE_HEX_CELL     = 11;

SHIM_STEPS = [0.2, 0.5, 1.0];

BODY_W = 132;
BODY_H = 105;
BODY_D = 77;

$fn = 96;
EXPLODED = 0;
SHOW_GHOSTS = 0;
// PART is the Watch Me [Part] dropdown (WATCH_ME.scad).
