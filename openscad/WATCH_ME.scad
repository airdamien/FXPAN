// =============================================================================
// WATCH_ME.scad  — KEEP THIS OPEN (Automatic Reload and Preview)
// =============================================================================
// Junction box + 3 bolt-on tubes (print flange on the bed, bolt onto the flat wall).
// Flanges sit on the cube faces. Arm tubes toe toward the lens.
// ARM_MOUNT 0 = female 52×0.75 + nut pocket; 1 = printed F-bayonet (clocked).
// F_MOUNT_CLOCK: add if the first F-print locks 90° off.
// 50/50 plate fork (same full frame): openscad/bsplit/WATCH_ME.scad
// Hybrid pano L (toed DX + one 50/50 plate): openscad/hybrid/WATCH_ME.scad
// =============================================================================

include <params.scad>
include <lib/threads.scad>
use <f_mount_male.scad>
use <mirror_tray.scad>
use <shims.scad>
use <d7000_body.scad>
use <taking_lens.scad>

/* [View] */
SHOW_BODIES = 0; // [0:hide, 1:show]
SHOW_LENS = 0; // [0:hide, 1:show]

/* [Mount] */
ARM_MOUNT = 0; // [0:reverse ring, 1:integrated F]
F_MOUNT_CLOCK = 0;

screw_resolution = $preview ? 0.6 : 0.25;

ex = EXPLODED ? 55 : 0;
MOUNT_PEG = 4;
LID_T     = 4;
LID_LIP   = 3;
LID_GAP   = 0.3;
LID_SCREW = 4;            // inset from the outer edge (was 8: holes sat on the inner wall)

function mount_stack()   = ARM_MOUNT ? F_FMOUNT_STACK : F_REV_STACK;
function stem_tube_len() = D_LENS_TO_KNIFE - JUNCTION_BOX / 2;
function arm_tube_len()  = D_KNIFE_TO_MOUNT - mount_stack() - JUNCTION_BOX / 2;

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
// pinches the reverse ring. az=180 is local −X (world +Z on the +X arm).
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

// Place children in each port's local frame (outer face at the cube surface).
module at_stem() {
    translate([0, -JUNCTION_BOX / 2, 0])
        rotate([90, 0, 0])
            children();
}

module at_arm(side) {
    translate([side * JUNCTION_BOX / 2, 0, 0])
        rotate([0, side * 90, 0])
            children();
}

module at_each_port() {
    at_stem() children();
    at_arm(1) children();
    at_arm(-1) children();
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
            // hex opens to the inner face; stays inside the remaining wall
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

// Cookie stays in XY. Tube leans `toe` deg about +X (world −Y / toward the lens).
module along_tube(toe = 0) {
    translate([0, 0, PORT_PATCH_T])
        rotate([toe, 0, 0])
            children();
}

module port_tube_solid(out_len, toe = 0) {
    difference() {
        union() {
            port_flange();
            along_tube(toe)
                cylinder(h = out_len, d = TUBE_OD);
            if (toe != 0)
                translate([0, 0, PORT_PATCH_T])
                    hull() {
                        cylinder(h = 0.2, d = TUBE_OD);
                        rotate([toe, 0, 0])
                            cylinder(h = 0.2, d = TUBE_OD);
                    }
        }
        along_tube(toe)
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

// Male M42 → female L39×26 TPI for the El-Nikkor 50/2.8. Print male-down.
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

module part_arm(side = 1) {
    toe = arm_toe();
    color("SlateGray")
    difference() {
        port_tube_solid(arm_tube_len(), toe);
        if (ARM_MOUNT == 0)
            along_tube(toe) {
                translate([0, 0, arm_tube_len() - F_REV_LEN])
                    ScrewThread(1.01 * F_REV_MAJOR + 1.25 * F_REV_TOL,
                                F_REV_LEN + 0.3,
                                pitch = F_REV_PITCH, tolerance = F_REV_TOL);
                rev_lock_cuts(arm_tube_len(), side > 0 ? 180 : 0);
            }
    }
    if (ARM_MOUNT)
        color("Goldenrod")
            along_tube(toe)
                translate([0, 0, arm_tube_len()])
                    // Raw forks at +X. Pin is 90° left of up (+X arm −X, −X arm +X).
                    f_mount_on_tube((side > 0 ? -90 : 90) + F_MOUNT_CLOCK);
    else if ($preview && !SHOW_BODIES)
        color("Goldenrod", 0.55)
            along_tube(toe)
                translate([0, 0, arm_tube_len()])
                    difference() {
                        cylinder(h = F_REV_STACK, d = 62);
                        translate([0, 0, -0.1])
                            cylinder(h = F_REV_STACK + 0.2, d = F_BORE);
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
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW), -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
        }
    }
}

module ghost_body(side = 1) {
    if ($preview && SHOW_GHOSTS)
        color("black", 0.12)
            at_arm(side)
                along_tube(arm_toe())
                    translate([0, 0, arm_tube_len() + mount_stack() + 15 + BODY_D / 2 + ex])
                        cube([BODY_W * 0.8, BODY_H * 0.7, BODY_D], center = true);
}

module camera_body(side = 1) {
    if (SHOW_BODIES)
        color("DimGray", 0.92)
            at_arm(side)
                along_tube(arm_toe())
                    translate([0, 0, arm_tube_len() + (ARM_MOUNT ? F_FMOUNT_STACK : 0) + ex])
                        d7000_body(side > 0 ? -90 : 90);
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

module ghost_lens() {
    if ($preview && SHOW_GHOSTS && !SHOW_LENS)
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
                at_arm(side)
                    along_tube(arm_toe())
                        translate([0, 0, -JUNCTION_BOX / 2])
                            cylinder(h = D_KNIFE_TO_MOUNT + 2, d = 1.0);
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

    for (side = [-1, 1])
        at_arm(side)
            translate([0, 0, EXPLODED ? ex : 0])
                part_arm(side);

    mirror_z = EXPLODED ? (JUNCTION_BOX / 2 + 40) : 0;
    mirror_pair(show_mirrors = $preview, explode_z = mirror_z);

    ghost_body(-1);
    ghost_body(1);
    camera_body(-1);
    camera_body(1);
    ghost_lens();
    taking_lens_at();
    optical_axis_guides();
    echo(str("Bolt-on tubes: 4× M3 at 45°; ARM_MOUNT=", ARM_MOUNT,
             " (", ARM_MOUNT ? "integrated F" : "reverse ring", ")"));
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
    else if (PART == "elnikkor_adapter")
        part_elnikkor_adapter();
    else if (PART == "lid")
        part_lid();
    else if (PART == "mirror_tray")
        mirror_L_cartridge(show_mirrors = false);
    else
        assembly();
}

export_part();
