// One-piece V cartridge. Knife at origin (box middle).
// Tip points at the lens (−Y). Arms run toward the blank back wall (+Y).
// Coatings on the OUTSIDE of the V (toward the cameras).
// Lid forks drop over two posts to retain the cartridge.

include <../../../openscad/params.scad>

CARTRIDGE_WALL = 4.5;
KNIFE_W        = 2.0;
POST_W         = 8.0;
POST_D         = 3.2;
POST_H         = 12.0;
FORK_CLEAR     = 0.4;
FORK_LEN       = 10.0;
CHAMBER_MARGIN = 1.2;

function chamber_xy() = JUNCTION_BOX - 2 * WALL;
function floor_z()    = -JUNCTION_BOX / 2 + WALL;
function blade_mid()  = MIRROR_SIZE * 0.55;
function blade_ang(side) = -side * 45;   // +1 right → −45°
function wing_in(side)   = -side * overlap_cross() / 2;

// World XY of a wing post. side +1 = +X (right), −1 = −X (left).
function retain_xy(side) =
    let (a = blade_ang(side), lx = wing_in(side), ly = blade_mid())
        [lx * cos(a) - ly * sin(a),
         lx * sin(a) + ly * cos(a)];

module place_wing(side, glass = false) {
    rotate([0, 0, blade_ang(side)])
        translate([wing_in(side), 0, 0])
            mirror_wing(out = side, glass = glass);
}

module mirror_glass() {
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// Local: knife at Y=0, blade +Y.
// `out` = which local-X side is OUTSIDE the V (coating / open face).
// Right wing  Rz(−45): local +X is outside → out = +1
// Left  wing  Rz(+45): local −X is outside → out = −1
module mirror_wing(out = 1, glass = false) {
    py = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pz = MIRROR_SIZE + MIRROR_CLEAR * 2;
    gx = out * (MIRROR_THICK / 2 + MIRROR_CLEAR);

    if (glass) {
        translate([gx, MIRROR_SIZE / 2, 0])
            mirror_glass();
    } else {
        difference() {
            union() {
                // backing on the INSIDE of the V
                translate([-out * (CARTRIDGE_WALL / 2 + MIRROR_THICK / 2),
                           MIRROR_SIZE / 2, 0])
                    cube([CARTRIDGE_WALL, py, pz + CARTRIDGE_WALL * 2],
                         center = true);

                // top lip
                translate([0, MIRROR_SIZE / 2,
                           pz / 2 + CARTRIDGE_WALL / 2])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2, py,
                          CARTRIDGE_WALL], center = true);

                // solid plinth down to the chamber floor (no skinny feet)
                let (z0 = floor_z(), z1 = -pz / 2)
                    translate([0, MIRROR_SIZE / 2, (z0 + z1) / 2])
                        cube([MIRROR_THICK + CARTRIDGE_WALL * 2, py,
                              z1 - z0], center = true);

                // end cap stays on the glass, does not overshoot toward the wall
                translate([0, MIRROR_SIZE - CARTRIDGE_WALL / 2, 0])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2, CARTRIDGE_WALL,
                          pz + CARTRIDGE_WALL * 2], center = true);

                hull() {
                    translate([0, 0.4, 0])
                        cube([KNIFE_W, 1.2, pz * 0.7], center = true);
                    translate([-out * CARTRIDGE_WALL * 0.3, MIRROR_SIZE * 0.08, 0])
                        cube([1.2, 1.2, pz * 0.7], center = true);
                }
            }
            translate([gx, MIRROR_SIZE / 2, 0])
                cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.15, py, pz],
                     center = true);
            translate([out * 8, MIRROR_SIZE / 2, 0])
                cube([16, py - 6, pz - 6], center = true);
        }
    }
}

module cartridge_posts() {
    top = (MIRROR_SIZE + MIRROR_CLEAR * 2) / 2 + CARTRIDGE_WALL;
    for (side = [-1, 1]) {
        p = retain_xy(side);
        translate([p[0], p[1], top + POST_H / 2])
            cube([POST_W, POST_D, POST_H], center = true);
    }
}

module mirror_L_cartridge(show_mirrors = true) {
    color("SteelBlue")
    intersection() {
        union() {
            translate([0, KNIFE_W / 2, 0])
                cube([KNIFE_W, KNIFE_W,
                      MIRROR_SIZE + CARTRIDGE_WALL * 2], center = true);

            place_wing(1, glass = false);
            place_wing(-1, glass = false);

            cartridge_posts();
        }
        cube([chamber_xy() - CHAMBER_MARGIN * 2,
              chamber_xy() - CHAMBER_MARGIN * 2,
              JUNCTION_BOX - 1], center = true);
    }
    if (show_mirrors) {
        intersection() {
            union() {
                place_wing(1, glass = true);
                place_wing(-1, glass = true);
            }
            cube([chamber_xy() - CHAMBER_MARGIN * 2,
                  chamber_xy() - CHAMBER_MARGIN * 2,
                  JUNCTION_BOX - 1], center = true);
        }
    }
}

module mirror_groove_cutouts() {
    // cartridge now sits on the flat floor — no foot pockets
}

// Call from the lid (lid origin = box rim, +Z out). Forks slot over the posts.
module lid_retain_tabs(lip = 3) {
    for (side = [-1, 1]) {
        p = retain_xy(side);
        translate([p[0], p[1], 0])
            difference() {
                translate([0, 0, -lip - FORK_LEN / 2])
                    cube([POST_W + 4, POST_D + 3.2, FORK_LEN], center = true);
                translate([0, 0, -lip - FORK_LEN / 2 - 0.6])
                    cube([POST_W + FORK_CLEAR * 2,
                          POST_D + FORK_CLEAR * 2,
                          FORK_LEN], center = true);
            }
    }
}

module mirror_ray_guides() {
    if ($preview) {
        color("gold", 0.5) {
            translate([0, -D_LENS_TO_KNIFE / 2, 0])
                cube([1.0, D_LENS_TO_KNIFE, 1.0], center = true);
            for (side = [-1, 1])
                translate([side * JUNCTION_BOX / 2, 0, 0])
                    rotate([0, 0, -side * arm_toe()])
                        translate([side * D_KNIFE_TO_MOUNT / 2, 0, 0])
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
