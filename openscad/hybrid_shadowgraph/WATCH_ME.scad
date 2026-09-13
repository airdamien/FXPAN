// =============================================================================
// hybrid_shadowgraph/WATCH_ME.scad — same-image 50/50, T sharp / R shadowgraph
// =============================================================================
// Both DX bodies see the same frame (field_toe = 0).
// T is conjugate (shorter by the plate OPL). Both flanges say shadowgraph.
// Lens −Y. Plate at origin: R → +X, T → +Y. Open this file.
// ARM_MOUNT 0 = female 52×0.75 + nut pocket; 1 = printed F-bayonet (clocked).
// F_MOUNT_CLOCK: add if the first F-print locks 90° off.
// =============================================================================

include <params.scad>
include <../lib/threads.scad>
use <hybrid_tray.scad>
use <shims.scad>
use <../d7000_body.scad>
use <../taking_lens.scad>
use <../f_mount_male.scad>
use <../pi4_body.scad>
use <../monitor/display_mount.scad>
use <../monitor/monitor.scad>

/* [View] */
SHOW_LID = 1; // [0:hide, 1:show]
SHOW_PANELS = 1; // [0:hide, 1:show]
SHOW_MONITOR = 0; // [0:hide, 1:show]
SHOW_PI = 0; // [0:hide, 1:show]
SHOW_BODIES = 0; // [0:hide, 1:show]
SHOW_LENS = 0; // [0:hide, 1:show]

/* [Mount] */
ARM_MOUNT = 0; // [0:reverse ring, 1:integrated F]
F_MOUNT_CLOCK = 0;

screw_resolution = $preview ? 0.6 : 0.25;

ex = EXPLODED ? 55 : 0;
LID_T     = 4;
LID_LIP   = 3;
LID_GAP   = 0.3;
// In from the outer corner so the hex sits under the 90 mm plates.
LID_SCREW = 5;
// Nut center below the box top. M3×20: 4 lid + 12 to nut + nut + a bit past.
LID_NUT_DROP = 12;

function mount_stack()       = ARM_MOUNT ? F_FMOUNT_STACK : F_REV_STACK;
function stem_tube_len()     = D_LENS_TO_PLATE - JUNCTION_BOX / 2;
function base_tube_len()     = D_PLATE_TO_MOUNT - mount_stack() - JUNCTION_BOX / 2;
function reflect_tube_len()  = base_tube_len() + R_LEN_EXTRA;
function transmit_tube_len() = base_tube_len() - bs_t_comp();

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
    module stamp_fast(word) {
        // Condensed italic + a little extra shear so it reads like it's moving.
        translate([8.6, -0.15])
            multmatrix([[1, 0.22, 0], [0, 1, 0]])
                text(word, size = 2.7,
                     font = "Avenir Next Condensed:style=Heavy Italic",
                     halign = "left", valign = "center", spacing = 1.06);
    }
    translate([0, 0, PORT_PATCH_T - t])
        linear_extrude(t + 0.15) {
            if (kind == "R")
                translate([-e, 0])
                    rotate(90) {
                        stamp("R");
                        stamp_fast("shadowgraph");
                    }
            else
                // Same clock as hybrid T: rotate 180 so the face reads
                // upright from the tube. Full word, same as R.
                translate([0, -e])
                    rotate(180) {
                        stamp("T");
                        stamp_fast("shadowgraph");
                    }
        }
}

module hex_nut_cut() {
    cylinder(h = PORT_NUT_T + 0.2, d = PORT_NUT_AF / cos(30), $fn = 6);
}

// Camera-end rectangle for an M3 nut; radial 3.2 hole so a set screw
// pinches the reverse ring. az is flange-mark up (R: 180, T: −90).
// Razor at the mouth of R: 0.42 mm slot through +Y to the axis.
// Soft Fourier cutoff (~8 mm early of the 135 rear focus).
module knife_slot(out_len) {
    t = 0.42;
    insert = 8.0;
    translate([0, TUBE_OD / 4, out_len - insert / 2])
        cube([t, TUBE_OD / 2 + 2, insert], center = true);
}

module rev_lock_cuts(out_len, az = 180) {
    z0 = out_len - F_REV_LEN / 2;
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

    mirror_groove_cutouts();

    translate([0, 0, -s / 2 - 0.05]) {
        cylinder(h = tripod_hole_h() + 0.1, d = TRIPOD_INSERT_D);
        cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
    }

    at_each_port()
        translate([0, 0, -WALL / 2])
            cylinder(h = WALL + 2, d = TUBE_ID + 1, center = true);
}

// M3 hex in each top corner. Slot opens on ±Y so the stem / T plates cover it.
module lid_body_fastener_cuts() {
    s = JUNCTION_BOX;
    nut_z = s / 2 - LID_NUT_DROP;
    module nut_hex() {
        rotate([0, 0, 30])
            cylinder(h = PORT_NUT_T + 0.25,
                     d = PORT_NUT_AF / cos(30), $fn = 6, center = true);
    }
    for (sx = [-1, 1], sy = [-1, 1]) {
        px = sx * (s / 2 - LID_SCREW);
        py = sy * (s / 2 - LID_SCREW);
        translate([px, py, nut_z - 4])
            cylinder(h = s / 2 - nut_z + 5, d = PORT_SCREW_D);
        // Hex tunnel to the ±Y face; stem / T plates cover the opening.
        hull() {
            translate([px, py, nut_z])
                nut_hex();
            translate([px, sy * (s / 2 + 0.2), nut_z])
                nut_hex();
        }
    }
}

module box_fastener_cuts() {
    lid_body_fastener_cuts();
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
                translate([0, 0, out_len - F_REV_LEN])
                    ScrewThread(1.01 * F_REV_MAJOR + 1.25 * F_REV_TOL,
                                F_REV_LEN + 0.3,
                                pitch = F_REV_PITCH, tolerance = F_REV_TOL);
                rev_lock_cuts(out_len, mark == "T" ? -90 : 180);
                f_pin_line_cut(out_len, mark == "T" ? -90 : 180);
            }
        if (mark == "R")
            along_tube(rx, ry)
                knife_slot(out_len);
        if (mark != "")
            flange_marks(mark);
    }
    if (ARM_MOUNT)
        color("Goldenrod")
            along_tube(rx, ry)
                translate([0, 0, out_len])
                    // Raw forks at +X. Pin is 90° left of up (R −X, T −Y).
                    f_mount_on_tube((mark == "T" ? 0 : -90) + F_MOUNT_CLOCK);
    else if ($preview && !SHOW_BODIES)
        color("Goldenrod", 0.55)
            along_tube(rx, ry)
                translate([0, 0, out_len])
                    difference() {
                        cylinder(h = F_REV_STACK, d = 62);
                        translate([0, 0, -0.1])
                            cylinder(h = F_REV_STACK + 0.2, d = F_BORE);
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
                display_lid_bosses(LID_T);
            }
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW), -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
            display_lid_cuts(LID_T, LID_LIP);
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
                translate([0, 0, out_len + (ARM_MOUNT ? F_FMOUNT_STACK : 0) + ex])
                    d7000_body(roll);
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

    if (SHOW_PANELS) {
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
    }

    hybrid_pair(show_glass = $preview,
                explode_z = EXPLODED ? (JUNCTION_BOX / 2 + 40) : 0);

    if (SHOW_LID)
        part_lid();
    if (SHOW_MONITOR || SHOW_PI)
        translate([0, 0, JUNCTION_BOX / 2 + LID_T + (EXPLODED ? ex * 0.4 : 0)]) {
            if (SHOW_MONITOR)
                display_mount();
            monitor_easel() {
                if (SHOW_MONITOR)
                    monitor_ghost();
                if (SHOW_PI)
                    monitor_pi();
            }
        }

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
    echo(str("hybrid shadowgraph: 50x50x1 S1 toward lens; ARM_MOUNT=", ARM_MOUNT,
             " (", ARM_MOUNT ? "integrated F" : "reverse ring", ")"));
    echo(str("PATH_TOTAL=", PATH_TOTAL, " mm  same-image  field_toe=",
             field_toe(), " deg  R extra=", R_LEN_EXTRA, " mm"));
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
    else if (PART == "display_mount")
        display_mount_print();
    else if (PART == "hybrid_tray")
        hybrid_cartridge(show_glass = false);
    else
        assembly();
}

export_part();
