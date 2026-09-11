// =============================================================================
// WATCH_ME.scad  — KEEP THIS OPEN (Automatic Reload and Preview)
// =============================================================================
// Single printable chassis: junction + stem + both arms + F-mounts are ONE solid.
// Separate prints: lid, mirror trays, shims.
// =============================================================================

include <params.scad>
use <f_mount_male.scad>
use <mirror_tray.scad>
use <shims.scad>

ex = EXPLODED ? 50 : 0;
MOUNT_BOSS = 14;  // solid fusion length behind each F register into the arm

module tube_x(x0, x1) {
    // horizontal tube along X from x0 to x1 (x1 > x0)
    translate([x0, 0, 0])
        rotate([0, 90, 0])
            cylinder(h = x1 - x0, d = TUBE_OD);
}

module tube_y(y0, y1) {
    // tube along Y from y0 to y1 (y1 > y0)
    translate([0, y0, 0])
        rotate([-90, 0, 0])
            cylinder(h = y1 - y0, d = TUBE_OD);
}

module helicoid_nut(h = HELICOID_LEN) {
    major = HELICOID_MAJOR;
    pitch = HELICOID_PITCH;
    difference() {
        cylinder(h = h, d = major + 12);
        translate([0, 0, -0.1])
            cylinder(h = h + 0.2, d = major - 1.6);
        for (i = [0 : max(0, floor(h / pitch) - 1)])
            translate([0, 0, i * pitch])
                rotate([0, 0, (i * 25) % 360])
                    rotate_extrude(angle = 300)
                        translate([major / 2 - 0.85, 0])
                            circle(d = 0.8, $fn = 12);
    }
}

// Structural cradle under an arm — fused to tube + mount flange
module arm_cradle_solid() {
    // local coords: tube along Z (mount at z=0 growing +Z), gravity -Y
    hull() {
        translate([0, 0, -MOUNT_BOSS / 2])
            cylinder(h = MOUNT_BOSS, d = TUBE_OD);
        translate([0, -TUBE_OD / 2 - 8, -MOUNT_BOSS / 2])
            cube([36, 16, MOUNT_BOSS], center = true);
    }
    // 1/4-20 pad
    translate([0, -TUBE_OD / 2 - 14, -MOUNT_BOSS / 2])
        difference() {
            cube([28, 14, 12], center = true);
            cylinder(h = 20, d = 5.6, center = true);
        }
}

// ----- ONE continuous chassis body -----
module chassis_outer() {
    s = JUNCTION_BOX;
    // junction box
    cube([s, s, s], center = true);

    // stem tube: from box face to helicoid register plane
    // register at y = -D_LENS_TO_KNIFE; box face at y = -s/2
    tube_y(-D_LENS_TO_KNIFE, -s / 2 + 1);

    // helicoid flange + nut at stem end
    translate([0, -D_LENS_TO_KNIFE, 0])
        rotate([90, 0, 0]) {
            cylinder(h = STEM_FLANGE_T, d = TUBE_OD + 8);
            for (a = [0, 90, 180, 270])
                rotate([0, 0, a])
                    translate([TUBE_OD / 2 + 3, 0, STEM_FLANGE_T / 2])
                        cube([10, 12, STEM_FLANGE_T], center = true);
            translate([0, 0, STEM_FLANGE_T])
                helicoid_nut(HELICOID_LEN);
        }

    // left / right arms + integrated F-mounts
    for (side = [-1, 1]) {
        // tube from box into mount boss (overlap box wall so it fuses)
        if (side > 0)
            tube_x(s / 2 - 1, D_KNIFE_TO_MOUNT);
        else
            tube_x(-D_KNIFE_TO_MOUNT, -s / 2 + 1);

        // F-mount solid at register plane, oriented toward camera (outward)
        translate([side * D_KNIFE_TO_MOUNT, 0, 0])
            rotate([0, side * 90, 0]) {
                f_mount_male_solid(boss = MOUNT_BOSS);
                arm_cradle_solid();
            }
    }
}

module chassis_bore() {
    s = JUNCTION_BOX;
    // hollow chamber
    cube([s - 2 * WALL, s - 2 * WALL, s - 2 * WALL], center = true);

    // stem bore (-Y) through helicoid
    rotate([90, 0, 0])
        cylinder(h = D_LENS_TO_KNIFE + HELICOID_LEN + STEM_FLANGE_T + 5, d = TUBE_ID);

    // arm bores: stop at mount boss so F-mount solid keeps its own F_BORE
    for (side = [-1, 1]) {
        len = D_KNIFE_TO_MOUNT - MOUNT_BOSS + 2;
        translate([side * (s / 4), 0, 0])
            rotate([0, side * 90, 0])
                cylinder(h = len, d = TUBE_ID);
    }

    // open top for lid / mirror access
    translate([0, 0, s / 2 - WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, WALL + 0.2], center = true);

    // lid screw holes (heat-set M3)
    for (x = [-1, 1], y = [-1, 1])
        translate([x * (s / 2 - 8), y * (s / 2 - 8), s / 2 - 15])
            cylinder(h = 20, d = 3.2);

    // helicoid ear holes
    translate([0, -D_LENS_TO_KNIFE, 0])
        rotate([90, 0, 0])
            for (a = [0, 90, 180, 270])
                rotate([0, 0, a])
                    translate([TUBE_OD / 2 + 3, 0, -1])
                        cylinder(h = STEM_FLANGE_T + 2, d = 3.2);

    // room for mirror trays — roof in +Y half, clear ±X camera tunnels
    for (side = [-1, 1]) {
        rot = -side * 45;
        along_n = MIRROR_SIZE * 0.5 + MIRROR_THICK;
        rotate([0, 0, rot])
            translate([0, along_n, 0])
                cube([MIRROR_SIZE + 14, MIRROR_THICK + 16, MIRROR_SIZE + 14], center = true);
    }
}

module part_chassis() {
    color("SlateGray")
    difference() {
        chassis_outer();
        chassis_bore();
    }
    // mirror tray floors (still part of chassis solid)
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
                side * (D_KNIFE_TO_MOUNT + BODY_D / 2 + 6 + ex),
                0,
                -5
            ])
                cube([BODY_D, BODY_W * 0.85, BODY_H * 0.75], center = true);
}

module ghost_lens() {
    if ($preview)
        color("black", 0.22)
            translate([0, -D_LENS_TO_KNIFE - HELICOID_LEN - 25 - ex, 0])
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
    translate([0, ex * 0.15, 0])
        part_chassis();
    part_lid();
    translate([0, 0, ex * 0.2])
        mirror_pair(show_mirrors = $preview);
    ghost_body(-1);
    ghost_body(1);
    ghost_lens();
    optical_axis_guides();
    echo(str("PATH_FOLD=", PATH_FOLD,
             " PATH_TOTAL=", PATH_TOTAL,
             " mm — chassis is one solid"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction" || PART == "stem" ||
        PART == "arm_l" || PART == "arm_r")
        part_chassis();  // one body now
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
