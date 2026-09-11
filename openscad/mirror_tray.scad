// One-piece L/V cartridge — both mirrors locked at 90°, coatings INTO the V.
// Drop in from +Z. Knife at origin. Open toward lens (−Y).

include <params.scad>

GROOVE_CLEAR   = 0.45;
CARTRIDGE_WALL = 2.2;
SPINE_W        = 3.2;
FLOOR_T        = 2.8;
RAIL_W         = 2.5;

module mirror_glass() {
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// invert=true puts glass on the −X side of the wing (flips which face is coating).
// +X = nominal outward; coatings must face INTO the V (toward lens / axis).
module mirror_wing_frame(invert = false) {
    s = invert ? -1 : 1;
    pocket_y = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pocket_z = MIRROR_SIZE + MIRROR_CLEAR * 2;
    gx = s * (MIRROR_THICK / 2 + MIRROR_CLEAR);

    difference() {
        union() {
            // back plate on the substrate side (further along +s*X)
            translate([gx + s * (MIRROR_THICK / 2 + CARTRIDGE_WALL / 2),
                       MIRROR_SIZE / 2, 0])
                cube([CARTRIDGE_WALL,
                      pocket_y + CARTRIDGE_WALL,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            for (z = [-1, 1])
                translate([gx + s * (CARTRIDGE_WALL / 2),
                           MIRROR_SIZE / 2,
                           z * (pocket_z / 2 + CARTRIDGE_WALL / 2)])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                          pocket_y + CARTRIDGE_WALL,
                          CARTRIDGE_WALL], center = true);
            translate([gx + s * (CARTRIDGE_WALL / 2),
                       MIRROR_SIZE + CARTRIDGE_WALL / 2, 0])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                      CARTRIDGE_WALL,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            hull() {
                translate([0, 1, 0])
                    cube([0.8, 2, pocket_z * 0.7], center = true);
                translate([gx + s * CARTRIDGE_WALL, MIRROR_SIZE * 0.25, 0])
                    cube([1, 1, pocket_z * 0.7], center = true);
            }
            translate([gx + s * (MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
                       MIRROR_SIZE / 2, 0])
                cube([RAIL_W, pocket_y + 2, pocket_z + 6], center = true);
        }
        translate([gx, MIRROR_SIZE / 2, 0])
            cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.15,
                  pocket_y,
                  pocket_z], center = true);
        // open toward V interior (opposite substrate)
        translate([-s * 3, MIRROR_SIZE / 2, 0])
            cube([10, pocket_y - 4, pocket_z - 4], center = true);
    }
}

module mirror_wing_glass(invert = false) {
    s = invert ? -1 : 1;
    gx = s * (MIRROR_THICK / 2 + MIRROR_CLEAR);
    translate([gx, MIRROR_SIZE / 2, 0])
        mirror_glass();
}

module mirror_L_cartridge(show_mirrors = true) {
    color("SteelBlue")
    union() {
        translate([0, MIRROR_SIZE / 2,
                   -MIRROR_SIZE / 2 - FLOOR_T / 2 - MIRROR_CLEAR])
            cube([MIRROR_SIZE * 1.15, MIRROR_SIZE + 10, FLOOR_T], center = true);

        translate([0, SPINE_W / 2, 0])
            cube([SPINE_W, SPINE_W + 1,
                  MIRROR_SIZE + CARTRIDGE_WALL * 2], center = true);

        translate([0, MIRROR_SIZE * 0.5, -MIRROR_SIZE / 2 + 2])
            cube([MIRROR_SIZE * 0.85, 5, 3.5], center = true);

        // Right wing @ 45° — inverted so coating faces into V (was toward camera)
        rotate([0, 0, 45])
            mirror_wing_frame(invert = true);
        // Left wing @ 135° — keep nominal (coating into V)
        rotate([0, 0, 135])
            mirror_wing_frame(invert = false);
    }
    if (show_mirrors) {
        rotate([0, 0, 45])
            mirror_wing_glass(invert = true);
        rotate([0, 0, 135])
            mirror_wing_glass(invert = false);
    }
}

module mirror_groove_cutouts() {
    well_h = JUNCTION_BOX;
    // slots follow substrate/rail side of each wing
    for (ang_inv = [[45, true], [135, false]]) {
        ang = ang_inv[0];
        inv = ang_inv[1];
        s = inv ? -1 : 1;
        rotate([0, 0, ang])
            translate([s * (MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
                       MIRROR_SIZE / 2,
                       WALL])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2 + RAIL_W * 2 + GROOVE_CLEAR * 2,
                      MIRROR_SIZE + CARTRIDGE_WALL * 2 + GROOVE_CLEAR * 2,
                      well_h], center = true);
    }
    translate([0, MIRROR_SIZE * 0.35, WALL])
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
