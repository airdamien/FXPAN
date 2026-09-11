// Nikon Dual T — shared parameters
// Optical path: P = D_LENS_TO_KNIFE + D_KNIFE_TO_MOUNT + FLANGE_F
// Infinity focus comes from the helicoid at the stem, not from an F-Nikkor.

FLANGE_F = 46.5;          // mm, D7000 internal mount→sensor (fixed)

// Field-splitter fold (symmetric L/R)
D_LENS_TO_KNIFE  = 45;    // lens flange / helicoid register → knife edge
D_KNIFE_TO_MOUNT = 45;    // knife edge → camera F-mount register face
PATH_FOLD        = D_LENS_TO_KNIFE + D_KNIFE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;  // ~136.5 mm — helicoid focuses here

// First-surface mirrors (Amazon FSM squares)
MIRROR_SIZE   = 50;       // mm, square edge
MIRROR_THICK  = 3;        // mm, typical FSM substrate
MIRROR_CLEAR  = 0.4;      // pocket clearance

// Junction / tubes — OD can be large; ID steps down at F-mounts (see F_BORE)
TUBE_ID       = 52;       // arm / stem clear (≤ image needs, ≥ F_BORE)
TUBE_OD       = 68;
WALL          = (TUBE_OD - TUBE_ID) / 2;
JUNCTION_BOX  = 86;       // must exceed TUBE_OD so arms fuse into box faces

// Helicoid stem (M42×1 default; set HELICOID_MAJOR=39 for M39)
HELICOID_MAJOR = 42;
HELICOID_PITCH = 1.0;
HELICOID_LEN   = 28;      // printed engagement length
STEM_FLANGE_T  = 6;

// Male F-mount (camera bayonets onto this) — calibrate vs f-mount_raw.stl
F_THROAT       = 43.8;    // cylinder OD into camera throat (~44)
F_LUG_OD       = 47.6;
F_LUG_T        = 1.6;
F_LUG_SWEEP    = 58;      // degrees per lug
F_REGISTER_T   = 4.5;     // flange thickness behind lugs
F_LOCK_NOTCH_W = 4.2;
F_LOCK_NOTCH_D = 1.8;
F_BORE         = F_THROAT - 3.5;  // clear aperture through male F (keep < lug OD)

// Per-arm path shims / adjusters
SHIM_RANGE     = 2.0;     // ± mm focus match
SHIM_STEPS     = [0.2, 0.5, 1.0];

// D7000 body envelope (for cradles / clearance)
BODY_W = 132;
BODY_H = 105;
BODY_D = 77;

// Preview / export
$fn = 96;
EXPLODED = 0;             // 1 = pull parts apart for viewing
PART = "assembly";        // assembly | chassis | lid | mirror_tray | shims | f_mount
