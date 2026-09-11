// =============================================================================
// WATCH_ME.scad  — KEEP THIS OPEN (Automatic Reload and Preview)
// =============================================================================
// Junction box + 3 bolt-on tubes (each tube is a wall cookie; print cookie on bed).
// Mirrors drop in from the top. Arms toe in for OVERLAP_FRAC stitch overlap.
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
LID_LIP   = 3;
LID_GAP   = 0.3;

function stem_tube_len() = D_LENS_TO_KNIFE - JUNCTION_BOX / 2;
function arm_tube_len()  = D_KNIFE_TO_MOUNT - MOUNT_PEG - JUNCTION_BOX / 2;

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

// Local port frame: z=0 is the outer face, +Z is outward (away from box).
module port_screws() {
    for (a = [0, 90, 180, 270])
        rotate([0, 0, a])
            translate([PORT_SCREW_R, 0, 0])
                children();
}

module port_flange() {
    translate([0, 0, PORT_PATCH_T / 2])
        cube([PORT_PATCH, PORT_PATCH, PORT_PATCH_T], center = true);
}

module hex_nut_cut() {
    cylinder(h = PORT_NUT_T + 0.2, d = PORT_NUT_AF / cos(30), $fn = 6);
}

// Place children in each port's local frame (outer face at the cube surface).
module at_stem() {
    translate([0, -JUNCTION_BOX / 2, 0])
        rotate([90, 0, 0])
            children();
}

module at_arm(side) {
    rotate([0, 0, -side * arm_toe()])
        translate([side * JUNCTION_BOX / 2, 0, 0])
            rotate([0, side * 90, 0])
                children();
}

module at_each_port() {
    at_stem() children();
    at_arm(1) children();
    at_arm(-1) children();
}

module box_nut_bosses() {
    at_each_port()
        port_screws()
            translate([0, 0, -WALL - PORT_BOSS_H])
                cylinder(h = PORT_BOSS_H + 0.02, d = PORT_NUT_AF + 4.5);
}

module box_bore() {
    s = JUNCTION_BOX;

    translate([0, 0, WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, s - WALL], center = true);

    translate([0, 0, s / 2 - WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, WALL + 0.2], center = true);

    translate([0, 0, s / 2 - LID_LIP / 2])
        cube([s - WALL, s - WALL, LID_LIP + 0.1], center = true);

    for (x = [-1, 1], y = [-1, 1])
        translate([x * (s / 2 - 8), y * (s / 2 - 8), s / 2 - 12])
            cylinder(h = 14, d = 3.2);

    mirror_groove_cutouts();

    translate([0, 0, -s / 2 - 0.05]) {
        ScrewThread(1.01 * TRIPOD_MAJOR + 1.25 * TRIPOD_TOL,
                    WALL - TRIPOD_KEEP,
                    pitch = TRIPOD_PITCH, tolerance = TRIPOD_TOL);
        cylinder(h = 1.2, d1 = TRIPOD_MAJOR + 1.6, d2 = TRIPOD_MAJOR);
    }

    at_each_port() {
        // cookie recess in the outer wall
        translate([0, 0, -PORT_PATCH_T / 2])
            cube([PORT_PATCH + PORT_FIT, PORT_PATCH + PORT_FIT,
                  PORT_PATCH_T + 0.15], center = true);
        // light hole through the remaining wall
        translate([0, 0, -WALL / 2])
            cylinder(h = WALL + 2, d = TUBE_ID + 1, center = true);
    }
}

module box_fastener_cuts() {
    at_each_port()
        port_screws() {
            translate([0, 0, -WALL - PORT_BOSS_H - 0.2])
                cylinder(h = WALL + PORT_BOSS_H + 0.6, d = PORT_SCREW_D);
            translate([0, 0, -WALL - PORT_NUT_T])
                hex_nut_cut();
        }
}

module part_junction() {
    color("SlateGray")
    difference() {
        union() {
            difference() {
                cube([JUNCTION_BOX, JUNCTION_BOX, JUNCTION_BOX], center = true);
                box_bore();
            }
            box_nut_bosses();
        }
        box_fastener_cuts();
    }
}

module port_tube_solid(out_len) {
    difference() {
        union() {
            port_flange();
            translate([0, 0, PORT_PATCH_T])
                cylinder(h = out_len, d = TUBE_OD);
        }
        translate([0, 0, -1])
            cylinder(h = PORT_PATCH_T + out_len + 2, d = TUBE_ID);
        port_screws()
            translate([0, 0, -1])
                cylinder(h = PORT_PATCH_T + 2, d = PORT_SCREW_D);
    }
}

module part_stem() {
    color("SlateGray") {
        port_tube_solid(stem_tube_len());
        translate([0, 0, PORT_PATCH_T + stem_tube_len()])
            helicoid_nut();
    }
}

module part_arm(side = 1) {
    color("SlateGray")
        port_tube_solid(arm_tube_len());
    translate([0, 0, PORT_PATCH_T + arm_tube_len() + MOUNT_PEG]) {
        f_mount_male_solid(boss = MOUNT_PEG);
        if (SHOW_CRADLES)
            arm_cradle_solid();
    }
}

module part_lid() {
    s = JUNCTION_BOX;
    color("DarkSlateGray")
    translate([0, 0, s / 2 + (SHOW_LID ? 0 : 0) + ex * 0.4]) {
        difference() {
            union() {
                translate([0, 0, LID_T / 2])
                    cube([s, s, LID_T], center = true);
                translate([0, 0, -LID_LIP / 2 + 0.01])
                    cube([s - WALL - LID_GAP * 2,
                          s - WALL - LID_GAP * 2,
                          LID_LIP], center = true);
                lid_retain_tabs(lip = LID_LIP);
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
            rotate([0, 0, -side * arm_toe()])
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
            for (side = [-1, 1])
                rotate([0, 0, -side * arm_toe()])
                    rotate([0, side * 90, 0])
                        cylinder(h = D_KNIFE_TO_MOUNT + 2, d = 1.0);
        }
}

module assembly() {
    part_junction();

    at_stem()
        translate([0, 0, EXPLODED ? ex : 0])
            part_stem();

    for (side = [-1, 1])
        at_arm(side)
            translate([0, 0, EXPLODED ? ex : 0])
                part_arm(side);

    if (SHOW_LID)
        part_lid();

    mirror_z = EXPLODED ? (JUNCTION_BOX / 2 + 40) : 0;
    mirror_pair(show_mirrors = $preview, explode_z = mirror_z);

    ghost_body(-1);
    ghost_body(1);
    ghost_lens();
    optical_axis_guides();
    echo("Bolt-on tubes: print cookie on bed; 4× M3 + hex nuts per port");
    echo(str("PATH_TOTAL=", PATH_TOTAL, " mm  OVERLAP_FRAC=", OVERLAP_FRAC,
             "  arm_toe=", arm_toe(), " deg"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction")
        part_junction();
    else if (PART == "stem")
        part_stem();
    else if (PART == "arm_l")
        part_arm(-1);
    else if (PART == "arm_r")
        part_arm(1);
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
