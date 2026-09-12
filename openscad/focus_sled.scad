// =============================================================================
// focus_sled.scad — two NVIDIA PCB rulers: rail + tilted target
// =============================================================================
// Flat ruler on the table, toward the lens (−Y). Sled slides on it = distance.
// Second ruler drops into the slot and leans 30° away from the lens.
// Only a thin band is sharp; the ticks tell you which way to slide.
// Side V-notches read the rail at the closest (bottom) face of the target.
//
// NVIDIA ruler ≈ 1.5" × 1.6 mm FR4. Edit RAIL_W / RAIL_T if yours differs.
// Print on the LEFT side (large flat X face) so the tilt is walls, no support.
// =============================================================================

/* [Ruler] */
RAIL_W = 38.2;
RAIL_T = 1.60;
SLIDE  = 0.50;

/* [Sled] */
TILT   = 30;
GRAB   = 26;
WALL   = 2.8;
BASE_L = 34;
BASE_H = 10;

/* [View] */
SHOW_RULERS = 1; // [0:hide, 1:show]

$fn = 48;

slot_w = RAIL_W + SLIDE;
slot_t = RAIL_T + SLIDE;
base_w = slot_w + 2 * WALL;
hold_y = GRAB * sin(TILT) + slot_t + WALL + 2;
hold_z = GRAB * cos(TILT) + WALL + 2;

// y=0 is the front face of the target (closest to the lens). −Y = lens.

module rail_groove() {
    translate([0, hold_y / 2 - BASE_L / 2, slot_t / 2 - 0.05])
        cube([slot_w, BASE_L + hold_y + 2, slot_t], center = true);
}

module target_pocket() {
    // Floor at z≈2 in the tilted frame so the ruler sits on plastic.
    rotate([-TILT, 0, 0]) {
        translate([0, slot_t / 2, 2 + (GRAB + 12) / 2])
            cube([slot_w, slot_t, GRAB + 12], center = true);
        // Lead-in on the top mouth.
        translate([0, slot_t / 2, GRAB + 6])
            rotate([45, 0, 0])
                cube([slot_w, 4, 4], center = true);
    }
}

module pointer_notches() {
    s = 3.0;
    for (x = [-1, 1])
        translate([x * (base_w / 2), 0, BASE_H])
            rotate([45, 0, 0])
                cube([WALL + 0.6, s, s], center = true);
}

module lens_arrow() {
    t = 0.55;
    translate([0, -BASE_L + 6, BASE_H - t])
        linear_extrude(t + 0.15)
            polygon([[0, -4.0], [-2.2, 1.4], [2.2, 1.4]]);
}

module body() {
    union() {
        translate([0, -BASE_L / 2, BASE_H / 2])
            cube([base_w, BASE_L, BASE_H], center = true);
        translate([0, hold_y / 2, hold_z / 2])
            cube([base_w, hold_y, hold_z], center = true);
        // Front lip so the target cannot slide toward the lens.
        translate([0, -WALL / 2, 5])
            cube([base_w, WALL, 10], center = true);
    }
}

module sled() {
    difference() {
        body();
        rail_groove();
        target_pocket();
        pointer_notches();
        lens_arrow();
    }
}

module ghost_rail() {
    color("ForestGreen", 0.4)
        translate([0, 30, RAIL_T / 2])
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
