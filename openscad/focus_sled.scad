// =============================================================================
// focus_sled.scad — two NVIDIA PCB rulers: rail + tilted target
// =============================================================================
// Two ramps meet at the upright-ruler insert (y=0). Print the −X chevron
// on the bed: tilt, ramps, and rail jaws are walls — no rectangular slot
// ceiling on a layer. 45° jaws pinch the rail’s top edges.
//
// Flat ruler on the table, toward the lens (−Y). Sled slides on it.
// Second ruler drops in at the peak and leans 30° away from the lens,
// sitting on a shelf above the sliding rail. V-notches at the insert.
//
// NVIDIA ruler ≈ 1.5" × 1.6 mm FR4. Edit RAIL_W / RAIL_T if yours differs.
// =============================================================================

include <lib/part_stamp.scad>

/* [Ruler] */
RAIL_W = 38.2;
RAIL_T = 1.60;
SLIDE  = 0.35;

/* [Sled] */
TILT  = 30;
GRAB  = 26;
WALL  = 2.8;
PEAK  = 36;
FRONT = 36;
TAIL  = 50;

/* [View] */
SHOW_RULERS = 1; // [0:hide, 1:show]

$fn = 48;

slot_w = RAIL_W + SLIDE;
slot_t = RAIL_T + SLIDE;
base_w = slot_w + 2 * WALL;
jaw    = slot_t; // 45°: extra width at the table equals height

// y=0 is the insert (closest face of the target). −Y = lens.

module chevron() {
    hull() {
        translate([0, -FRONT, 0.05])
            cube([base_w, 0.1, 0.1], center = true);
        translate([0, 0, 0.05])
            cube([base_w, 0.1, 0.1], center = true);
        translate([0, 0, PEAK])
            cube([base_w, 2.4, 0.1], center = true);
    }
    hull() {
        translate([0, TAIL, 0.05])
            cube([base_w, 0.1, 0.1], center = true);
        translate([0, 0, 0.05])
            cube([base_w, 0.1, 0.1], center = true);
        translate([0, 0, PEAK])
            cube([base_w, 2.4, 0.1], center = true);
    }
}

module rail_jaws() {
    len = FRONT + TAIL + 4;
    yc  = (TAIL - FRONT) / 2;
    hull() {
        translate([0, yc, 0])
            cube([slot_w + 2 * jaw, len, 0.05], center = true);
        translate([0, yc, slot_t])
            cube([slot_w, len, 0.05], center = true);
    }
}

// Shelf above the rail at the insert — upright ruler sits here, rail still passes.
module insert_seat() {
    translate([0, 2.5, slot_t + 1.5])
        cube([slot_w + 1.2, 10, 3.0], center = true);
}

module target_pocket() {
    // Bottom of the cut is above the rail + seat (tilted z=5).
    rotate([-TILT, 0, 0]) {
        translate([0, slot_t / 2, 5 + (GRAB + 12) / 2])
            cube([slot_w, slot_t, GRAB + 12], center = true);
        translate([0, slot_t / 2, GRAB + 9])
            rotate([45, 0, 0])
                cube([slot_w, 4, 4], center = true);
    }
}

module pointer_notches() {
    s = 3.0;
    for (x = [-1, 1])
        translate([x * (base_w / 2), 0, 10])
            rotate([45, 0, 0])
                cube([WALL + 0.6, s, s], center = true);
}

module lens_arrow() {
    t = 0.55;
    translate([0, -FRONT + 8, 3])
        rotate([atan(PEAK / FRONT), 0, 0])
            linear_extrude(t + 0.15)
                polygon([[0, -4.0], [-2.2, 1.4], [2.2, 1.4]]);
}

module sled() {
    difference() {
        union() {
            chevron();
            insert_seat();
        }
        rail_jaws();
        target_pocket();
        pointer_notches();
        lens_arrow();
        translate([base_w / 2 - STAMP_DEPTH, -FRONT / 2, 8])
            rotate([90, 0, 90])
                part_stamp_cut("focus_sled", size = 2.8);
    }
}

module ghost_rail() {
    color("ForestGreen", 0.4)
        translate([0, 20, RAIL_T / 2])
            cube([RAIL_W, 220, RAIL_T], center = true);
}

module ghost_target() {
    color("Gold", 0.55)
        rotate([-TILT, 0, 0])
            translate([0, RAIL_T / 2, 80])
                cube([RAIL_W, RAIL_T, 160], center = true);
}

sled();
if ($preview && SHOW_RULERS) {
    ghost_rail();
    ghost_target();
}
