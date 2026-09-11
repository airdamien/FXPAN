// F-mount = your STL, untouched. Peg only is bored for fusion into the arm.

include <params.scad>

F_STL_FILE   = "../f-mount_raw.stl";
F_STL_CX     = 2.091;
F_STL_CY     = 0.934;
F_STL_ZMIN   = -1.750;
F_STL_ZMAX   = 5.000;
F_STL_HEIGHT = F_STL_ZMAX - F_STL_ZMIN;
F_STL_OD     = 52;

module f_mount_stl_raw() {
    translate([-F_STL_CX, -F_STL_CY, -F_STL_ZMIN])
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
