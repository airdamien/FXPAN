// Male Canon EF — camera bayonets onto this (lens-rear style).
// Throat 54 / external 65 / 3 lugs. Dry-fit a 5D III and tweak
// EF_LUG_SWEEP / EF_LUG_OD / EF_MOUNT_CLOCK if the first print is stiff.

include <params.scad>

module ef_rev_thread_cut(h = undef) {
    _h = is_undef(h) ? EF_REV_LEN + 0.3 : h;
    ScrewThread(EF_REV_MAJOR, _h,
                pitch = EF_REV_PITCH,
                tolerance = EF_REV_TOL,
                tooth_angle = 30);
}

module ef_lug() {
    rotate_extrude(angle = EF_LUG_SWEEP)
        translate([EF_THROAT / 2, 0])
            square([(EF_LUG_OD - EF_THROAT) / 2, EF_LUG_T]);
}

module ef_mount_male_solid() {
    difference() {
        union() {
            cylinder(h = EF_REGISTER_T, d = EF_FLANGE_OD);
            translate([0, 0, EF_REGISTER_T])
                for (a = [0, 120, 240])
                    rotate([0, 0, a - EF_LUG_SWEEP / 2])
                        ef_lug();
        }
        translate([0, 0, -0.1])
            cylinder(h = EF_REGISTER_T + EF_LUG_T + 0.2, d = EF_BORE);
    }
}

// Back at z=0 (tube end). Register face at z=EF_REGISTER_T.
// Lugs point +Z into the camera. Rotate `clock` so the body locks
// flange-mark up (red-dot / lock pin live in EF_MOUNT_CLOCK).
module ef_mount_on_tube(clock = 0) {
    translate([0, 0, -4])
        difference() {
            cylinder(h = 4.4, d = TUBE_ID + 4);
            translate([0, 0, -0.1])
                cylinder(h = 4.6, d = EF_BORE);
        }
    rotate([0, 0, clock])
        ef_mount_male_solid();
}
