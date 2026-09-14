// =============================================================================
// focus_anchor.scad — rail zero at the taking-lens stem
// =============================================================================
// Sits on the table. Cups the 68 mm stem from below (same axis as the
// taking lens). Side wings hug the 90 mm stem cookie. The ruler slides
// in from the subject and butts that cookie — that face is distance zero.
// Pair with focus_sled.scad (same RAIL_W / RAIL_T).
//
// Print floor on the bed. No support. −Y = subject / sled, +Y = box.
// =============================================================================

include <lib/part_stamp.scad>

/* [Ruler] */
RAIL_W = 38.2;
RAIL_T = 1.60;
SLIDE  = 0.35;

/* [Stem] */
TUBE_OD  = 68;
PATCH    = 90;
PATCH_T  = 4;
AXIS_Z   = 45;
CUP_SLACK = 0.70;

/* [Anchor] */
WALL   = 3.2;
GRAB   = 30;
CUP_L  = 12;
BASE_H = 9;

/* [View] */
SHOW_GHOSTS = 1; // [0:hide, 1:show]

$fn = 64;

slot_w = RAIL_W + SLIDE;
slot_t = RAIL_T + SLIDE;
cup_d  = TUBE_OD + CUP_SLACK;
cup_r  = cup_d / 2;
wing_x = PATCH / 2 + 0.30;
base_w = PATCH + 2 * WALL + 0.6;
base_y0 = -GRAB;
base_y1 = 0;

// y=0 is the cookie’s outer face (ruler zero / stem flange).
// +Y into the box. −Y toward the sled.

module floor_plate() {
    translate([0, (base_y0 + base_y1) / 2, BASE_H / 2])
        cube([base_w, base_y1 - base_y0, BASE_H], center = true);
}

module cookie_wings() {
    for (s = [-1, 1])
        translate([s * (wing_x + WALL / 2), PATCH_T / 2, 28])
            cube([WALL, PATCH_T, 56], center = true);
}

module tube_cup() {
    w = cup_d + 2 * WALL;
    h = AXIS_Z + cup_r + 2;
    translate([0, -CUP_L / 2, h / 2])
        cube([w, CUP_L, h], center = true);
}

module tube_cut() {
    translate([0, 1, AXIS_Z])
        rotate([90, 0, 0])
            cylinder(h = CUP_L + PATCH_T + 2, d = cup_d);
    // Open top — drop the stem in, or slide along −Y under the lens.
    translate([0, -CUP_L / 2, AXIS_Z + cup_r / 2 + 20])
        cube([cup_d, CUP_L + 2, cup_r + 40], center = true);
}

module ruler_tunnel() {
    translate([0, (base_y0 - 0.2) / 2, slot_t / 2 - 0.05])
        cube([slot_w, -base_y0 + 0.6, slot_t], center = true);
}

module lens_arrow() {
    t = 0.55;
    translate([0, -GRAB + 8, BASE_H - t])
        linear_extrude(t + 0.15)
            polygon([[0, 4.0], [-2.2, -1.4], [2.2, -1.4]]);
}

module body() {
    union() {
        floor_plate();
        cookie_wings();
        tube_cup();
    }
}

module anchor() {
    difference() {
        body();
        tube_cut();
        ruler_tunnel();
        lens_arrow();
        translate([base_w / 2 - STAMP_DEPTH, -GRAB / 2, BASE_H / 2])
            rotate([90, 0, 90])
                part_stamp_cut("focus_anchor", size = 2.6);
    }
}

module ghost_cookie() {
    color("SlateGray", 0.35)
        translate([0, PATCH_T / 2, PATCH / 2])
            cube([PATCH, PATCH_T, PATCH], center = true);
}

module ghost_tube() {
    color("SlateGray", 0.35)
        translate([0, -CUP_L / 2, AXIS_Z])
            rotate([90, 0, 0])
                cylinder(h = CUP_L, d = TUBE_OD, center = true);
}

module ghost_rail() {
    color("ForestGreen", 0.4)
        translate([0, -80, RAIL_T / 2])
            cube([RAIL_W, 160, RAIL_T], center = true);
}

anchor();
if ($preview && SHOW_GHOSTS) {
    ghost_cookie();
    ghost_tube();
    ghost_rail();
}
