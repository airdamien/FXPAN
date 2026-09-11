// Path-length shim rings — stack between arm tube and F-mount register.
// Print a set; match L/R live view on a distant chart.

include <params.scad>

module shim_ring(t) {
    difference() {
        cylinder(h = t, d = F_LUG_OD + 8);
        translate([0, 0, -0.1])
            cylinder(h = t + 0.2, d = F_THROAT - 2);
        for (a = [30, 150, 270])
            rotate([0, 0, a])
                translate([F_LUG_OD / 2 + 1.5, 0, -0.1])
                    cylinder(h = t + 0.2, d = 3.2);
    }
}

module shim_set() {
    for (i = [0 : len(SHIM_STEPS) - 1])
        translate([i * (F_LUG_OD + 14), 0, 0])
            shim_ring(SHIM_STEPS[i]);
}
