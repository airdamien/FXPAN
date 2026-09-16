// =============================================================================
// bsplit/WATCH_ME.scad  — 50/50 plate fork (Automatic Reload and Preview)
// =============================================================================
// L-chassis: lens −Y, reflect +X, transmit +Y.
// Same bolt-on tubes as the panorama T. Open this file, not ../WATCH_ME.scad.
// ARM_MOUNT 0 = female 52×0.75 + nut pocket; 1 = printed F-bayonet (clocked).
// F_MOUNT_CLOCK: add if the first F-print locks 90° off.
// =============================================================================

include <params.scad>
include <../lib/threads.scad>
use <bs_tray.scad>
use <shims.scad>
use <../d7000_body.scad>
use <../taking_lens.scad>
use <../f_mount_male.scad>

/* [View] */
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
LID_SCREW = 4;

function mount_stack()       = ARM_MOUNT ? F_FMOUNT_STACK : F_REV_STACK;
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

module hex_nut_cut() {
    cylinder(h = PORT_NUT_T + 0.2, d = PORT_NUT_AF / cos(30), $fn = 6);
}

// Camera-end rectangle for an M3 nut; radial 3.2 hole so a set screw
// pinches the reverse ring. az is flange-mark up (R: 180, T: −90).

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

    translate([0, 0, -s / 2 - 0.05]) {
        cylinder(h = tripod_hole_h() + 0.1, d = TRIPOD_INSERT_D);
        cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
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

module along_tube() {
    translate([0, 0, PORT_PATCH_T])
        children();
}

module port_tube_solid(out_len) {
    difference() {
        union() {
            port_flange();
            along_tube()
                cylinder(h = out_len, d = TUBE_OD);
        }
        along_tube()
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

module part_camera_tube(out_len, lock_az = 180) {
    color("SlateGray")
    difference() {
        port_tube_solid(out_len);
        if (ARM_MOUNT == 0)
            along_tube() {
                translate([0, 0, out_len - F_REV_LEN])
                    f_rev_thread_cut();
                rev_lock_cuts(out_len, lock_az);
                f_pin_line_cut(out_len, lock_az);
            }
    }
    if (ARM_MOUNT)
        color("Goldenrod")
            along_tube()
                translate([0, 0, out_len])
                    // Raw forks at +X. Pin is 90° left of up (R −X, T −Y).
                    f_mount_on_tube((lock_az == -90 ? 0 : -90) + F_MOUNT_CLOCK);
    else if ($preview && !SHOW_BODIES)
        color("Goldenrod", 0.55)
            along_tube()
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
            }
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW), -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
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

module camera_body_at(out_len, roll = 0) {
    if (SHOW_BODIES)
        color("DimGray", 0.92)
            along_tube()
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

    at_stem()
        translate([0, 0, EXPLODED ? ex : 0])
            part_stem();

    at_stem()
        translate([0, 0, PORT_PATCH_T + stem_tube_len() + HELICOID_LEN
                         + (EXPLODED ? ex * 1.4 : 0)])
            part_elnikkor_adapter();

    at_reflect()
        translate([0, 0, EXPLODED ? ex : 0])
            part_camera_tube(reflect_tube_len());

    at_transmit()
        translate([0, 0, EXPLODED ? ex : 0])
            part_camera_tube(transmit_tube_len(), lock_az = -90);

    bs_pair(show_plate = $preview,
            explode_z = EXPLODED ? (JUNCTION_BOX / 2 + 40) : 0);

    at_reflect() {
        ghost_body_at();
        camera_body_at(reflect_tube_len(), roll = -90);
    }
    at_transmit() {
        ghost_body_at();
        camera_body_at(transmit_tube_len(), roll = 180);
    }
    taking_lens_at();
    optical_axis_guides();
    echo(str("bsplit: 50/50; R=+X T=+Y; ARM_MOUNT=", ARM_MOUNT,
             " (", ARM_MOUNT ? "integrated F" : "reverse ring", ")"));
    echo(str("PATH_TOTAL=", PATH_TOTAL, " mm  bs_t_comp=", bs_t_comp(), " mm"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction")
        part_junction();
    else if (PART == "stem")
        part_stem();
    else if (PART == "arm_r")
        part_camera_tube(reflect_tube_len());
    else if (PART == "arm_t")
        part_camera_tube(transmit_tube_len(), lock_az = -90);
    else if (PART == "shims")
        shim_set();
    else if (PART == "elnikkor_adapter")
        part_elnikkor_adapter();
    else if (PART == "lid")
        part_lid();
    else if (PART == "bs_tray")
        bs_cartridge(show_plate = false);
    else
        assembly();
}

export_part();
