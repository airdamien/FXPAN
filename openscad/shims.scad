// Path-length shim rings — stack behind imported F-mount if needed for focus match.

include <params.scad>

module shim_ring(t) {
    difference() {
        cylinder(h = t, d = TUBE_OD + 4);
        translate([0, 0, -0.1])
            cylinder(h = t + 0.2, d = F_BORE + 1);
        for (a = [0, 120, 240])
            rotate([0, 0, a])
                translate([TUBE_OD / 2 - 4, 0, -0.1])
                    cylinder(h = t + 0.2, d = 3.2);
    }
}

module shim_set() {
    for (i = [0 : len(SHIM_STEPS) - 1])
        translate([i * (TUBE_OD + 12), 0, 0])
            shim_ring(SHIM_STEPS[i]);
}
