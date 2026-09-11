// One 50×50×1 50/50 at 45°. Leading edge at the origin (split).
// Rays that miss (left field) go +Y at full brightness.
// Rays that hit: R → +X, T → +Y. First BS_EXPOSE mm is the stitch strip.
// A baffle on the transmit face blocks unique-right T so the back camera
// does not see the whole right half. S1 toward the lens. No FSM.

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

function retain_xy(side) =
    let (ly = (side > 0) ? BS_SIZE * 0.85 : BS_SIZE * 0.15, a = -45)
        [-ly * sin(a), ly * cos(a)];

module in_plate() {
    rotate([0, 0, -45])
        children();
}

module place_bs_glass() {
    in_plate()
        translate([0, BS_SIZE / 2, 0])
            color("gold", 0.4)
                cube([BS_THICK, BS_SIZE, BS_SIZE], center = true);
}

module bs_frame() {
    w  = CARTRIDGE_WALL;
    py = plate_w();
    pz = plate_w();
    st = slot_t();
    z0 = floor_z();
    z1 = -pz / 2;

    in_plate()
        translate([0, BS_SIZE / 2, 0])
            difference() {
                union() {
                    translate([0, 0, (z0 + z1) / 2])
                        cube([st + w * 2, py + w * 2, z1 - z0], center = true);
                    translate([0, 0, pz / 2 + w / 2])
                        cube([st + w * 2, py + w * 2, w], center = true);
                    // trailing rail only — leading edge stays open at the split
                    translate([0, py / 2 + w / 2, 0])
                        cube([st + w * 2, w, pz + w * 2], center = true);
                    // T-side baffle: unique right stays off the back camera
                    translate([-(st / 2 + w / 2), BS_EXPOSE / 2, 0])
                        cube([w, py - BS_EXPOSE, pz - 6], center = true);
                }
                cube([st, py + 0.2, pz + 20], center = true);
                // incoming face open (whole plate in the beam)
                translate([20, 0, 0])
                    cube([40, py - 6, pz - 6], center = true);
                // overlap window on the T face
                translate([-20, -(py / 2) + BS_EXPOSE / 2, 0])
                    cube([40, BS_EXPOSE, pz - 6], center = true);
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

module hybrid_cartridge(show_glass = true) {
    color("SteelBlue")
    intersection() {
        union() {
            bs_frame();
            cartridge_posts();
        }
        cube([chamber_xy() - CHAMBER_MARGIN * 2,
              chamber_xy() - CHAMBER_MARGIN * 2,
              JUNCTION_BOX - 1], center = true);
    }
    if (show_glass)
        intersection() {
            place_bs_glass();
            cube([chamber_xy() - CHAMBER_MARGIN * 2,
                  chamber_xy() - CHAMBER_MARGIN * 2,
                  JUNCTION_BOX - 1], center = true);
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
