// =============================================================================
// WATCH_ME.scad  — KEEP THIS OPEN (Automatic Reload and Preview)
// =============================================================================
// Mirrors drop in from the top into 45° grooves and meet at the box center.
// Lid optional (SHOW_LID=0 by default) — seats with a light-trap lip.
// =============================================================================

include <params.scad>
include <lib/threads.scad>
use <f_mount_male.scad>
use <mirror_tray.scad>
use <shims.scad>

screw_resolution = $preview ? 0.6 : 0.25;

ex = EXPLODED ? 55 : 0;
MOUNT_PEG = 4;
LID_T     = 4;
LID_LIP   = 3;    // light-trap step into the box
LID_GAP   = 0.3;

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

module helicoid_nut(h = HELICOID_LEN) {
    ScrewHole(HELICOID_MAJOR, h, pitch = HELICOID_PITCH, tolerance = HELICOID_TOL)
        cylinder(h = h, d = HELICOID_MAJOR + 14);
}

module arm_cradle_solid() {
    translate([0, -TUBE_OD / 2 - 12, -8])
        difference() {
            cube([24, 12, 10], center = true);
            cylinder(h = 20, d = 5.6, center = true);
        }
}

module chassis_structure() {
    s = JUNCTION_BOX;
    cube([s, s, s], center = true);

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

    tube_x(s / 2 - 2, D_KNIFE_TO_MOUNT - MOUNT_PEG);
    tube_x(-(D_KNIFE_TO_MOUNT - MOUNT_PEG), -s / 2 + 2);
}

module chassis_bore() {
    s = JUNCTION_BOX;

    // hollow chamber (keep a floor; open top for drop-in)
    translate([0, 0, WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, s - WALL], center = true);

    // top opening — full width so cartridges clear
    translate([0, 0, s / 2 - WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, WALL + 0.2], center = true);

    // lid lip recess (light trap) around top rim
    translate([0, 0, s / 2 - LID_LIP / 2])
        cube([s - WALL, s - WALL, LID_LIP + 0.1], center = true);

    rotate([90, 0, 0])
        cylinder(h = D_LENS_TO_KNIFE + STEM_FLANGE_T + 1, d = TUBE_ID);

    rotate([0, 90, 0])
        cylinder(h = 2 * (D_KNIFE_TO_MOUNT - MOUNT_PEG) + 2, d = TUBE_ID, center = true);

    // screw bosses for lid
    for (x = [-1, 1], y = [-1, 1])
        translate([x * (s / 2 - 8), y * (s / 2 - 8), s / 2 - 12])
            cylinder(h = 14, d = 3.2);

    // 45° drop-in grooves for mirror cartridges (open at top)
    mirror_groove_cutouts();
}

module chassis_f_mounts() {
    for (side = [-1, 1])
        translate([side * D_KNIFE_TO_MOUNT, 0, 0])
            rotate([0, side * 90, 0]) {
                f_mount_male_solid(boss = MOUNT_PEG);
                if (SHOW_CRADLES)
                    arm_cradle_solid();
            }
}

module part_chassis() {
    color("SlateGray")
    difference() {
        chassis_structure();
        chassis_bore();
    }
    chassis_f_mounts();
}

// Lid with stepped light-trap lip that plugs into the top recess
module part_lid() {
    s = JUNCTION_BOX;
    color("DarkSlateGray")
    translate([0, 0, s / 2 + (SHOW_LID ? 0 : 0) + ex * 0.4]) {
        difference() {
            union() {
                // outer cap
                translate([0, 0, LID_T / 2])
                    cube([s, s, LID_T], center = true);
                // light-trap lip (fits into rim recess)
                translate([0, 0, -LID_LIP / 2 + 0.01])
                    cube([s - WALL - LID_GAP * 2,
                          s - WALL - LID_GAP * 2,
                          LID_LIP], center = true);
            }
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - 8), y * (s / 2 - 8), -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
        }
    }
}

module ghost_body(side = 1) {
    if ($preview && SHOW_GHOSTS)
        color("black", 0.12)
            translate([
                side * (D_KNIFE_TO_MOUNT + F_REGISTER_T + 15 + BODY_D / 2 + ex),
                0,
                -8
            ])
                cube([BODY_D, BODY_W * 0.8, BODY_H * 0.7], center = true);
}

module ghost_lens() {
    if ($preview && SHOW_GHOSTS)
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
        color("gold", 0.45) {
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

    if (SHOW_LID)
        part_lid();

    // Drop-in path: EXPLODED lifts cartridges above the box
    mirror_z = EXPLODED ? (JUNCTION_BOX / 2 + 40) : 0;
    mirror_pair(show_mirrors = $preview, explode_z = mirror_z);

    ghost_body(-1);
    ghost_body(1);
    ghost_lens();
    optical_axis_guides();
    echo("V cartridge: tip at center, arms to back wall, coatings OUT; SHOW_LID=", SHOW_LID);
    echo(str("PATH_TOTAL=", PATH_TOTAL, " mm"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction" || PART == "stem" ||
        PART == "arm_l" || PART == "arm_r")
        part_chassis();
    else if (PART == "shims")
        shim_set();
    else if (PART == "f_mount")
        f_mount_male_solid(boss = 0);
    else if (PART == "lid")
        part_lid();
    else if (PART == "mirror_tray")
        mirror_L_cartridge(show_mirrors = false);
    else
        assembly();
}

export_part();
