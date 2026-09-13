// Wormfingers HAMTYSAN 10.1" case. CC BY 4.0.
// https://www.printables.com/model/1041827-hamtysan-101-touchscreen-enclosure
// After this module: XY centered, outer back at Z=0, glass toward +Z.
// Native panel top is −Y (thin bezel). HDMI / board bay is +X.
// Pi sits on the outer back (chips −Z). M2.5 nuts open into the tray.

include <params.scad>
include <../lib/part_stamp.scad>
use <../pi4_body.scad>

BEZEL_STL  = "bezel.stl";
BOTTOM_STL = "case-bottom.stl";
WALL_STL   = "wall_mount.stl";

BEZEL_C  = [375.0, 315.0, 2.477];
BOTTOM_C = [124.206, 105.0, 0];
WALL_C   = [125.0, 105.0, 0];
WALL_PLATE = 5.0;
BOTTOM_H   = 18.162;
BEZEL_T    = 2.476;
INNER_FLOOR = 2.5;

EASEL_RAIL_X  = 32;
EASEL_SCREW_Y = 36;
EASEL_SCREW_D = 3.2;
EASEL_NUT_AF  = 5.7;
EASEL_NUT_T   = 2.6;
EASEL_RAIL_Z  = 11;

PI_SCREW_D = 2.8;
PI_NUT_AF  = 5.0;
PI_NUT_T   = 2.0;
// USB toward +Y (chin / lid = screen bottom). Parked in the +X +Y corner.
PI_CORNER_X = 70;
PI_CORNER_Y = 36;

function monitor_pi_holes() = [
    for (p = pi4_holes())
        [p[1] + PI_CORNER_X, -p[0] + PI_CORNER_Y]
];

module monitor_pi_at() {
    translate([PI_CORNER_X, PI_CORNER_Y, 0])
        rotate([0, 0, -90])
            children();
}

function monitor_case_height() = BOTTOM_H + BEZEL_T;

function case_easel_holes() = [
    for (x = [-EASEL_RAIL_X, EASEL_RAIL_X], y = [-EASEL_SCREW_Y, 0, EASEL_SCREW_Y])
        [x, y]
];

module case_easel_hole_cutters() {
    for (p = case_easel_holes())
        translate([p[0], p[1], -EASEL_RAIL_Z - 2])
            cylinder(h = EASEL_RAIL_Z + BOTTOM_H + 4, d = EASEL_SCREW_D, $fn = 24);
}

module case_easel_rail_cutters() {
    case_easel_hole_cutters();
    for (p = case_easel_holes())
        translate([p[0], p[1], -EASEL_RAIL_Z - 0.05])
            cylinder(h = EASEL_NUT_T + 0.3, d = EASEL_NUT_AF / cos(30), $fn = 6);
}

module pi_case_cutters() {
    for (p = monitor_pi_holes()) {
        translate([p[0], p[1], -1])
            cylinder(h = INNER_FLOOR + 2, d = PI_SCREW_D, $fn = 24);
        translate([p[0], p[1], INNER_FLOOR - PI_NUT_T])
            cylinder(h = PI_NUT_T + 0.2, d = PI_NUT_AF / cos(30), $fn = 6);
    }
}

module monitor_bezel() {
    translate(-BEZEL_C)
        import(BEZEL_STL, convexity = 6);
}

module monitor_bottom() {
    difference() {
        translate(-BOTTOM_C)
            import(BOTTOM_STL, convexity = 6);
        case_easel_hole_cutters();
        pi_case_cutters();
        translate([0, 72, INNER_FLOOR - STAMP_DEPTH])
            part_stamp_cut("case_back");
    }
}

module monitor_wall() {
    translate(-WALL_C)
        import(WALL_STL, convexity = 6);
}

module monitor_pi() {
    color("ForestGreen", 0.92)
        monitor_pi_at()
            mirror([0, 0, 1])
                pi4_body();
}

module monitor_ghost() {
    color("#4a4538")
        monitor_bottom();
    color("#5c5648")
        translate([0, 0, BOTTOM_H])
            monitor_bezel();
    color("#111318")
        translate([0, 0, BOTTOM_H + 0.4])
            cube([AA_W, AA_H, 0.3], center = true);
}
