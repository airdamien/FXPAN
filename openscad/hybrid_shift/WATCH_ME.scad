// =============================================================================
// hybrid_shift/WATCH_ME.scad  — pano L: shifted DX, no tube toe
// =============================================================================
// Same stitch as hybrid. Cookies and M3s stay on the 90 mm faces; only
// the R/T tube axes shift by sensor_shift() (~9.4 mm). No tube toe.
// SHELL inner = PETG lining, outer = PCTG.
// Lens −Y. Plate at origin: R → +X, T → +Y. Open this file.
// ARM_MOUNT 0 = female 52×0.75 + nut pocket; 1 = printed F-bayonet (clocked).
// F_MOUNT_CLOCK: add if the first F-print locks 90° off.
// STEM 0 = helicoid + L39 (EL-Nikkor 135). STEM 1 = female F (50 mm test).
// STEM 2 = helicoid + M62 (EL-Nikkor 180, infinity).
// F 50 uses the 54 mm camera tubes + 2 mm cookies (ARMS=1). 135/180 keep 72 / 4.
// Brace: triangle under the box + both body 1/4-20s. Tripod insert in the brace.
// F_STEM_CLOCK: add if the first F50 stem locks off the index.
// EL180_M62_PITCH: 1.0 default; 0.75 if the 180 will not start.
// =============================================================================

/* [Part] */
PART = "assembly"; // [assembly:Assembly, chassis:Chassis, stem:Stem 135/180, stem_f50:Stem F 50, arm_r:Arm R 72 mm, arm_t:Arm T 72 mm, arm_r_s:Arm R F50, arm_t_s:Arm T F50, arm_r_sf:Arm R F50 printed F, arm_t_sf:Arm T F50 printed F, lid:Lid, display_mount:Display mount, hybrid_tray:Tray, brace:Tripod brace, shims:Shims, elnikkor_adapter:EL 135 adapter, el180_adapter:EL 180 adapter]

/* [Stem] */
STEM = 0; // [0:EL-Nikkor 135, 1:F-mount 50, 2:EL-Nikkor 180]
ARMS = 0; // [0:72 mm 135/180, 1:54 mm F 50]

include <params.scad>
include <../lib/threads.scad>
include <../lib/part_stamp.scad>
use <hybrid_tray.scad>
use <shims.scad>
use <../d7000_body.scad>
use <../taking_lens.scad>
use <../f_mount_male.scad>
use <../f_mount_female.scad>
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
SHOW_BRACE = 1; // [0:hide, 1:show]

/* [Shell] */
SHELL = "full"; // [full:Full (one material), inner:Inner PETG, outer:Outer PCTG]

/* [Mount] */
ARM_MOUNT = 0; // [0:reverse ring, 1:integrated F]
F_MOUNT_CLOCK = 0;

F_STEM_CLOCK = 0;
EL180_M62_PITCH = 1.0; // [0.75, 1.0]

screw_resolution = $preview ? 0.6 : 0.25;

ex = EXPLODED ? 55 : 0;
LID_T     = 4;
LID_LIP   = 3;
LID_GAP   = 0.3;
// In from the outer corner so the hex sits under the 90 mm plates.
LID_SCREW = 5;
// Nut center below the box top. M3×20: 4 lid + 12 to nut + nut + a bit past.
LID_NUT_DROP = 12;

function printed_f()         =
    ARM_MOUNT
    || PART == "arm_r_f" || PART == "arm_t_f"
    || PART == "arm_r_sf" || PART == "arm_t_sf";
function mount_stack()       = printed_f() ? F_FMOUNT_STACK : F_REV_STACK;
function f50_kit()           =
    ARMS || STEM == 1 || PART == "stem_f50"
    || PART == "arm_r_s" || PART == "arm_t_s"
    || PART == "arm_r_sf" || PART == "arm_t_sf";
function patch_t()           = f50_kit() ? PORT_PATCH_T_SHORT : PORT_PATCH_T;
function stem_tube_len()     =
    ((STEM == 1 || PART == "stem_f50") ? D_LENS_TO_PLATE_F50 : D_LENS_TO_PLATE_LONG)
    - JUNCTION_BOX / 2;
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

function cam_patch() = PORT_PATCH;
// Local flange XY: R is world −Y, T is world +X.
function cam_axis(mark) =
    mark == "R" ? [0, -sensor_shift()] :
    mark == "T" ? [sensor_shift(), 0] : [0, 0];
function hs_tag(name) = str("hs_", name);
function hs_arm_tag(mark) =
    str("hs_arm_", mark == "T" ? "t" : "r",
        f50_kit() ? "s" : "",
        printed_f() ? "f" : "");

module mm_split() {
    if (SHELL == "inner")
        intersection() { children(0); children(1); }
    else if (SHELL == "outer")
        difference() { children(0); children(1); }
    else
        children(0);
}

module port_flange(patch = PORT_PATCH) {
    translate([0, 0, patch_t() / 2])
        cube([patch, patch, patch_t()], center = true);
}

// Engraved on the camera-side face (print flange on the bed).
// kind "R": local −X is world +Z. kind "T": local −Y is world +Z.
module flange_marks(kind, patch = PORT_PATCH) {
    t = 0.8;
    e = patch / 2 - 3.4;
    module stamp(letter) {
        translate([-4.6, 0])
            polygon([[0, 2.6], [-1.7, -1.4], [1.7, -1.4]]);
        translate([3.2, 0])
            text(letter, size = 5.2, font = "Liberation Sans:style=Bold",
                 halign = "center", valign = "center");
    }
    translate([0, 0, patch_t() - t])
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
    // Cookie + M3s on the +X face center. Bore is cam_axis("R") in this frame.
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

module at_each_bore() {
    at_stem() children();
    at_reflect()
        translate([cam_axis("R").x, cam_axis("R").y, 0])
            children();
    at_transmit()
        translate([cam_axis("T").x, cam_axis("T").y, 0])
            children();
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

    at_each_bore()
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

module box_lining_mask() {
    s = JUNCTION_BOX;
    L = INNER_LINING;
    difference() {
        translate([0, 0, (WALL - L) / 2])
            cube([s - 2 * (WALL - L),
                  s - 2 * (WALL - L),
                  s - (WALL - L)], center = true);
        translate([0, 0, WALL / 2])
            cube([s - 2 * WALL, s - 2 * WALL, s - WALL + 0.4], center = true);
    }
    at_each_bore()
        translate([0, 0, -WALL / 2])
            difference() {
                cylinder(h = WALL + 0.4, d = TUBE_ID + 1 + 2 * L, center = true);
                cylinder(h = WALL + 0.8, d = TUBE_ID + 1, center = true);
            }
}

module tube_lining_mask(out_len, rx = 0, ry = 0, mark = "") {
    L = INNER_LINING;
    along_cam(rx, ry, mark) {
        difference() {
            translate([0, 0, -patch_t() - 0.2])
                cylinder(h = patch_t() + out_len + 0.4, d = TUBE_ID + 2 * L);
            translate([0, 0, -patch_t() - 0.6])
                cylinder(h = patch_t() + out_len + 1.2, d = TUBE_ID);
        }
        if (printed_f())
            translate([0, 0, out_len])
                f_mount_path_liner(L);
    }
}

module lid_lining_mask() {
    s = JUNCTION_BOX;
    L = INNER_LINING;
    // Chamber side only: lip + tabs + lining. Not a core sandwich.
    translate([0, 0, s / 2 + ex * 0.4])
        translate([0, 0, (-40 + L) / 2])
            cube([s + 4, s + 4, 40 + L], center = true);
}

module part_junction() {
    color("SlateGray")
    mm_split() {
        difference() {
            cube([JUNCTION_BOX, JUNCTION_BOX, JUNCTION_BOX], center = true);
            box_bore();
            box_fastener_cuts();
            box_floor_stamp(hs_tag("chassis"), JUNCTION_BOX, WALL);
        }
        box_lining_mask();
    }
}

module along_tube(rx = 0, ry = 0) {
    translate([0, 0, patch_t()])
        rotate([rx, ry, 0])
            children();
}

module along_cam(rx = 0, ry = 0, mark = "") {
    ax = cam_axis(mark);
    translate([ax.x, ax.y, 0])
        along_tube(rx, ry)
            children();
}

module port_tube_solid(out_len, rx = 0, ry = 0, patch = PORT_PATCH, mark = "") {
    ax = cam_axis(mark);
    difference() {
        union() {
            port_flange(patch);
            if (out_len > 0.05)
                along_cam(rx, ry, mark)
                    cylinder(h = out_len, d = TUBE_OD);
            if (out_len > 0.05 && (rx != 0 || ry != 0))
                translate([ax.x, ax.y, patch_t()])
                    hull() {
                        cylinder(h = 0.2, d = TUBE_OD);
                        rotate([rx, ry, 0])
                            cylinder(h = 0.2, d = TUBE_OD);
                    }
        }
        along_cam(rx, ry, mark)
            translate([0, 0, -patch_t() - 2])
                cylinder(h = patch_t() + out_len + 4, d = TUBE_ID);
        port_screws()
            translate([0, 0, -1])
                cylinder(h = patch_t() + 2, d = PORT_SCREW_D);
    }
}

module part_stem() {
    color("SlateGray")
    mm_split() {
        difference() {
            union() {
                port_tube_solid(stem_tube_len());
                translate([0, 0, patch_t() + stem_tube_len()])
                    helicoid_nut();
            }
            flange_stamp(hs_tag("stem"), "", PORT_PATCH, patch_t());
        }
        tube_lining_mask(stem_tube_len());
    }
}

module part_stem_f50() {
    t = STEM_F50_PATCH;
    color("SlateGray")
    difference() {
        union() {
            translate([0, 0, t / 2])
                cube([PORT_PATCH, PORT_PATCH, t], center = true);
            translate([0, 0, t])
                f_mount_female(clock = F_STEM_CLOCK, od = TUBE_OD, back = 0);
        }
        translate([0, 0, -1])
            cylinder(h = t + f_fem_h(0) + 2, d = TUBE_ID);
        port_screws()
            translate([0, 0, -1])
                cylinder(h = t + 2, d = PORT_SCREW_D);
        flange_stamp(hs_tag("stem_f50"), "", PORT_PATCH, t);
    }
}

module stem_chosen() {
    if (STEM == 1)
        part_stem_f50();
    else
        part_stem();
}

function stem_label() =
    STEM == 1 ? "F 50" : STEM == 2 ? "EL 180" : "EL 135";

function el180_adapter_h() =
    EL_M42_LEN + EL180_ADAPTER_HEX + EL180_M62_LEN;

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
        translate([0, -(EL_ADAPTER_OD + EL_BORE) / 4 - 0.8,
                   h1 + h2 + h3 - STAMP_DEPTH])
            part_stamp_stack_cut(hs_tag("elnikkor"), size = 2.2);
    }
    if ($preview && !SHOW_LENS)
        color("DimGray", 0.45)
            translate([0, 0, h1 + h2 + h3])
                cylinder(h = 28, d = 47.5);
}

module part_el180_adapter() {
    h1 = EL_M42_LEN;
    h2 = EL180_ADAPTER_HEX;
    h3 = EL180_M62_LEN;
    color("SlateGray")
    difference() {
        union() {
            ScrewThread(HELICOID_MAJOR, h1, pitch = HELICOID_PITCH,
                        tolerance = HELICOID_TOL);
            translate([0, 0, h1])
                cylinder(h = h2, d = EL180_ADAPTER_OD, $fn = 6);
            translate([0, 0, h1 + h2])
                ScrewHole(EL180_M62_MAJOR, h3, pitch = EL180_M62_PITCH,
                          tolerance = EL180_M62_TOL)
                    cylinder(h = h3, d = EL180_ADAPTER_OD);
        }
        translate([0, 0, -0.2])
            cylinder(h = h1 + h2 + h3 + 0.4, d = EL180_BORE);
        translate([0, -(EL180_ADAPTER_OD + EL180_BORE) / 4 - 0.8,
                   h1 + h2 + h3 - STAMP_DEPTH])
            part_stamp_stack_cut(hs_tag("el180"), size = 2.2);
    }
    if ($preview && !SHOW_LENS)
        color("DimGray", 0.45)
            translate([0, 0, h1 + h2 + h3])
                el180_ghost();
}

module el180_ghost() {
    cylinder(h = 14, d = 72);
    translate([0, 0, 14])
        cylinder(h = 72, d = 80);
}

module part_camera_tube(out_len, rx = 0, ry = 0, mark = "") {
    p = cam_patch();
    color("SlateGray")
    mm_split() {
    intersection() {
    difference() {
        union() {
            port_tube_solid(out_len, rx, ry, p, mark);
            if (printed_f() && SHELL != "full")
                along_cam(rx, ry, mark)
                    translate([0, 0, out_len])
                        f_mount_path_liner(INNER_LINING);
        }
        if (!printed_f())
            along_cam(rx, ry, mark) {
                translate([0, 0, max(out_len - F_REV_LEN, -patch_t())])
                    ScrewThread(1.01 * F_REV_MAJOR + 1.25 * F_REV_TOL,
                                F_REV_LEN + 0.3,
                                pitch = F_REV_PITCH, tolerance = F_REV_TOL);
                if (out_len >= F_REV_LEN) {
                    rev_lock_cuts(out_len, mark == "T" ? -90 : 180);
                    f_pin_line_cut(out_len, mark == "T" ? -90 : 180);
                } else
                    f_pin_line_cut(out_len, mark == "T" ? -90 : 180);
            }
        if (mark != "")
            flange_marks(mark, p);
        if (mark != "")
            flange_stamp(hs_arm_tag(mark), mark, p, patch_t(),
                         STAMP_DEPTH, 2.8);
    }
        translate([-p, -p, 0])
            cube([p * 2, p * 2,
                  patch_t() + out_len + (printed_f() ? 16 : 8)]);
    }
        tube_lining_mask(out_len, rx, ry, mark);
    }
    if (SHELL != "inner") {
    if (printed_f())
        color("Goldenrod")
            along_cam(rx, ry, mark)
                translate([0, 0, out_len])
                    f_mount_on_tube((mark == "T" ? 0 : -90) + F_MOUNT_CLOCK,
                                    peg_face = (SHELL == "full" ? 0
                                                : INNER_LINING));
    else if ($preview && !SHOW_BODIES)
        color("Goldenrod", 0.55)
            along_cam(rx, ry, mark)
                translate([0, 0, out_len])
                    difference() {
                        cylinder(h = F_REV_STACK, d = 62);
                        translate([0, 0, -0.1])
                            cylinder(h = F_REV_STACK + 0.2, d = F_BORE);
                    }
    }
}

module part_lid() {
    s = JUNCTION_BOX;
    color("DarkSlateGray")
    mm_split() {
    translate([0, 0, s / 2 + ex * 0.4]) {
        difference() {
            union() {
                translate([0, 0, LID_T / 2])
                    cube([s, s, LID_T], center = true);
                translate([0, 0, -LID_LIP / 2 + 0.01])
                    difference() {
                        cube([s - WALL - LID_GAP * 2,
                              s - WALL - LID_GAP * 2,
                              LID_LIP], center = true);
                        cube([s - 2 * WALL - 0.4,
                              s - 2 * WALL - 0.4,
                              LID_LIP + 0.4], center = true);
                    }
                lid_retain_tabs(lip = LID_LIP);
                display_lid_bosses(LID_T);
                display_lid_nut_pads(LID_LIP);
            }
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW), -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
            display_lid_cuts(LID_T, LID_LIP);
            plate_stamp(hs_tag("lid"), s, LID_T);
            lid_inner_ribs();
        }
    }
        lid_lining_mask();
    }
}

module ghost_body_at(mark = "") {
    if ($preview && SHOW_GHOSTS)
        color("black", 0.12)
            along_cam(0, 0, mark)
                translate([0, 0, D_PLATE_TO_MOUNT - JUNCTION_BOX / 2
                                 + 15 + BODY_D / 2 + ex])
                    cube([BODY_W * 0.8, BODY_H * 0.7, BODY_D], center = true);
}

module taking_lens_at() {
    if (SHOW_LENS)
        color("DimGray", 0.92)
            at_stem()
                if (STEM == 1)
                    translate([0, 0, STEM_F50_PATCH + stem_tube_len() + f_fem_h(0)
                                     + (EXPLODED ? ex * 1.4 : 0)])
                        f50_ghost();
                else if (STEM == 2)
                    translate([0, 0, patch_t() + stem_tube_len() + HELICOID_LEN
                                     + el180_adapter_h()
                                     + (EXPLODED ? ex * 1.4 : 0)])
                        el180_ghost();
                else
                    translate([0, 0, patch_t() + stem_tube_len() + HELICOID_LEN
                                     + EL_M42_LEN + EL_ADAPTER_HEX + EL_M39_LEN
                                     + (EXPLODED ? ex * 1.4 : 0)])
                        taking_lens();
}

module camera_body_at(out_len, rx = 0, ry = 0, roll = 0, mark = "") {
    if (SHOW_BODIES)
        color("DimGray", 0.92)
            along_cam(rx, ry, mark)
                translate([0, 0, out_len + (printed_f() ? F_FMOUNT_STACK : 0) + ex])
                    d7000_body(roll);
}

// Both bodies upright (world +Z = camera top). R was −90 (upside down).
function body_roll_r() = 90;
function body_roll_t() = 180;

function brace_cam_d() = D_PLATE_TO_MOUNT + D7000_TRIPOD_IN;
function brace_r_xy() = [brace_cam_d(), -sensor_shift()];
function brace_t_xy() = [sensor_shift(), brace_cam_d()];
function brace_tripod_xy() =
    let (r = brace_r_xy(), t = brace_t_xy())
        [(r.x + t.x) / 3, (r.y + t.y) / 3];
function brace_cam_lift() =
    max(1, JUNCTION_BOX / 2 - D7000_TRIPOD_BELOW);
function brace_stamp_xy() =
    let (r = brace_r_xy(), t = brace_t_xy(),
         m = [(r.x + t.x) / 2, (r.y + t.y) / 2],
         n = m / norm(m))
        [m.x - n.x * 10, m.y - n.y * 10];

module brace_hex_grid_2d() {
    cell = BRACE_HEX_CELL;
    for (j = [-2:22], i = [-2:22])
        translate([(i + (j % 2) * 0.5) * cell, j * cell * sin(60)])
            rotate(30)
                circle(d = BRACE_HEX_D, $fn = 6);
}

module brace_hex_cuts_2d() {
    r = brace_r_xy();
    t = brace_t_xy();
    q = brace_tripod_xy();
    s = brace_stamp_xy();
    intersection() {
        difference() {
            offset(-1.8)
                offset(BRACE_WEB / 2)
                    polygon([[0, 0], r, t]);
            translate([0, 0])
                circle(d = BRACE_PAD_D + 4);
            translate(r)
                circle(d = BRACE_PAD_D + 4);
            translate(t)
                circle(d = BRACE_PAD_D + 4);
            translate(q)
                circle(d = BRACE_PAD_D + 4);
            translate(s)
                rotate(135)
                    square([78, 10], center = true);
        }
        brace_hex_grid_2d();
    }
}

module brace_slot_2d(p) {
    a = atan2(p.y, p.x);
    translate(p)
        rotate(a)
            hull() {
                translate([-BRACE_SLOT_L / 2, 0])
                    circle(d = BRACE_SLOT_W);
                translate([BRACE_SLOT_L / 2, 0])
                    circle(d = BRACE_SLOT_W);
            }
}

module brace_head_2d(p) {
    a = atan2(p.y, p.x);
    translate(p)
        rotate(a)
            hull() {
                translate([-BRACE_SLOT_L / 2, 0])
                    circle(d = BRACE_HEAD_D);
                translate([BRACE_SLOT_L / 2, 0])
                    circle(d = BRACE_HEAD_D);
            }
}

module brace_blank() {
    r = brace_r_xy();
    t = brace_t_xy();
    lift = brace_cam_lift();
    union() {
        linear_extrude(BRACE_T)
            union() {
                offset(BRACE_WEB / 2)
                    polygon([[0, 0], r, t]);
                translate([0, 0])
                    circle(d = BRACE_PAD_D);
                translate(r)
                    circle(d = BRACE_PAD_D);
                translate(t)
                    circle(d = BRACE_PAD_D);
                translate(brace_tripod_xy())
                    circle(d = BRACE_PAD_D);
            }
        translate([r.x, r.y, BRACE_T])
            cylinder(h = lift, d = BRACE_PAD_D);
        translate([t.x, t.y, BRACE_T])
            cylinder(h = lift, d = BRACE_PAD_D);
    }
}

module part_brace() {
    r = brace_r_xy();
    t = brace_t_xy();
    q = brace_tripod_xy();
    h = BRACE_T + brace_cam_lift();
    color("SlateGray")
    difference() {
        brace_blank();
        translate([0, 0, -0.2])
            cylinder(h = BRACE_T + 0.4, d = BRACE_SCREW_D);
        translate([0, 0, -0.05])
            cylinder(h = BRACE_HEAD_H + 0.1, d = BRACE_HEAD_D);
        translate([0, 0, -0.2])
            linear_extrude(h + 0.4)
                union() {
                    brace_slot_2d(r);
                    brace_slot_2d(t);
                }
        translate([0, 0, -0.05])
            linear_extrude(BRACE_HEAD_H + 0.1)
                union() {
                    brace_head_2d(r);
                    brace_head_2d(t);
                }
        translate([q.x, q.y, -0.05]) {
            cylinder(h = tripod_hole_h() + 0.15, d = TRIPOD_INSERT_D);
            cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
        }
        translate([0, 0, -0.2])
            linear_extrude(BRACE_T + 0.4)
                brace_hex_cuts_2d();
        translate([brace_stamp_xy().x, brace_stamp_xy().y, BRACE_T - STAMP_DEPTH])
            rotate(135)
                part_stamp_cut(hs_tag("brace"));
    }
}

module brace_at() {
    translate([0, 0, -JUNCTION_BOX / 2 - BRACE_T])
        part_brace();
}

module optical_axis_guides() {
    if ($preview)
        color("gold", 0.45) {
            rotate([90, 0, 0])
                cylinder(h = D_LENS_TO_PLATE + 2, d = 1.0);
            translate([0, -sensor_shift(), 0])
                rotate([0, 90, 0])
                    cylinder(h = D_PLATE_TO_MOUNT + 2, d = 1.0);
            translate([sensor_shift(), 0, 0])
                rotate([-90, 0, 0])
                    cylinder(h = D_PLATE_TO_MOUNT + 2, d = 1.0);
        }
}

module assembly() {
    part_junction();

    if (SHOW_PANELS) {
        at_stem()
            translate([0, 0, EXPLODED ? ex : 0])
                stem_chosen();

        if (STEM == 0)
            at_stem()
                translate([0, 0, patch_t() + stem_tube_len() + HELICOID_LEN
                                 + (EXPLODED ? ex * 1.4 : 0)])
                    part_elnikkor_adapter();
        if (STEM == 2)
            at_stem()
                translate([0, 0, patch_t() + stem_tube_len() + HELICOID_LEN
                                 + (EXPLODED ? ex * 1.4 : 0)])
                    part_el180_adapter();

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
                if (SHOW_PI) {
                    monitor_pi();
                }
            }
        }

    if (SHOW_BRACE)
        brace_at();

    at_reflect() {
        ghost_body_at("R");
        camera_body_at(reflect_tube_len(), rx = -field_toe(),
                       roll = body_roll_r(), mark = "R");
    }
    at_transmit() {
        ghost_body_at("T");
        camera_body_at(transmit_tube_len(), ry = -field_toe(),
                       roll = body_roll_t(), mark = "T");
    }
    taking_lens_at();
    optical_axis_guides();
    echo(str("hybrid_shift L: 50x50x1 S1 toward lens; ARM_MOUNT=", ARM_MOUNT,
             " (", ARM_MOUNT ? "integrated F" : "reverse ring", ")",
             " STEM=", STEM, " (", stem_label(), ")",
             " ARMS=", ARMS, " (", ARMS ? "54 mm F 50" : "72 mm 135/180", ")",
             " SHELL=", SHELL));
    echo(str("PATH_TOTAL=", PATH_TOTAL, " mm  stitch_w=", stitch_w(),
             " mm  sensor_shift=", sensor_shift(), " mm  field_toe=",
             field_toe(), " deg"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction")
        part_junction();
    else if (PART == "stem")
        stem_chosen();
    else if (PART == "stem_f50")
        part_stem_f50();
    else if (PART == "arm_r" || PART == "arm_r_s"
          || PART == "arm_r_f" || PART == "arm_r_sf")
        part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");
    else if (PART == "arm_t" || PART == "arm_t_s"
          || PART == "arm_t_f" || PART == "arm_t_sf")
        part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    else if (PART == "shims")
        shim_set();
    else if (PART == "elnikkor_adapter")
        part_elnikkor_adapter();
    else if (PART == "el180_adapter")
        part_el180_adapter();
    else if (PART == "lid")
        part_lid();
    else if (PART == "display_mount")
        display_mount_print();
    else if (PART == "hybrid_tray")
        hybrid_cartridge(show_glass = false);
    else if (PART == "brace")
        part_brace();
    else
        assembly();
}

export_part();
