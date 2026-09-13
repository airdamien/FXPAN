// Two rails. Each L is closed heel-to-tip so the arm takes bending.
// Flat pads on the lid (screws from above). Beam stays behind the case.
// https://www.printables.com/model/1041827-hamtysan-101-touchscreen-enclosure

use <monitor.scad>

LID_DISP_X = 32;
LID_HINGE_Y = 36;
DISP_NUT_AF = 5.7;
DISP_NUT_T  = 2.6;
DISP_SCREW_D = 3.2;

RAIL_T   = 12;
FOOT_H   = 6;
BEAM_R   = 5.5;
TIP_S    = 125;
MONITOR_TILT = 60;
CASE_H   = 154;

function lid_display_holes() = [
    for (x = [-LID_DISP_X, LID_DISP_X], y = [-32, 10])
        [x, y]
];

function display_mount_height() = FOOT_H;

function _easel_up() = [-cos(MONITOR_TILT), sin(MONITOR_TILT)];
function _easel_n()  = [sin(MONITOR_TILT), cos(MONITOR_TILT)];
function _easel_pt(t) = [LID_HINGE_Y, FOOT_H] + t * _easel_up();
function _rail_pt(t)  = _easel_pt(t) - BEAM_R * _easel_n();

module display_lid_bosses(lid_t) { }

module display_lid_cuts(lid_t, lip = 3) {
    for (p = lid_display_holes()) {
        translate([p[0], p[1], -lip - 0.2])
            cylinder(h = lid_t + lip + 0.4, d = DISP_SCREW_D);
        translate([p[0], p[1], -lip - 0.05])
            cylinder(h = DISP_NUT_T + 0.2, d = DISP_NUT_AF / cos(30), $fn = 6);
    }
}

module _beam(pts, r = BEAM_R) {
    for (i = [0 : len(pts) - 2])
        hull() {
            translate(pts[i]) circle(r);
            translate(pts[i + 1]) circle(r);
        }
}

module rail_profile() {
    translate([-38, 2])
        offset(r = 2)
            square([54, FOOT_H - 4]);
    _beam([
        [12, FOOT_H],
        _rail_pt(22),
        _rail_pt(50),
        _rail_pt(80),
        _rail_pt(110),
        _rail_pt(TIP_S),
    ]);
    // Heel to tip: closes the L so the beam cannot fold at the elbow.
    _beam([
        [-40, FOOT_H],
        _rail_pt(TIP_S),
    ], 5);
}

module case_easel_world_cutters() {
    monitor_easel()
        case_easel_rail_cutters();
}

module display_rail(side = 1) {
    difference() {
        translate([side * LID_DISP_X, 0, 0])
            rotate([90, 0, 90])
                linear_extrude(height = RAIL_T, center = true)
                    rail_profile();
        for (p = lid_display_holes())
            if (p[0] == side * LID_DISP_X)
                translate([p[0], p[1], -1])
                    cylinder(h = FOOT_H + 2, d = DISP_SCREW_D);
        case_easel_world_cutters();
    }
}

module display_mount() {
    color("Sienna") {
        display_rail(-1);
        display_rail(1);
    }
}

module display_mount_print() {
    translate([-60, 0, RAIL_T / 2])
        rotate([0, 0, -90])
            rotate([0, -90, 0])
                translate([LID_DISP_X, 0, 0])
                    display_rail(-1);
    translate([60, 0, RAIL_T / 2])
        rotate([0, 0, 90])
            rotate([0, 90, 0])
                translate([-LID_DISP_X, 0, 0])
                    display_rail(1);
}

module monitor_easel() {
    translate([0, LID_HINGE_Y, FOOT_H])
        rotate([-MONITOR_TILT, 0, 0])
            translate([0, -CASE_H / 2, 0])
                children();
}
