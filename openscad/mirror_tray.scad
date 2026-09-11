// One-piece V cartridge — joins at the middle (knife at origin).
// Tip in the chamber center; arms run toward the blank back wall (+Y).
// Coatings face OUT of the V. No back plate. Cannot flip a wing alone.

include <params.scad>

GROOVE_CLEAR   = 0.45;
CARTRIDGE_WALL = 2.2;
SPINE_W        = 3.5;
FLOOR_T        = 2.8;
RAIL_W         = 2.5;

module mirror_glass() {
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// Local: knife at Y=0, blade +Y (toward back after ±45° place).
// `out` = ±1 — local-X side that is OUTSIDE the V (coating / open face).
module mirror_wing_frame(out = 1) {
    pocket_y = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pocket_z = MIRROR_SIZE + MIRROR_CLEAR * 2;
    gx = out * (MIRROR_THICK / 2 + MIRROR_CLEAR);

    difference() {
        union() {
            translate([gx + out * (MIRROR_THICK / 2 + CARTRIDGE_WALL / 2),
                       MIRROR_SIZE / 2, 0])
                cube([CARTRIDGE_WALL,
                      pocket_y + CARTRIDGE_WALL,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            for (z = [-1, 1])
                translate([gx + out * (CARTRIDGE_WALL / 2),
                           MIRROR_SIZE / 2,
                           z * (pocket_z / 2 + CARTRIDGE_WALL / 2)])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                          pocket_y + CARTRIDGE_WALL,
                          CARTRIDGE_WALL], center = true);
            translate([gx + out * (CARTRIDGE_WALL / 2),
                       MIRROR_SIZE + CARTRIDGE_WALL / 2, 0])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                      CARTRIDGE_WALL,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            hull() {
                translate([0, 1, 0])
                    cube([0.8, 2, pocket_z * 0.65], center = true);
                translate([gx + out * CARTRIDGE_WALL, MIRROR_SIZE * 0.2, 0])
                    cube([1, 1, pocket_z * 0.65], center = true);
            }
            translate([gx + out * (MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
                       MIRROR_SIZE / 2, 0])
                cube([RAIL_W, pocket_y + 2, pocket_z + 6], center = true);
        }
        translate([gx, MIRROR_SIZE / 2, 0])
            cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.15,
                  pocket_y,
                  pocket_z], center = true);
        translate([out * 6, MIRROR_SIZE / 2, 0])
            cube([12, pocket_y - 4, pocket_z - 4], center = true);
    }
}

module mirror_wing_glass(out = 1) {
    gx = out * (MIRROR_THICK / 2 + MIRROR_CLEAR);
    translate([gx, MIRROR_SIZE / 2, 0])
        mirror_glass();
}

// Fixed cartridge: tip at origin, arms to +Y back wall, coatings OUT.
// Right @ −45° out=+1; left @ +45° out=−1. One piece.
module mirror_L_cartridge(show_mirrors = true) {
    color("SteelBlue")
    union() {
        // spine joins both wings at the tip (middle of the box)
        translate([0, SPINE_W / 2, 0])
            cube([SPINE_W, SPINE_W,
                  MIRROR_SIZE + CARTRIDGE_WALL * 2], center = true);

        // floor under the V (not a back wall plate)
        translate([0, MIRROR_SIZE / 2,
                   -MIRROR_SIZE / 2 - FLOOR_T / 2 - MIRROR_CLEAR])
            cube([MIRROR_SIZE * 0.95, MIRROR_SIZE + 4, FLOOR_T], center = true);

        rotate([0, 0, -45])
            mirror_wing_frame(out = 1);
        rotate([0, 0, 45])
            mirror_wing_frame(out = -1);
    }
    if (show_mirrors) {
        rotate([0, 0, -45])
            mirror_wing_glass(out = 1);
        rotate([0, 0, 45])
            mirror_wing_glass(out = -1);
    }
}

module mirror_groove_cutouts() {
    well_h = JUNCTION_BOX;

    for (ang_out = [[-45, 1], [45, -1]]) {
        ang = ang_out[0];
        out = ang_out[1];
        rotate([0, 0, ang])
            translate([out * (MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
                       MIRROR_SIZE / 2,
                       WALL])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2 + RAIL_W * 2 + GROOVE_CLEAR * 2,
                      MIRROR_SIZE + CARTRIDGE_WALL * 2 + GROOVE_CLEAR * 2,
                      well_h], center = true);
    }
    translate([0, MIRROR_SIZE * 0.4, WALL])
        cube([SPINE_W + GROOVE_CLEAR * 4,
              MIRROR_SIZE * 0.85,
              well_h], center = true);
}

module mirror_ray_guides() {
    if ($preview) {
        color("gold", 0.5) {
            translate([0, -D_LENS_TO_KNIFE / 2, 0])
                cube([1.0, D_LENS_TO_KNIFE, 1.0], center = true);
            translate([D_KNIFE_TO_MOUNT / 2, 0, 0])
                cube([D_KNIFE_TO_MOUNT, 1.0, 1.0], center = true);
            translate([-D_KNIFE_TO_MOUNT / 2, 0, 0])
                cube([D_KNIFE_TO_MOUNT, 1.0, 1.0], center = true);
        }
    }
}

module mirror_pair(show_mirrors = true, explode_z = 0) {
    translate([0, 0, explode_z])
        mirror_L_cartridge(show_mirrors = show_mirrors);
    mirror_ray_guides();
}

module mirror_cartridge(side = 1, show_mirror = true) {
    mirror_L_cartridge(show_mirrors = show_mirror);
}

module mirror_tray(side = 1, show_mirror = true) {
    mirror_L_cartridge(show_mirrors = show_mirror);
}
