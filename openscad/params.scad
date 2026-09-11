// Nikon Dual T — shared parameters
// Optical path: P = D_LENS_TO_KNIFE + D_KNIFE_TO_MOUNT + FLANGE_F

FLANGE_F = 46.5;          // mm, D7000 internal mount→sensor (fixed)

// Field-splitter fold — arms long enough that F-mounts sit clear of the box
D_LENS_TO_KNIFE  = 55;    // helicoid register → knife
D_KNIFE_TO_MOUNT = 72;    // knife → camera F-mount register face
PATH_FOLD        = D_LENS_TO_KNIFE + D_KNIFE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;  // ~173.5 mm

// Stitch overlap: each camera looks across the knife by this fraction of
// a D7000 frame. Glasses cross past the axis by the same field mapped to
// the knife. Tune OVERLAP_FRAC; 0.20 ≈ 4.7 mm / ~1000 px on each body.
SENSOR_W      = 23.6;
OVERLAP_FRAC  = 0.20;
function path_after_knife()   = D_KNIFE_TO_MOUNT + FLANGE_F;
function overlap_at_sensor()  = SENSOR_W * OVERLAP_FRAC;
function overlap_cross()      = overlap_at_sensor() * path_after_knife() / PATH_TOTAL;
function arm_toe()            = atan(overlap_at_sensor() / path_after_knife());

// First-surface mirrors
MIRROR_SIZE   = 50;
MIRROR_THICK  = 3;
MIRROR_CLEAR  = 0.4;

// Junction / tubes
TUBE_ID       = 52;
TUBE_OD       = 68;
WALL          = (TUBE_OD - TUBE_ID) / 2;
JUNCTION_BOX  = 90;

// Detachable ports: wall cookie + tube, print cookie on the bed
PORT_PATCH     = 86;      // square of the outer face that travels with the tube
PORT_PATCH_T   = 4;       // cookie thickness (outer part of WALL)
PORT_FIT       = 0.35;    // recess clearance
PORT_SCREW_R   = 38.5;    // 4× M3 at 45° so adjacent faces do not share a corner
PORT_SCREW_D   = 3.2;
PORT_NUT_AF    = 5.7;     // M3 hex, across flats
PORT_NUT_T     = 2.6;     // hex trap in the inner wall (no chamber boss)

// Helicoid stem (M42×1)
HELICOID_MAJOR = 42;
HELICOID_PITCH = 1.0;
HELICOID_LEN   = 28;
HELICOID_TOL   = 0.45;    // ScrewHole extra clearance for FDM
STEM_FLANGE_T  = 6;

// Fotodiox-style Nikon F reverse ring: male F-bayonet + male 52 mm filter
// thread. Arms are female 52×0.75; the ring screws on, bodies bayonet on.
// https://www.amazon.com/Fotodiox-Reverse-Adapter-Compatible-Cameras/dp/B001G4NBSC
F_REV_MAJOR    = 52;      // filter thread major (mm)
F_REV_PITCH    = 0.75;
F_REV_LEN      = 7;       // printed female thread length
F_REV_STACK    = 8;       // ring, thread seat → F-register (tune on the real part)
F_REV_TOL      = 0.45;
F_BORE         = 40.3;
F_REGISTER_T   = F_REV_STACK;


// 1/4-20 UNC in the chassis floor (tripod shoe / camera screw)
TRIPOD_MAJOR   = 6.35;
TRIPOD_PITCH   = 1.27;
TRIPOD_TOL     = 0.45;
TRIPOD_KEEP    = 1.8;     // leave this much floor so the tap stays blind

SHIM_RANGE     = 2.0;
SHIM_STEPS     = [0.2, 0.5, 1.0];

BODY_W = 132;
BODY_H = 105;
BODY_D = 77;

$fn = 96;
EXPLODED = 0;             // 1 = pull arms + lift mirror cartridges for drop-in view
SHOW_LID = 0;             // 0 = hide lid so you can see mirrors / grooves
SHOW_GHOSTS = 0;
SHOW_CRADLES = 0;
PART = "assembly";        // assembly | chassis | stem | arm_l | arm_r | lid | mirror_tray | shims | f_mount
