// One-piece V cartridge — wings join at a thin knife in the MIDDLE (origin).
// Tip at box center (points toward lens); arms toward blank back wall (+Y).
// Coatings on the OUTSIDE of the V. No back plate / no fat spine block.

include <params.scad>

GROOVE_CLEAR   = 0.4;
CARTRIDGE_WALL = 2.2;
RAIL_W         = 2.2;
FLOOR_T        = 2.2;
KNIFE_W        = 1.2;   // thin join at tip — not a fat rectangle

module mirror_glass() {
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// One wing: backing on the INSIDE of the V, glass pocket on the OUTSIDE.
// Local: knife at Y=0, blade +Y. `out` = +1/−1 = outside direction in local X.
module mirror_wing(out = 1, glass = false) {
    py = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pz = MIRROR_SIZE + MIRROR_CLEAR * 2;
    // glass center on the OUTSIDE face
    gx = out * (MIRROR_THICK / 2 + MIRROR_CLEAR);

    if (glass) {
        translate([gx, MIRROR_SIZE / 2, 0])
            mirror_glass();
    } else {
        difference() {
            union() {
                // inside backing (toward the crease / −out)
                translate([-out * (CARTRIDGE_WALL / 2 + 0.3),
                           MIRROR_SIZE / 2, 0])
                    cube([CARTRIDGE_WALL,
                          py + CARTRIDGE_WALL,
                          pz + CARTRIDGE_WALL * 2], center = true);

                // top & bottom lips holding glass from outside
                for (z = [-1, 1])
                    translate([gx * 0.3,
                               MIRROR_SIZE / 2,
                               z * (pz / 2 + CARTRIDGE_WALL / 2)])
                        cube([MIRROR_THICK + CARTRIDGE_WALL * 2.5,
                              py + CARTRIDGE_WALL,
                              CARTRIDGE_WALL], center = true);

                // far end (toward back wall)
                translate([0, MIRROR_SIZE + CARTRIDGE_WALL / 2, 0])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2.5,
                          CARTRIDGE_WALL,
                          pz + CARTRIDGE_WALL * 2], center = true);

                // thin web into knife
                hull() {
                    translate([0, 0.6, 0])
                        cube([KNIFE_W, 1.2, pz * 0.7], center = true);
                    translate([-out * CARTRIDGE_WALL * 0.4, MIRROR_SIZE * 0.12, 0])
                        cube([1, 1, pz * 0.7], center = true);
                }

                // outside drop-in rail
                translate([out * (MIRROR_THICK + CARTRIDGE_WALL + RAIL_W / 2),
                           MIRROR_SIZE / 2, 0])
                    cube([RAIL_W, py, pz + 5], center = true);

                // floor strip under this wing only
                translate([-out * CARTRIDGE_WALL * 0.25, MIRROR_SIZE / 2,
                           -pz / 2 - FLOOR_T / 2])
                    cube([CARTRIDGE_WALL + MIRROR_THICK + 2,
                          py + 2, FLOOR_T], center = true);
            }
            // glass pocket from the OUTSIDE
            translate([gx, MIRROR_SIZE / 2, 0])
                cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.15,
                      py, pz], center = true);
            // keep outside face open so coating faces OUT
            translate([out * 8, MIRROR_SIZE / 2, 0])
                cube([16, py - 5, pz - 5], center = true);
        }
    }
}

module mirror_L_cartridge(show_mirrors = true) {
    color("SteelBlue")
    union() {
        // thin knife join at the tip (middle of body) — not a fat block
        translate([0, KNIFE_W / 2, 0])
            cube([KNIFE_W, KNIFE_W,
                  MIRROR_SIZE + CARTRIDGE_WALL * 2], center = true);

        rotate([0, 0, -45])
            mirror_wing(out = 1, glass = false);
        rotate([0, 0, 45])
            mirror_wing(out = -1, glass = false);
    }
    if (show_mirrors) {
        rotate([0, 0, -45])
            mirror_wing(out = 1, glass = true);
        rotate([0, 0, 45])
            mirror_wing(out = -1, glass = true);
    }
}

module mirror_groove_cutouts() {
    well_h = JUNCTION_BOX;
    for (pair = [[-45, 1], [45, -1]]) {
        rotate([0, 0, pair[0]])
            translate([pair[1] * (MIRROR_THICK + CARTRIDGE_WALL + RAIL_W / 2),
                       MIRROR_SIZE / 2, WALL])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2 + RAIL_W * 2 + GROOVE_CLEAR * 2,
                      MIRROR_SIZE + CARTRIDGE_WALL * 2 + GROOVE_CLEAR * 2,
                      well_h], center = true);
    }
    translate([0, KNIFE_W, WALL])
        cube([KNIFE_W + GROOVE_CLEAR * 4, KNIFE_W * 4, well_h], center = true);
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
