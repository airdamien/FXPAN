// =============================================================================
// Ehybrid/WATCH_ME.scad  — pano L: one 50/50 plate, toed FF Sony α7
// =============================================================================
// Each camera looks at a different half of a stitch_w() image (field_toe).
// Lens −Y. Plate at origin: R → +X, T → +Y. Open this file.
// ARM_MOUNT 0 = female 52×0.75 (E reverse ring); 1 = printed E bayonet.
// E_MOUNT_CLOCK: add if the first E-print locks 90° off.
// =============================================================================

include <params.scad>
include <../lib/threads.scad>
use <hybrid_tray.scad>
use <shims.scad>
use <a7_body.scad>
use <../taking_lens.scad>
use <e_mount_male.scad>

/* [View] */
SHOW_LID = 1; // [0:hide, 1:show]
SHOW_BODIES = 0; // [0:hide, 1:show]
SHOW_LENS = 0; // [0:hide, 1:show]

/* [Mount] */
ARM_MOUNT = 0; // [0:reverse ring, 1:integrated E]
E_MOUNT_CLOCK = 0;

screw_resolution = $preview ? 0.6 : 0.25;

ex = EXPLODED ? 55 : 0;
LID_T     = 4;
LID_LIP   = 3;
LID_GAP   = 0.3;
// Inset from the outer wall. 4 put the Ø3.2 hole on the lip recess (no bite).
LID_SCREW = 2.5;
// Raspberry Pi HAT holes (58×49). Blind from the outer face so the lid stays light-tight.
// Board centered; USB/ethernet toward blank −X. M2.5 thread-forming, 1.5 mm floor.
PI_HOLE_D = 2.3;
PI_HOLE_Z = 2.5;
function pi_holes() = [
    [42.5 - 3.5,  3.5 - 28],
    [42.5 - 61.5, 3.5 - 28],
    [42.5 - 3.5,  52.5 - 28],
    [42.5 - 61.5, 52.5 - 28]
];

function mount_stack()       = ARM_MOUNT ? E_FMOUNT_STACK : E_REV_STACK;
function stem_tube_len()     = D_LENS_TO_PLATE - JUNCTION_BOX / 2;
function reflect_tube_len()  = D_PLATE_TO_MOUNT - mount_stack() - JUNCTION_BOX / 2;
function transmit_tube_len() = reflect_tube_len() - bs_t_comp();

module helicoid_nut(h = HELICOID_LEN) {
    ScrewHole(HELICOID_MAJOR, h, pitch = HELICOID_PITCH, tolerance = HELICOID_TOL)
        cylinder(h = h, d = HELICOID_MAJOR + 14);
}

module port_screws() {
    for (a = [45, 135, 225, 315])
        rotate([0, 0, a])
            translate([PORT_SCREW_R, 0, 0])
                children();
}

module port_flange() {
    translate([0, 0, PORT_PATCH_T / 2])
        cube([PORT_PATCH, PORT_PATCH, PORT_PATCH_T], center = true);
}

// Engraved on the camera-side face (print flange on the bed).
// kind "R": local −X is world +Z. kind "T": local −Y is world +Z.
module flange_marks(kind) {
    t = 0.8;
    e = PORT_PATCH / 2 - 3.4;
    module stamp(letter) {
        translate([-4.6, 0])
            polygon([[0, 2.6], [-1.7, -1.4], [1.7, -1.4]]);
        translate([3.2, 0])
            text(letter, size = 5.2, font = "Liberation Sans:style=Bold",
                 halign = "center", valign = "center");
    }
    translate([0, 0, PORT_PATCH_T - t])
        linear_extrude(t + 0.15) {
            if (kind == "R")
                translate([-e, 0])
                    rotate(90)
                        stamp("R");
            else
                translate([0, -e])
                    rotate(180)
                        stamp("T");
        }
}

module hex_nut_cut() {
    cylinder(h = PORT_NUT_T + 0.2, d = PORT_NUT_AF / cos(30), $fn = 6);
}

// Camera-end rectangle for an M3 nut; radial 3.2 hole so a set screw
// pinches the reverse ring. az is flange-mark up (R: 180, T: −90).
module rev_lock_cuts(out_len, az = 180) {
    z0 = out_len - E_REV_LEN / 2;
    r_mid = (TUBE_ID + TUBE_OD) / 4;
    nw = 5.5 + 0.2;
    nt = 2.4 + 0.2;
    floor_z = z0 - 5.5 / 2 - 0.2;
    rotate([0, 0, az]) {
        translate([0, 0, z0])
            rotate([0, 90, 0])
                cylinder(h = TUBE_OD / 2 + 1, d = PORT_SCREW_D);
        translate([r_mid, 0, (out_len + floor_z) / 2])
            cube([nt, nw, out_len - floor_z + 0.2], center = true);
    }
}

module at_stem() {
    translate([0, -JUNCTION_BOX / 2, 0])
        rotate([90, 0, 0])
            children();
}

module at_reflect() {
    translate([JUNCTION_BOX / 2, 0, 0])
        rotate([0, 90, 0])
            children();
}

module at_transmit() {
    translate([0, JUNCTION_BOX / 2, 0])
        rotate([-90, 0, 0])
            children();
}

module at_each_port() {
    at_stem() children();
    at_reflect() children();
    at_transmit() children();
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
        translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW), s / 2 - 12])
            cylinder(h = 14, d = 3.2);

    mirror_groove_cutouts();

    translate([0, 0, -s / 2 - 0.05]) {
        ScrewThread(1.01 * TRIPOD_MAJOR + 1.25 * TRIPOD_TOL,
                    WALL - TRIPOD_KEEP,
                    pitch = TRIPOD_PITCH, tolerance = TRIPOD_TOL);
        cylinder(h = 1.2, d1 = TRIPOD_MAJOR + 1.6, d2 = TRIPOD_MAJOR);
    }

    at_each_port()
        translate([0, 0, -WALL / 2])
            cylinder(h = WALL + 2, d = TUBE_ID + 1, center = true);
}

module box_fastener_cuts() {
    at_each_port()
        port_screws() {
            translate([0, 0, -WALL - 0.2])
                cylinder(h = WALL + 0.6, d = PORT_SCREW_D);
            translate([0, 0, -WALL - 0.05])
                hex_nut_cut();
        }
}

module part_junction() {
    color("SlateGray")
    difference() {
        cube([JUNCTION_BOX, JUNCTION_BOX, JUNCTION_BOX], center = true);
        box_bore();
        box_fastener_cuts();
    }
}

module along_tube(rx = 0, ry = 0) {
    translate([0, 0, PORT_PATCH_T])
        rotate([rx, ry, 0])
            children();
}

module port_tube_solid(out_len, rx = 0, ry = 0) {
    difference() {
        union() {
            port_flange();
            along_tube(rx, ry)
                cylinder(h = out_len, d = TUBE_OD);
            if (rx != 0 || ry != 0)
                translate([0, 0, PORT_PATCH_T])
                    hull() {
                        cylinder(h = 0.2, d = TUBE_OD);
                        rotate([rx, ry, 0])
                            cylinder(h = 0.2, d = TUBE_OD);
                    }
        }
        along_tube(rx, ry)
            translate([0, 0, -PORT_PATCH_T - 2])
                cylinder(h = PORT_PATCH_T + out_len + 4, d = TUBE_ID);
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

module part_elnikkor_adapter() {
    h1 = EL_M42_LEN;
    h2 = EL_ADAPTER_HEX;
    h3 = EL_M39_LEN;
    color("SlateGray")
    difference() {
        union() {
            ScrewThread(HELICOID_MAJOR, h1, pitch = HELICOID_PITCH,
                        tolerance = HELICOID_TOL);
            translate([0, 0, h1])
                cylinder(h = h2, d = EL_ADAPTER_OD, $fn = 6);
            translate([0, 0, h1 + h2])
                ScrewHole(EL_M39_MAJOR, h3, pitch = EL_M39_PITCH,
                          tolerance = EL_M39_TOL)
                    cylinder(h = h3, d = EL_ADAPTER_OD);
        }
        translate([0, 0, -0.2])
            cylinder(h = h1 + h2 + h3 + 0.4, d = EL_BORE);
    }
    if ($preview && !SHOW_LENS)
        color("DimGray", 0.45)
            translate([0, 0, h1 + h2 + h3])
                cylinder(h = 28, d = 47.5);
}

module part_camera_tube(out_len, rx = 0, ry = 0, mark = "") {
    color("SlateGray")
    difference() {
        port_tube_solid(out_len, rx, ry);
        if (ARM_MOUNT == 0)
            along_tube(rx, ry) {
                translate([0, 0, out_len - E_REV_LEN])
                    ScrewThread(1.01 * E_REV_MAJOR + 1.25 * E_REV_TOL,
                                E_REV_LEN + 0.3,
                                pitch = E_REV_PITCH, tolerance = E_REV_TOL);
                rev_lock_cuts(out_len, mark == "T" ? -90 : 180);
            }
        if (mark != "")
            flange_marks(mark);
    }
    if (ARM_MOUNT)
        color("Goldenrod")
            along_tube(rx, ry)
                translate([0, 0, out_len])
                    e_mount_on_tube((mark == "T" ? -90 : 0) + E_MOUNT_CLOCK);
    else if ($preview && !SHOW_BODIES)
        color("Goldenrod", 0.55)
            along_tube(rx, ry)
                translate([0, 0, out_len])
                    difference() {
                        cylinder(h = E_REV_STACK, d = 62);
                        translate([0, 0, -0.1])
                            cylinder(h = E_REV_STACK + 0.2, d = E_BORE);
                    }
}

module pi_mount_cuts() {
    for (p = pi_holes()) {
        translate([p[0], p[1], LID_T - PI_HOLE_Z])
            cylinder(h = PI_HOLE_Z + 0.2, d = PI_HOLE_D);
        translate([p[0], p[1], LID_T - 0.7])
            cylinder(h = 0.8, d1 = PI_HOLE_D, d2 = 4.0);
    }
}

module part_lid() {
    s = JUNCTION_BOX;
    color("DarkSlateGray")
    translate([0, 0, s / 2 + ex * 0.4]) {
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
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW), -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
            pi_mount_cuts();
        }
    }
}

module ghost_body_at() {
    if ($preview && SHOW_GHOSTS)
        color("black", 0.12)
            along_tube()
                translate([0, 0, D_PLATE_TO_MOUNT - JUNCTION_BOX / 2
                                 + 15 + BODY_D / 2 + ex])
                    cube([BODY_W * 0.8, BODY_H * 0.7, BODY_D], center = true);
}

module taking_lens_at() {
    if (SHOW_LENS)
        color("DimGray", 0.92)
            at_stem()
                translate([0, 0, PORT_PATCH_T + stem_tube_len() + HELICOID_LEN
                                 + EL_M42_LEN + EL_ADAPTER_HEX + EL_M39_LEN
                                 + (EXPLODED ? ex * 1.4 : 0)])
                    taking_lens();
}

module camera_body_at(out_len, rx = 0, ry = 0, roll = 0) {
    if (SHOW_BODIES)
        color("DimGray", 0.92)
            along_tube(rx, ry)
                translate([0, 0, out_len + (ARM_MOUNT ? E_FMOUNT_STACK : 0) + ex])
                    body_a7(roll);
}

module optical_axis_guides() {
    if ($preview)
        color("gold", 0.45) {
            rotate([90, 0, 0])
                cylinder(h = D_LENS_TO_PLATE + 2, d = 1.0);
            rotate([0, 90, 0])
                cylinder(h = D_PLATE_TO_MOUNT + 2, d = 1.0);
            rotate([-90, 0, 0])
                cylinder(h = D_PLATE_TO_MOUNT + 2, d = 1.0);
        }
}

module assembly() {
    part_junction();

    at_stem()
        translate([0, 0, EXPLODED ? ex : 0])
            part_stem();

    at_stem()
        translate([0, 0, PORT_PATCH_T + stem_tube_len() + HELICOID_LEN
                         + (EXPLODED ? ex * 1.4 : 0)])
            part_elnikkor_adapter();

    at_reflect()
        translate([0, 0, EXPLODED ? ex : 0])
            part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");

    at_transmit()
        translate([0, 0, EXPLODED ? ex : 0])
            part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");

    hybrid_pair(show_glass = $preview,
                explode_z = EXPLODED ? (JUNCTION_BOX / 2 + 40) : 0);

    if (SHOW_LID)
        part_lid();

    at_reflect() {
        ghost_body_at();
        camera_body_at(reflect_tube_len(), rx = -field_toe(), roll = -90);
    }
    at_transmit() {
        ghost_body_at();
        camera_body_at(transmit_tube_len(), ry = -field_toe(), roll = 180);
    }
    taking_lens_at();
    optical_axis_guides();
    echo(str("Ehybrid L: A7 FF 50x50x1 S1 toward lens; ARM_MOUNT=", ARM_MOUNT,
             " (", ARM_MOUNT ? "integrated E" : "52mm E reverse ring", ")"));
    echo(str("PATH_TOTAL=", PATH_TOTAL, " mm  stitch_w=", stitch_w(),
             " mm  field_toe=", field_toe(), " deg"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction")
        part_junction();
    else if (PART == "stem")
        part_stem();
    else if (PART == "arm_r")
        part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");
    else if (PART == "arm_t")
        part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    else if (PART == "shims")
        shim_set();
    else if (PART == "elnikkor_adapter")
        part_elnikkor_adapter();
    else if (PART == "lid")
        part_lid();
    else if (PART == "hybrid_tray")
        hybrid_cartridge(show_glass = false);
    else
        assembly();
}

export_part();
