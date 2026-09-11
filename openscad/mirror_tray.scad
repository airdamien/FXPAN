// One-piece V cartridge — tip joins in the MIDDLE (origin).
// Arms run toward blank back wall (+Y). Coatings face OUT of the V.
// No back plate. Wings fixed; cannot flip one side alone.

include <params.scad>

GROOVE_CLEAR   = 0.45;
CARTRIDGE_WALL = 2.4;
SPINE_W        = 3.2;
FLOOR_T        = 2.4;
RAIL_W         = 2.4;

module mirror_glass() {
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// Knife at local Y=0; blade extends +Y.
// `out` picks the OUTSIDE of the V (coating + open face).
module mirror_wing(out = 1, glass = false) {
    pocket_y = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pocket_z = MIRROR_SIZE + MIRROR_CLEAR * 2;
    gx = out * (MIRROR_THICK / 2 + MIRROR_CLEAR);

    if (glass) {
        translate([gx, MIRROR_SIZE / 2, 0])
            mirror_glass();
    } else {
        difference() {
            union() {
                // substrate backing (further outside)
                translate([gx + out * (MIRROR_THICK / 2 + CARTRIDGE_WALL / 2),
                           MIRROR_SIZE / 2, 0])
                    cube([CARTRIDGE_WALL,
                          pocket_y + CARTRIDGE_WALL,
                          pocket_z + CARTRIDGE_WALL * 2], center = true);
                // top/bottom lips
                for (z = [-1, 1])
                    translate([gx,
                               MIRROR_SIZE / 2,
                               z * (pocket_z / 2 + CARTRIDGE_WALL / 2)])
                        cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                              pocket_y + CARTRIDGE_WALL,
                              CARTRIDGE_WALL], center = true);
                // far end cap (toward back wall)
                translate([gx,
                           MIRROR_SIZE + CARTRIDGE_WALL / 2, 0])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                          CARTRIDGE_WALL,
                          pocket_z + CARTRIDGE_WALL * 2], center = true);
                // web to spine
                hull() {
                    translate([0, 0.8, 0])
                        cube([1.2, 1.6, pocket_z * 0.6], center = true);
                    translate([gx + out * CARTRIDGE_WALL * 0.5,
                               MIRROR_SIZE * 0.15, 0])
                        cube([1, 1, pocket_z * 0.6], center = true);
                }
                // drop-in rail on outside
                translate([gx + out * (MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
                           MIRROR_SIZE / 2, 0])
                    cube([RAIL_W, pocket_y, pocket_z + 6], center = true);
                // thin floor strip under this wing only
                translate([gx / 2, MIRROR_SIZE / 2,
                           -pocket_z / 2 - FLOOR_T / 2])
                    cube([abs(gx) + CARTRIDGE_WALL + 2,
                          pocket_y + 2,
                          FLOOR_T], center = true);
            }
            // glass pocket
            translate([gx, MIRROR_SIZE / 2, 0])
                cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.2,
                      pocket_y,
                      pocket_z], center = true);
            // open OUTWARD (coating faces out of V)
            translate([out * 7, MIRROR_SIZE / 2, 0])
                cube([14, pocket_y - 6, pocket_z - 6], center = true);
        }
    }
}

// Fixed one-piece cartridge: tip at origin (middle of body).
module mirror_L_cartridge(show_mirrors = true) {
    color("SteelBlue")
    union() {
        // join at the tip — middle of the box
        translate([0, SPINE_W / 2, 0])
            cube([SPINE_W, SPINE_W,
                  MIRROR_SIZE + CARTRIDGE_WALL * 2], center = true);

        // Right wing → back-right; Left wing → back-left
        // Coatings OUT: right out=+1, left out=−1 at ±45°
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
            translate([pair[1] * (MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
                       MIRROR_SIZE / 2,
                       WALL])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2 + RAIL_W * 2 + GROOVE_CLEAR * 2,
                      MIRROR_SIZE + CARTRIDGE_WALL * 2 + GROOVE_CLEAR * 2,
                      well_h], center = true);
    }
    // clearance for center spine only (no back-wall slab)
    translate([0, SPINE_W, WALL])
        cube([SPINE_W + GROOVE_CLEAR * 4,
              SPINE_W * 3,
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
