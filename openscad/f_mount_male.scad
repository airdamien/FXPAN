// Male Nikon F bayonet — camera mounts onto this (lens-rear style).
// Local +Z = toward camera (away from knife). Boss extends −Z into the arm tube.

include <params.scad>

module f_mount_lug() {
    rotate_extrude(angle = F_LUG_SWEEP)
        translate([F_THROAT / 2, 0])
            square([(F_LUG_OD - F_THROAT) / 2, F_LUG_T]);
}

module f_mount_male(register_t = F_REGISTER_T) {
    difference() {
        f_mount_male_solid(register_t = register_t, boss = 0);
        for (a = [30, 150, 270])
            rotate([0, 0, a])
                translate([F_LUG_OD / 2 + 1.5, 0, -0.1])
                    cylinder(h = register_t + 0.2, d = 3.2);
    }
}

module f_mount_male_solid(register_t = F_REGISTER_T, boss = 12) {
    difference() {
        union() {
            if (boss > 0)
                translate([0, 0, -boss])
                    cylinder(h = boss + 0.02, d = TUBE_OD);
            // register flange
            cylinder(h = register_t, d = max(F_LUG_OD + 12, TUBE_OD));
            // throat + three bayonet lugs (into the camera)
            translate([0, 0, register_t]) {
                cylinder(h = F_LUG_T + 1.4, d = F_THROAT);
                for (a = [0, 120, 240])
                    rotate([0, 0, a - F_LUG_SWEEP / 2])
                        f_mount_lug();
            }
        }
        translate([0, 0, -boss - 0.1])
            cylinder(h = boss + register_t + F_LUG_T + 3, d = F_BORE);
        // lens-release pin notch
        translate([0, -F_LUG_OD / 2 - 0.2, register_t + F_LUG_T / 2])
            cube([F_LOCK_NOTCH_W, F_LOCK_NOTCH_D * 2 + 1, F_LUG_T + 0.4], center = true);
    }
}
