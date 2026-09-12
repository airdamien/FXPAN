// F-mount = your STL, untouched on the camera face. Peg / collar / tine
// pads are unions only — difference() on the import shreds preview/render.

include <params.scad>

F_STL_FILE   = "../f-mount_raw.stl";
// Flange OD circle is already at XY origin; old CX/CY offsets shoved the
// bayonet off the arm bore.
F_STL_ZMIN   = -1.750;
F_STL_ZMAX   = 5.000;
F_STL_HEIGHT = F_STL_ZMAX - F_STL_ZMIN;
F_STL_OD     = 52;
// Meat behind the register (z=1.75). Covers fork roots (r=29) without
// growing the lugs or filling the ~2.4 mm pin slot.
F_PEG_H      = 5.5;
F_COLLAR_OD  = 62;
F_COLLAR_Z0  = -1.6;
F_COLLAR_H   = 2.0;

module f_mount_stl_raw() {
    translate([0, 0, -F_STL_ZMIN])
        import(F_STL_FILE, convexity = 12);
}

// Do NOT difference() the imported mesh — that shreds preview/render.
module f_mount_male_solid(register_t = 0, boss = 4) {
    if (boss > 0)
        translate([0, 0, -boss])
            difference() {
                cylinder(h = boss + 0.4, d = F_STL_OD);
                translate([0, 0, -0.1])
                    cylinder(h = boss + 0.6, d = F_BORE);
            }
    color("Goldenrod")
        f_mount_stl_raw();
}

module f_mount_male(register_t = 0) {
    f_mount_male_solid(boss = 0);
}

// Raw forks at +X. Pin is 90° left of flange-mark-up (look −Z, CCW).
function f_pin_az(up_az) = up_az + 90;

// Radial groove on the tube-end annulus (reverse-ring seat), at the
// lock-pin azimuth. Engraved so the ring still sits flat; clock to it.
module f_pin_line_cut(out_len, up_az) {
    t = 0.35;
    r0 = TUBE_ID / 2 + 3.0;
    r1 = TUBE_OD / 2 - 0.4;
    rotate([0, 0, f_pin_az(up_az)])
        translate([(r0 + r1) / 2, 0, out_len - t / 2])
            cube([r1 - r0, 0.7, t + 0.1], center = true);
}

// Tine roots only (y ≈ ±2.55). Leaves the pin slot |y| < 1.2 open.
module f_fork_pads() {
    for (s = [-1, 1])
        translate([26.6, s * 2.55, 0.65])
            cube([5.5, 2.2, 1.3], center = true);
}

// Back at z=0 (tube end). Register face at z=1.75. Lock-pin forks at +X
// in the raw mesh (not +Y). Clock so those forks sit 90° left of
// flange-mark-up — that is where the D7000 body pin actually is.
// Bored peg sinks into TUBE_ID; collar / pads stay behind the register.
module f_mount_on_tube(clock = 0) {
    translate([0, 0, -F_PEG_H])
        difference() {
            cylinder(h = F_PEG_H + 0.4, d = F_STL_OD);
            translate([0, 0, -0.1])
                cylinder(h = F_PEG_H + 0.6, d = F_BORE);
        }
    translate([0, 0, F_COLLAR_Z0])
        difference() {
            cylinder(h = F_COLLAR_H, d = F_COLLAR_OD);
            translate([0, 0, -0.1])
                cylinder(h = F_COLLAR_H + 0.2, d = F_BORE);
        }
    rotate([0, 0, clock]) {
        f_mount_stl_raw();
        f_fork_pads();
    }
}
