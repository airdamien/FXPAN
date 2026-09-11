// 45° 50/50 at the origin. Drop the plate in from +Z; S1 toward the lens.
// Thick frame runs to the active corners (baffle). Floor beams to the others.
// Inward faces are sawtoothed so stray light dies instead of bouncing.

include <params.scad>

CARTRIDGE_WALL = 4.5;
POST_W         = 8.0;
POST_D         = 3.2;
POST_H         = 12.0;
FORK_CLEAR     = 0.4;
FORK_LEN       = 10.0;
SLIP           = 0.4;
SKIRT_T        = 3.4;
SKIRT_H        = 8.0;
CORNER_L       = 9.0;
RIB_PITCH      = 2.8;
RIB_DEPTH      = 0.9;

function chamber_xy() = JUNCTION_BOX - 2 * WALL;
function inner()      = chamber_xy() - 2 * SLIP;
function half()       = inner() / 2;
function floor_z()    = -JUNCTION_BOX / 2 + WALL;
function slot_t()     = BS_THICK + BS_CLEAR * 2;
function plate_w()    = BS_SIZE + BS_CLEAR * 2;
function frame_top()  = plate_w() / 2 + CARTRIDGE_WALL;
function corner_y()   = half() * sqrt(2);
function shelf_z()    = -BS_SIZE / 2 - 0.15;

function retain_xy(side) =
    let (ly = side * plate_w() / 2, a = -45)
        [-ly * sin(a), ly * cos(a)];

module place_plate(glass = false) {
    rotate([0, 0, -45])
        if (glass) {
            color("gold", 0.45)
                cube([BS_THICK, BS_SIZE, BS_SIZE], center = true);
        } else {
            bs_frame();
        }
}

// V-grooves cut into +X, spaced along Y, running height h.
module trap_ribs(len, h) {
    n = max(1, floor(len / RIB_PITCH));
    for (i = [0 : n - 1])
        translate([0, -len / 2 + (i + 0.5) * RIB_PITCH, 0])
            linear_extrude(height = h, center = true)
                polygon([
                    [0, -RIB_PITCH * 0.45],
                    [0,  RIB_PITCH * 0.45],
                    [RIB_DEPTH, 0]
                ]);
}

module bs_frame() {
    w  = CARTRIDGE_WALL;
    py = plate_w();
    pz = plate_w();
    st = slot_t();
    z0 = floor_z();
    top = frame_top();
    reach = corner_y();
    face = st / 2 + w;
    ext = reach - py / 2;

    difference() {
        translate([0, 0, (z0 + top) / 2])
            cube([st + w * 2, 2 * reach, top - z0], center = true);

        // Open-top slot: plate drops in from +Z and sits on the shelf.
        translate([0, 0, (shelf_z() + top + 6) / 2])
            cube([st, py + 0.3, top + 6 - shelf_z()], center = true);

        // Lead-in at the mouth
        translate([0, 0, top - 0.2])
            hull() {
                cube([st, py + 0.3, 0.4], center = true);
                translate([0, 0, 2.2])
                    cube([st + 1.8, py + 0.8, 0.4], center = true);
            }

        // Clear the two beam paths through the glass only
        cube([40, py - 6, pz - 6], center = true);

        // Sawteeth on the baffle faces (cut into the wall, toward the corners)
        for (sx = [-1, 1], sy = [-1, 1])
            translate([sx * face, sy * (py / 2 + ext / 2), (z0 + top) / 2])
                rotate([0, 0, sx > 0 ? 180 : 0])
                    trap_ribs(ext - 1, top - z0 - 2);
    }
}

module locate_skirt() {
    z0 = floor_z();
    difference() {
        translate([0, 0, z0 + SKIRT_H / 2])
            cube([inner(), inner(), SKIRT_H], center = true);
        translate([0, 0, z0 + SKIRT_H / 2])
            cube([inner() - 2 * SKIRT_T,
                  inner() - 2 * SKIRT_T,
                  SKIRT_H + 1], center = true);
        // Sawteeth on the inner skirt walls
        for (a = [0, 90, 180, 270])
            rotate([0, 0, a])
                translate([half() - SKIRT_T, 0, z0 + SKIRT_H / 2])
                    rotate([0, 0, 180])
                        trap_ribs(inner() - 2 * CORNER_L, SKIRT_H);
    }
}

module inactive_beams() {
    z0 = floor_z();
    // Plate sits on world +45. These run the other diagonal to the empty corners.
    rotate([0, 0, 45])
        translate([0, 0, z0 + SKIRT_H / 2])
            cube([SKIRT_T, inner() * sqrt(2), SKIRT_H], center = true);
}

module corner_uprights() {
    z0 = floor_z();
    h  = frame_top() - z0;
    for (sx = [-1, 1], sy = [-1, 1]) {
        translate([sx * (half() - CORNER_L / 2),
                   sy * (half() - SKIRT_T / 2),
                   z0 + h / 2])
            cube([CORNER_L, SKIRT_T, h], center = true);
        translate([sx * (half() - SKIRT_T / 2),
                   sy * (half() - CORNER_L / 2),
                   z0 + h / 2])
            cube([SKIRT_T, CORNER_L, h], center = true);
    }
}

module cartridge_posts() {
    top = frame_top();
    for (side = [-1, 1]) {
        p = retain_xy(side);
        translate([p[0], p[1], top + POST_H / 2])
            cube([POST_W, POST_D, POST_H], center = true);
    }
}

module hybrid_cartridge(show_glass = true) {
    color("SteelBlue")
    intersection() {
        union() {
            place_plate(glass = false);
            locate_skirt();
            inactive_beams();
            corner_uprights();
            cartridge_posts();
        }
        translate([0, 0, floor_z() + (JUNCTION_BOX - WALL) / 2])
            cube([inner(), inner(), JUNCTION_BOX - WALL], center = true);
    }
    if (show_glass)
        intersection() {
            place_plate(glass = true);
            cube([inner(), inner(), JUNCTION_BOX - 1], center = true);
        }
}

module mirror_groove_cutouts() { }

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

module hybrid_pair(show_glass = true, explode_z = 0) {
    translate([0, 0, explode_z])
        hybrid_cartridge(show_glass = show_glass);
}
