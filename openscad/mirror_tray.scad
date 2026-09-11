// One-piece V cartridge on the BACK wall (blank wall — no lens/camera).
// Coatings face OUT of the V into the chamber (toward the lens).
// Apex on +Y wall; open toward lens (−Y). Both wings identical handedness.

include <params.scad>

GROOVE_CLEAR   = 0.45;
CARTRIDGE_WALL = 2.2;
SPINE_W        = 3.2;
FLOOR_T        = 2.8;
RAIL_W         = 2.5;

// Keep the whole V in the back half, flush to +Y wall
function mirror_apex_y() = JUNCTION_BOX / 2 - WALL - 2;

module mirror_glass() {
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// Local: knife at Y=0, blade +Y.
// Coatings OUT of V: glass substrate on −X (into crease), coating on +X (faces chamber).
module mirror_wing_frame() {
    pocket_y = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pocket_z = MIRROR_SIZE + MIRROR_CLEAR * 2;
    gx = -(MIRROR_THICK / 2 + MIRROR_CLEAR);

    difference() {
        union() {
            translate([gx - MIRROR_THICK / 2 - CARTRIDGE_WALL / 2,
                       MIRROR_SIZE / 2, 0])
                cube([CARTRIDGE_WALL,
                      pocket_y + CARTRIDGE_WALL,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            for (z = [-1, 1])
                translate([gx - CARTRIDGE_WALL / 2,
                           MIRROR_SIZE / 2,
                           z * (pocket_z / 2 + CARTRIDGE_WALL / 2)])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                          pocket_y + CARTRIDGE_WALL,
                          CARTRIDGE_WALL], center = true);
            translate([gx - CARTRIDGE_WALL / 2,
                       MIRROR_SIZE + CARTRIDGE_WALL / 2, 0])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                      CARTRIDGE_WALL,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            hull() {
                translate([0, 1, 0])
                    cube([0.8, 2, pocket_z * 0.7], center = true);
                translate([gx - CARTRIDGE_WALL, MIRROR_SIZE * 0.25, 0])
                    cube([1, 1, pocket_z * 0.7], center = true);
            }
            translate([gx - MIRROR_THICK / 2 - CARTRIDGE_WALL - RAIL_W / 2,
                       MIRROR_SIZE / 2, 0])
                cube([RAIL_W, pocket_y + 2, pocket_z + 6], center = true);
        }
        translate([gx, MIRROR_SIZE / 2, 0])
            cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.15,
                  pocket_y,
                  pocket_z], center = true);
        // open on coating side (+X) — out of V into chamber
        translate([5, MIRROR_SIZE / 2, 0])
            cube([12, pocket_y - 4, pocket_z - 4], center = true);
    }
}

module mirror_wing_glass() {
    gx = -(MIRROR_THICK / 2 + MIRROR_CLEAR);
    translate([gx, MIRROR_SIZE / 2, 0])
        mirror_glass();
}

module mirror_L_cartridge(show_mirrors = true) {
    // Build in place at the back wall:
    // World: apex at (0, apex_y), blades sweep toward −Y into the box.
    // Right @ world angle that puts blade along back→right; left mirrored by −angle.
    ay = mirror_apex_y();

    color("SteelBlue")
    union() {
        // floor against back
        translate([0, ay - MIRROR_SIZE / 2,
                   -MIRROR_SIZE / 2 - FLOOR_T / 2 - MIRROR_CLEAR])
            cube([MIRROR_SIZE * 1.1, MIRROR_SIZE + 6, FLOOR_T], center = true);

        // spine on back wall
        translate([0, ay - SPINE_W / 2, 0])
            cube([SPINE_W, SPINE_W,
                  MIRROR_SIZE + CARTRIDGE_WALL * 2], center = true);

        translate([0, ay - MIRROR_SIZE * 0.45, -MIRROR_SIZE / 2 + 2])
            cube([MIRROR_SIZE * 0.8, 5, 3.5], center = true);

        // Wings: start at apex, extend into chamber (−Y) at ±45° from back wall
        // Rz(180-45)=Rz(135) and Rz(180+45)=Rz(225): local +Y → into −Y hemisphere
        translate([0, ay, 0]) {
            rotate([0, 0, 135])
                mirror_wing_frame();
            rotate([0, 0, 225])
                mirror_wing_frame();
        }
    }
    if (show_mirrors) {
        translate([0, ay, 0]) {
            rotate([0, 0, 135])
                mirror_wing_glass();
            rotate([0, 0, 225])
                mirror_wing_glass();
        }
    }
}

module mirror_groove_cutouts() {
    well_h = JUNCTION_BOX;
    ay = mirror_apex_y();

    translate([0, ay, 0]) {
        for (ang = [135, 225]) {
            rotate([0, 0, ang])
                translate([-(MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
                           MIRROR_SIZE / 2,
                           WALL])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2 + RAIL_W * 2 + GROOVE_CLEAR * 2,
                          MIRROR_SIZE + CARTRIDGE_WALL * 2 + GROOVE_CLEAR * 2,
                          well_h], center = true);
        }
    }
    translate([0, ay - MIRROR_SIZE * 0.35, WALL])
        cube([SPINE_W + GROOVE_CLEAR * 4,
              MIRROR_SIZE * 0.9,
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
