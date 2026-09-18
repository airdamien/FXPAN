// FXPAN 65 plate cartridge. 75×75×1 50/50 at 45° on the origin; drop it in
// from +Z with S1 toward the lens (Edmund marks the coated side with a black
// dot). Thick frame holds the glass, open-top walls reach the lid lip, three
// port windows. Inner faces, plate window and beams are sawtoothed. No roof.
// Everything here derives from BS_SIZE, so BS_SIZE = 50 shrinks the whole cup.

include <params.scad>
include <../lib/part_stamp.scad>

POST_W         = 8.0;
POST_D         = 3.2;
POST_OUT       = 8.0;
FORK_CLEAR     = 0.4;
FORK_LEN       = 10.0;
SLIP           = 0.4;
SKIRT_T        = 3.4;
SKIRT_H        = 8.0;
FLOOR_T        = 2.0;
RIB_PITCH      = 2.8;
RIB_DEPTH      = 0.9;
// Chassis M3 nuts / screw tips can sit a hair proud of the inner wall.
FASTENER_RELIEF_D = 9.0;
FASTENER_RELIEF_H = 1.4;
LID_NUT_Z         = BOX_Z / 2 - LID_NUT_DROP;

function chamber_xy() = BOX_XY - 2 * WALL;
function inner()      = chamber_xy() - 2 * SLIP;
function half()       = inner() / 2;
function floor_z()    = -BOX_Z / 2 + WALL;
function wall_top()   = BOX_Z / 2 - LID_LIP_SEAT;
function slot_t()     = BS_THICK + BS_CLEAR * 2;
function plate_w()    = BS_SIZE + BS_CLEAR * 2;
function frame_top()  = frame_top_z();
function corner_y()   = half() * sqrt(2);
function shelf_z()    = -BS_SIZE / 2 - 0.15;

function retain_xy(side) =
    let (ly = side * (plate_w() / 2 + POST_OUT), a = -45)
        [-ly * sin(a), ly * cos(a)];

module place_plate(glass = false) {
    rotate([0, 0, -45])
        if (glass) {
            color("gold", 0.45)
                cube([BS_THICK, BS_SIZE, BS_SIZE], center = true);
        } else {
            bs_frame();
        }
}

module trap_ribs(len, h) {
    n = max(1, floor(len / RIB_PITCH));
    for (i = [0 : n - 1])
        translate([0, -len / 2 + (i + 0.5) * RIB_PITCH, 0])
            linear_extrude(height = h, center = true)
                polygon([
                    [0, -RIB_PITCH * 0.45],
                    [0,  RIB_PITCH * 0.45],
                    [RIB_DEPTH, 0]
                ]);
}

// One window per port face — do not punch the opposite wall.
module chamber_ports(sh) {
    d = TUBE_ID + 0.6;
    t = SKIRT_T;
    w = t + 6;
    translate([0, -half() + t / 2, 0])
        rotate([90, 0, 0])
            cylinder(h = w, d = d, center = true);
    translate([half() - t / 2, cam_axis("R", sh).y, 0])
        rotate([0, 90, 0])
            cylinder(h = w, d = d, center = true);
    translate([cam_axis("T", sh).x, half() - t / 2, 0])
        rotate([-90, 0, 0])
            cylinder(h = w, d = d, center = true);
}

// Cross-hatch V-grooves in the plane z. bite < 0 cuts −Z, > 0 cuts +Z.
module hatch_ribs(z, bite, span) {
    n = max(1, floor(span / RIB_PITCH));
    module row(along_x) {
        for (i = [0 : n - 1]) {
            u = -span / 2 + (i + 0.5) * RIB_PITCH;
            translate(along_x ? [0, u, z] : [u, 0, z])
                rotate(along_x ? [90, 0, 90] : [90, 0, 0])
                    linear_extrude(height = span, center = true)
                        polygon([
                            [-RIB_PITCH * 0.45, 0],
                            [ RIB_PITCH * 0.45, 0],
                            [0, bite]
                        ]);
        }
    }
    row(true);
    row(false);
}

module floor_ribs() {
    hatch_ribs(floor_z() + FLOOR_T, -RIB_DEPTH, inner() - 2 * SKIRT_T - 2);
}

module lid_inner_ribs() {
    // 45° square bars: reliable boolean (triangular hatch_ribs sealed shut).
    span = BOX_XY - 2 * WALL - 2;
    p = RIB_PITCH;
    w = RIB_DEPTH * 2;
    n = max(1, floor(span / p));
    for (i = [0 : n - 1]) {
        u = -span / 2 + (i + 0.5) * p;
        translate([0, u, 0])
            rotate([45, 0, 0])
                cube([span + 2, w, w], center = true);
        translate([u, 0, 0])
            rotate([0, 45, 0])
                cube([w, span + 2, w], center = true);
    }
}

// Shallow pockets on the cup skin at the two clamp M3s + lid corners.
module chassis_fastener_relief(sh) {
    d = FASTENER_RELIEF_D;
    h = FASTENER_RELIEF_H;
    for (side = [-1, 1]) {
        s = clamp_xy("", side, sh);
        r = clamp_xy("R", side, sh);
        t = clamp_xy("T", side, sh);
        translate([s.x, -half(), s.y])
            rotate([90, 0, 0])
                translate([0, 0, -h])
                    cylinder(h = h + 0.3, d = d);
        translate([half(), r.y, -r.x])
            rotate([0, 90, 0])
                translate([0, 0, -h])
                    cylinder(h = h + 0.3, d = d);
        translate([t.x, half(), -t.y])
            rotate([-90, 0, 0])
                translate([0, 0, -h])
                    cylinder(h = h + 0.3, d = d);
    }
    for (sx = [-1, 1], sy = [-1, 1])
        translate([sx * (half() + d / 2 - h),
                   sy * (half() + d / 2 - h),
                   LID_NUT_Z])
            cylinder(h = PORT_NUT_T + 4, d = d, center = true);
}

module bs_frame() {
    w  = CARTRIDGE_WALL;
    py = plate_w();
    pz = plate_w();
    st = slot_t();
    z0 = floor_z();
    top = frame_top();
    reach = corner_y();
    face = st / 2 + w;
    th = st + w * 2;
    win_y = py - 6;
    win_z = pz - 6;

    difference() {
        translate([0, 0, (z0 + top) / 2])
            cube([th, 2 * reach, top - z0], center = true);

        translate([0, 0, (shelf_z() + top + 6) / 2])
            cube([st, py + 0.3, top + 6 - shelf_z()], center = true);

        translate([0, 0, top - 0.2])
            hull() {
                cube([st, py + 0.3, 0.4], center = true);
                translate([0, 0, 2.2])
                    cube([st + 1.8, py + 0.8, 0.4], center = true);
            }

        cube([40, win_y, win_z], center = true);

        // Outer cheeks, full length (slot faces stay smooth for the glass).
        for (sx = [-1, 1])
            translate([sx * face, 0, (z0 + top) / 2])
                rotate([0, 0, sx > 0 ? 180 : 0])
                    trap_ribs(2 * reach - 2, top - z0 - 2);

        // Inner window around the plate.
        for (sy = [-1, 1])
            translate([0, sy * win_y / 2, 0])
                rotate([0, 0, sy > 0 ? 90 : -90])
                    trap_ribs(th - 0.4, win_z - 0.4);
        translate([0, 0, win_z / 2])
            rotate([0, -90, 0])
                trap_ribs(win_y - 0.4, th - 0.4);
        translate([0, 0, -win_z / 2])
            rotate([0, 90, 0])
                trap_ribs(win_y - 0.4, th - 0.4);
    }
}

// Open-top cup: V-groove inner faces, then recut the three port windows.
module chamber_walls(sh, tag = "fxp_tray") {
    z0 = floor_z();
    h  = wall_top() - z0;
    t  = SKIRT_T;
    difference() {
        difference() {
            translate([0, 0, z0 + h / 2])
                cube([inner(), inner(), h], center = true);
            translate([0, 0, z0 + FLOOR_T + 50])
                cube([inner() - 2 * t, inner() - 2 * t, 100], center = true);
            floor_ribs();
            for (a = [0, 90, 180, 270])
                rotate([0, 0, a])
                    translate([half() - t, 0,
                               z0 + FLOOR_T + (h - FLOOR_T) / 2])
                        trap_ribs(inner() - 2 * t - 0.2, h - FLOOR_T - 0.2);
            tray_stamp(tag);
        }
        chamber_ports(sh);
    }
}

// Readable from the stem, looking at the −Y face.
module tray_stamp(tag = "fxp_tray") {
    translate([0, -half() + STAMP_DEPTH, floor_z() + 5])
        rotate([90, 0, 180])
            part_stamp_cut(tag, STAMP_DEPTH, STAMP_SIZE);
}

// Diagonal stiffener perpendicular to the plate — the dead quadrant no
// beam ever reaches, so it costs nothing optically.
module inactive_beams() {
    z0 = floor_z();
    L  = inner() * sqrt(2);
    rotate([0, 0, 45])
        difference() {
            translate([0, 0, z0 + SKIRT_H / 2])
                cube([SKIRT_T, L, SKIRT_H], center = true);
            for (sx = [-1, 1])
                translate([sx * SKIRT_T / 2, 0, z0 + SKIRT_H / 2])
                    rotate([0, 0, sx > 0 ? 180 : 0])
                        trap_ribs(L - 4, SKIRT_H - 0.4);
        }
}

module cartridge_posts() {
    top = frame_top();
    for (side = [-1, 1]) {
        p = retain_xy(side);
        translate([p[0], p[1], top + POST_H / 2])
            cube([POST_W, POST_D, POST_H], center = true);
    }
}

module fxp_cartridge(show_glass = true, sh, tag = "fxp_tray") {
    color("SteelBlue")
    intersection() {
        difference() {
            union() {
                place_plate(glass = false);
                chamber_walls(sh, tag);
                inactive_beams();
                cartridge_posts();
            }
            chassis_fastener_relief(sh);
        }
        translate([0, 0, floor_z() + (wall_top() - floor_z()) / 2])
            cube([inner(), inner(), wall_top() - floor_z() + 0.2],
                 center = true);
    }
    if (show_glass)
        intersection() {
            place_plate(glass = true);
            cube([inner(), inner(), BOX_Z - 1], center = true);
        }
}

module lid_retain_tabs(lip = 3) {
    for (side = [-1, 1]) {
        p = retain_xy(side);
        translate([p[0], p[1], 0])
            difference() {
                translate([0, 0, (-lip - FORK_LEN + 1.2) / 2])
                    cube([POST_W + 4, POST_D + 3.2,
                          lip + FORK_LEN + 1.2], center = true);
                translate([0, 0, -lip - FORK_LEN / 2 - 0.6])
                    cube([POST_W + FORK_CLEAR * 2,
                          POST_D + FORK_CLEAR * 2,
                          FORK_LEN], center = true);
            }
    }
}

module lid_retain_keepout(h = 10) {
    for (side = [-1, 1]) {
        p = retain_xy(side);
        translate([p[0], p[1], 0])
            cube([POST_W + 6, POST_D + 5, h], center = true);
    }
}

module fxp_pair(show_glass = true, explode_z = 0, sh, tag = "fxp_tray") {
    translate([0, 0, explode_z])
        fxp_cartridge(show_glass = show_glass, sh = sh, tag = tag);
}
