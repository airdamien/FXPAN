// =============================================================================
// WATCH_ME.scad  — KEEP THIS OPEN (Automatic Reload and Preview)
// =============================================================================
// Solid T chassis: junction + stem (M42 thread) + arms.
// F-mounts are unioned ON AFTER boring so they cannot be hollowed away.
// =============================================================================

include <params.scad>
include <lib/threads.scad>
use <f_mount_male.scad>
use <mirror_tray.scad>
use <shims.scad>

// Coarser thread mesh for snappy previews; drop to 0.2 for final STL
screw_resolution = $preview ? 0.6 : 0.25;

ex = EXPLODED ? 55 : 0;
MOUNT_BOSS = 16;

module tube_x(x0, x1) {
    translate([x0, 0, 0])
        rotate([0, 90, 0])
            cylinder(h = x1 - x0, d = TUBE_OD);
}

module tube_y(y0, y1) {
    translate([0, y0, 0])
        rotate([-90, 0, 0])
            cylinder(h = y1 - y0, d = TUBE_OD);
}

// Internal M42×1 using rcolyer threads.scad
module helicoid_nut(h = HELICOID_LEN) {
    major = HELICOID_MAJOR;
    ScrewHole(major, h, pitch = HELICOID_PITCH, tolerance = HELICOID_TOL)
        cylinder(h = h, d = major + 14);
}

module arm_cradle_solid() {
    hull() {
        translate([0, 0, -MOUNT_BOSS / 2])
            cylinder(h = MOUNT_BOSS, d = TUBE_OD);
        translate([0, -TUBE_OD / 2 - 10, -MOUNT_BOSS / 2])
            cube([40, 18, MOUNT_BOSS], center = true);
    }
    translate([0, -TUBE_OD / 2 - 16, -MOUNT_BOSS / 2])
        difference() {
            cube([30, 14, 12], center = true);
            cylinder(h = 20, d = 5.6, center = true);
        }
}

// Box + tubes + stem only (no F-mounts — those are added after bore)
module chassis_structure() {
    s = JUNCTION_BOX;
    cube([s, s, s], center = true);

    // stem tube into helicoid register
    tube_y(-D_LENS_TO_KNIFE, -s / 2 + 2);

    translate([0, -D_LENS_TO_KNIFE, 0])
        rotate([90, 0, 0]) {
            difference() {
                union() {
                    cylinder(h = STEM_FLANGE_T, d = TUBE_OD + 10);
                    for (a = [0, 90, 180, 270])
                        rotate([0, 0, a])
                            translate([TUBE_OD / 2 + 4, 0, STEM_FLANGE_T / 2])
                                cube([12, 14, STEM_FLANGE_T], center = true);
                }
                for (a = [0, 90, 180, 270])
                    rotate([0, 0, a])
                        translate([TUBE_OD / 2 + 4, 0, -1])
                            cylinder(h = STEM_FLANGE_T + 2, d = 3.2);
            }
            translate([0, 0, STEM_FLANGE_T])
                helicoid_nut(HELICOID_LEN);
        }

    // arm tubes out to mount plane (overlap box wall)
    tube_x(s / 2 - 2, D_KNIFE_TO_MOUNT);
    tube_x(-D_KNIFE_TO_MOUNT, -s / 2 + 2);
}

module chassis_bore() {
    s = JUNCTION_BOX;

    // hollow chamber
    cube([s - 2 * WALL, s - 2 * WALL, s - 2 * WALL], center = true);

    // stem optical bore — stop before threaded helicoid nut
    rotate([90, 0, 0])
        cylinder(h = D_LENS_TO_KNIFE + STEM_FLANGE_T + 1, d = TUBE_ID);

    // arm optical bores — stop before mount boss so F-mounts stay solid
    for (side = [-1, 1]) {
        len = D_KNIFE_TO_MOUNT - MOUNT_BOSS - 1;
        translate([side * (s / 2 - 1), 0, 0])
            rotate([0, -side * 90, 0])
                cylinder(h = len, d = TUBE_ID);
    }

    // open top
    translate([0, 0, s / 2 - WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, WALL + 0.2], center = true);

    for (x = [-1, 1], y = [-1, 1])
        translate([x * (s / 2 - 8), y * (s / 2 - 8), s / 2 - 15])
            cylinder(h = 20, d = 3.2);

    // mirror tray pockets (stay in +Y roof, clear of ±X mounts)
    for (side = [-1, 1]) {
        rot = -side * 45;
        along_n = MIRROR_SIZE * 0.5 + MIRROR_THICK;
        rotate([0, 0, rot])
            translate([0, along_n, 0])
                cube([MIRROR_SIZE + 12, MIRROR_THICK + 14, MIRROR_SIZE + 12], center = true);
    }
}

// F-mounts pointed OUTWARD (+X / −X). Unioned after bore so they survive.
module chassis_f_mounts() {
    for (side = [-1, 1])
        translate([side * D_KNIFE_TO_MOUNT, 0, 0])
            // side=+1 → rotate −90° about Y → local +Z maps to world +X (outward)
            rotate([0, -side * 90, 0]) {
                f_mount_male_solid(boss = MOUNT_BOSS);
                arm_cradle_solid();
            }
}

module part_chassis() {
    color("SlateGray")
    union() {
        difference() {
            chassis_structure();
            chassis_bore();
        }
        chassis_f_mounts();
    }
    // tray floors
    color("Gray")
    for (side = [-1, 1]) {
        rot = -side * 45;
        along_n = MIRROR_SIZE * 0.5 + MIRROR_THICK;
        rotate([0, 0, rot])
            translate([0, along_n + 6, -JUNCTION_BOX / 2 + WALL + 2])
                difference() {
                    cube([MIRROR_SIZE + 8, 8, 4], center = true);
                    for (x = [-14, 14])
                        translate([x, 0, 0])
                            cylinder(h = 6, d = 2.9, center = true);
                }
    }
}

module part_lid() {
    s = JUNCTION_BOX;
    color("DarkSlateGray")
    translate([0, 0, s / 2 + 2 + ex * 0.35])
        difference() {
            cube([s, s, 4], center = true);
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - 8), y * (s / 2 - 8), -3])
                    cylinder(h = 8, d = 3.2);
        }
}

module ghost_body(side = 1) {
    if ($preview)
        color("black", 0.18)
            translate([
                side * (D_KNIFE_TO_MOUNT + F_REGISTER_T + F_LUG_T + BODY_D / 2 + 4 + ex),
                0,
                -5
            ])
                cube([BODY_D, BODY_W * 0.85, BODY_H * 0.75], center = true);
}

module ghost_lens() {
    if ($preview)
        color("black", 0.2)
            translate([0, -D_LENS_TO_KNIFE - STEM_FLANGE_T - HELICOID_LEN - 20 - ex, 0])
                rotate([90, 0, 0]) {
                    cylinder(h = 35, d1 = 52, d2 = 48);
                    translate([0, 0, 35])
                        cylinder(h = 8, d = 56);
                }
}

module optical_axis_guides() {
    if ($preview)
        color("gold", 0.5) {
            rotate([90, 0, 0])
                cylinder(h = D_LENS_TO_KNIFE + 2, d = 1.0);
            rotate([0, -90, 0])
                cylinder(h = D_KNIFE_TO_MOUNT + 2, d = 1.0);
            rotate([0, 90, 0])
                cylinder(h = D_KNIFE_TO_MOUNT + 2, d = 1.0);
        }
}

module assembly() {
    translate([0, ex * 0.1, 0])
        part_chassis();
    part_lid();
    translate([0, 0, ex * 0.15])
        mirror_pair(show_mirrors = $preview);
    ghost_body(-1);
    ghost_body(1);
    ghost_lens();
    optical_axis_guides();
    echo(str("PATH_FOLD=", PATH_FOLD,
             " PATH_TOTAL=", PATH_TOTAL,
             " mm | F-mounts OUTWARD + M42 ScrewHole"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction" || PART == "stem" ||
        PART == "arm_l" || PART == "arm_r")
        part_chassis();
    else if (PART == "shims")
        shim_set();
    else if (PART == "f_mount")
        f_mount_male_solid(boss = MOUNT_BOSS);
    else if (PART == "lid")
        part_lid();
    else if (PART == "mirror_tray") {
        mirror_tray(-1, false);
        translate([90, 0, 0])
            mirror_tray(1, false);
    }
    else
        assembly();
}

export_part();
