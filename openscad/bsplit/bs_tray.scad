// Single 45° plate cartridge. Plate center = origin.
// Light travels +Y from the lens (−Y). S1 coating faces the lens.
// Reflect → +X camera. Transmit → +Y camera.
// Rz(−45): local +X (coating) points toward +X−Y.

include <params.scad>

CARTRIDGE_WALL = 4.5;
POST_W         = 8.0;
POST_D         = 3.2;
POST_H         = 12.0;
FORK_CLEAR     = 0.4;
FORK_LEN       = 10.0;
CHAMBER_MARGIN = 1.2;

function chamber_xy() = JUNCTION_BOX - 2 * WALL;
function floor_z()    = -JUNCTION_BOX / 2 + WALL;
function slot_t()     = BS_THICK + BS_CLEAR * 2;
function plate_w()    = BS_SIZE + BS_CLEAR * 2;

// World XY of the two top rails (local ±Y after Rz(−45)).
function retain_xy(side) =
    let (ly = side * plate_w() / 2, a = -45)
        [-ly * sin(a), ly * cos(a)];

module place_plate(glass = false) {
    rotate([0, 0, -45])
        if (glass) {
            color("silver", 0.45)
                cube([BS_THICK, BS_SIZE, BS_SIZE], center = true);
        } else {
            bs_frame();
        }
}

module bs_frame() {
    w  = CARTRIDGE_WALL;
    py = plate_w();
    pz = plate_w();
    st = slot_t();
    z0 = floor_z();
    z1 = -pz / 2;

    difference() {
        union() {
            translate([0, 0, (z0 + z1) / 2])
                cube([st + w * 2, py + w * 2, z1 - z0], center = true);
            translate([0, 0, pz / 2 + w / 2])
                cube([st + w * 2, py + w * 2, w], center = true);
            for (s = [-1, 1])
                translate([0, s * (py / 2 + w / 2), 0])
                    cube([st + w * 2, w, pz + w * 2], center = true);
        }
        cube([st, py + 0.2, pz + 20], center = true);
        cube([40, py - 6, pz - 6], center = true);
    }
}

module cartridge_posts() {
    top = plate_w() / 2 + CARTRIDGE_WALL;
    for (side = [-1, 1]) {
        p = retain_xy(side);
        translate([p[0], p[1], top + POST_H / 2])
            cube([POST_W, POST_D, POST_H], center = true);
    }
}

module bs_cartridge(show_plate = true) {
    color("SteelBlue")
    intersection() {
        union() {
            place_plate(glass = false);
            cartridge_posts();
        }
        cube([chamber_xy() - CHAMBER_MARGIN * 2,
              chamber_xy() - CHAMBER_MARGIN * 2,
              JUNCTION_BOX - 1], center = true);
    }
    if (show_plate)
        intersection() {
            place_plate(glass = true);
            cube([chamber_xy() - CHAMBER_MARGIN * 2,
                  chamber_xy() - CHAMBER_MARGIN * 2,
                  JUNCTION_BOX - 1], center = true);
        }
}

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

module bs_pair(show_plate = true, explode_z = 0) {
    translate([0, 0, explode_z])
        bs_cartridge(show_plate = show_plate);
}
