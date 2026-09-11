// F-mount from the provided scan/model — do not reinvent the bayonet.
// STL axis = Z. We center XY, put the back face at z=0, bayonet toward +Z (camera).

include <params.scad>

// Measured from f-mount_raw.stl
F_STL_FILE   = "../f-mount_raw.stl";
F_STL_CX     = 2.091;     // centroid X (mm)
F_STL_CY     = 0.934;     // centroid Y
F_STL_ZMIN   = -1.750;    // back face
F_STL_ZMAX   = 5.000;     // bayonet tip
F_STL_HEIGHT = F_STL_ZMAX - F_STL_ZMIN;  // 6.75
F_STL_OD     = 56;        // approx outer for boss blend

module f_mount_stl_raw() {
    // Origin at back-face center; +Z toward camera / bayonet
    translate([-F_STL_CX, -F_STL_CY, -F_STL_ZMIN])
        import(F_STL_FILE, convexity = 12);
}

// boss extends −Z into arm tube for a solid fusion joint
module f_mount_male_solid(register_t = 0, boss = 12) {
    difference() {
        union() {
            if (boss > 0) {
                // blend boss into STL back
                translate([0, 0, -boss])
                    cylinder(h = boss + 1.0, d = TUBE_OD);
                translate([0, 0, -0.2])
                    cylinder(h = 2.5, d1 = TUBE_OD, d2 = F_STL_OD);
            }
            f_mount_stl_raw();
        }
        // optical clear through mount
        translate([0, 0, -boss - 0.2])
            cylinder(h = boss + F_STL_HEIGHT + 1, d = F_BORE);
    }
}

// Standalone test / PART="f_mount"
module f_mount_male(register_t = 0) {
    f_mount_male_solid(boss = 0);
}
