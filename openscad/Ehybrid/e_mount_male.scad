// Male Sony E — camera bayonets onto this (lens-rear style).
// Inner 46.1 / 3 lugs / 18 mm register. Dry-fit an A7 and tweak
// E_LUG_SWEEP / E_LUG_OD / E_MOUNT_CLOCK if the first print is stiff.

include <params.scad>

module e_lug() {
    rotate_extrude(angle = E_LUG_SWEEP)
        translate([E_THROAT / 2, 0])
            square([(E_LUG_OD - E_THROAT) / 2, E_LUG_T]);
}

module e_mount_male_solid() {
    difference() {
        union() {
            cylinder(h = E_REGISTER_T, d = E_FLANGE_OD);
            translate([0, 0, E_REGISTER_T])
                for (a = [0, 120, 240])
                    rotate([0, 0, a - E_LUG_SWEEP / 2])
                        e_lug();
        }
        translate([0, 0, -0.1])
            cylinder(h = E_REGISTER_T + E_LUG_T + 0.2, d = E_BORE);
    }
}

// Back at z=0 (tube end). Register face at z=E_REGISTER_T.
// Lugs point +Z into the camera.
module e_mount_on_tube(clock = 0) {
    translate([0, 0, -4])
        difference() {
            cylinder(h = 4.4, d = TUBE_ID + 4);
            translate([0, 0, -0.1])
                cylinder(h = 4.6, d = E_BORE);
        }
    rotate([0, 0, clock])
        e_mount_male_solid();
}
