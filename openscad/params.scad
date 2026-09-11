// Nikon Dual T — shared parameters
// Optical path: P = D_LENS_TO_KNIFE + D_KNIFE_TO_MOUNT + FLANGE_F

FLANGE_F = 46.5;          // mm, D7000 internal mount→sensor (fixed)

// Field-splitter fold — arms long enough that F-mounts sit clear of the box
D_LENS_TO_KNIFE  = 55;    // helicoid register → knife
D_KNIFE_TO_MOUNT = 72;    // knife → camera F-mount register face
PATH_FOLD        = D_LENS_TO_KNIFE + D_KNIFE_TO_MOUNT;
PATH_TOTAL       = PATH_FOLD + FLANGE_F;  // ~173.5 mm

// First-surface mirrors
MIRROR_SIZE   = 50;
MIRROR_THICK  = 3;
MIRROR_CLEAR  = 0.4;

// Junction / tubes
TUBE_ID       = 52;
TUBE_OD       = 68;
WALL          = (TUBE_OD - TUBE_ID) / 2;
JUNCTION_BOX  = 90;

// Helicoid stem (M42×1)
HELICOID_MAJOR = 42;
HELICOID_PITCH = 1.0;
HELICOID_LEN   = 28;
HELICOID_TOL   = 0.45;    // ScrewHole extra clearance for FDM
STEM_FLANGE_T  = 6;

// Male F-mount — geometry comes from f-mount_raw.stl (see f_mount_male.scad)
F_BORE         = 40.3;    // clear aperture through imported mount
F_REGISTER_T   = 6.75;    // STL height (Zmax-Zmin); used for ghost body spacing
F_LUG_T        = 0;       // included in STL


SHIM_RANGE     = 2.0;
SHIM_STEPS     = [0.2, 0.5, 1.0];

BODY_W = 132;
BODY_H = 105;
BODY_D = 77;

$fn = 96;
EXPLODED = 0;
PART = "assembly";        // assembly | chassis | lid | mirror_tray | shims | f_mount
