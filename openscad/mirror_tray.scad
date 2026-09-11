// One-piece V cartridge — sits on the BACK wall (no lens/camera port).
// Coatings face OUT from the V (toward the lens / into the chamber).
// Apex against +Y wall; V opens toward the lens (−Y).

include <params.scad>

GROOVE_CLEAR   = 0.45;
CARTRIDGE_WALL = 2.2;
SPINE_W        = 3.2;
FLOOR_T        = 2.8;
RAIL_W         = 2.5;

// Apex sits just inside the back wall
function mirror_apex_y() = JUNCTION_BOX / 2 - WALL - 4;

module mirror_glass() {
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// Local wing: knife edge at Y=0, blade extends +Y in local frame.
// Coatings face OUT of the V: glass on −X, coating on +X face (looks outward).
// After world placement, +X local maps to the chamber/lens side.
module mirror_wing_frame() {
    pocket_y = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pocket_z = MIRROR_SIZE + MIRROR_CLEAR * 2;
    // substrate further −X (into the V / toward back wall after place);
    // coating on +X face = OUT from the V
    gx = -(MIRROR_THICK / 2 + MIRROR_CLEAR);

    difference() {
        union() {
            // back plate on substrate side (−X)
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
            // web toward spine
            hull() {
                translate([0, 1, 0])
                    cube([0.8, 2, pocket_z * 0.7], center = true);
                translate([gx - CARTRIDGE_WALL, MIRROR_SIZE * 0.25, 0])
                    cube([1, 1, pocket_z * 0.7], center = true);
            }
            // rail on substrate side
            translate([gx - MIRROR_THICK / 2 - CARTRIDGE_WALL - RAIL_W / 2,
                       MIRROR_SIZE / 2, 0])
                cube([RAIL_W, pocket_y + 2, pocket_z + 6], center = true);
        }
        translate([gx, MIRROR_SIZE / 2, 0])
            cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.15,
                  pocket_y,
                  pocket_z], center = true);
        // open on coating side (+X) — out from V
        translate([4, MIRROR_SIZE / 2, 0])
            cube([10, pocket_y - 4, pocket_z - 4], center = true);
    }
}

module mirror_wing_glass() {
    gx = -(MIRROR_THICK / 2 + MIRROR_CLEAR);
    translate([gx, MIRROR_SIZE / 2, 0])
        mirror_glass();
}

// Place wings so blades run along the back wall, apex on +Y wall center.
// Right wing: Rz(-45) — blade into +X from apex, coating faces chamber (−Y-ish)
// Left wing:  Rz(+45) — blade into −X from apex, coating faces chamber
// Then shift whole L to the back wall.
module mirror_L_cartridge(show_mirrors = true) {
    ay = mirror_apex_y();

    translate([0, ay, 0])
    rotate([0, 0, 180]) {  // local +Y blades point toward −Y (into chamber / lens)
        color("SteelBlue")
        union() {
            // floor under V
            translate([0, MIRROR_SIZE / 2,
                       -MIRROR_SIZE / 2 - FLOOR_T / 2 - MIRROR_CLEAR])
                cube([MIRROR_SIZE * 1.15, MIRROR_SIZE + 10, FLOOR_T], center = true);

            // spine at apex (against back wall after translate)
            translate([0, SPINE_W / 2, 0])
                cube([SPINE_W, SPINE_W + 1,
                      MIRROR_SIZE + CARTRIDGE_WALL * 2], center = true);

            translate([0, MIRROR_SIZE * 0.5, -MIRROR_SIZE / 2 + 2])
                cube([MIRROR_SIZE * 0.85, 5, 3.5], center = true);

            // BOTH wings same recipe — coatings OUT from V
            rotate([0, 0, -45])
                mirror_wing_frame();
            rotate([0, 0, 45])
                mirror_wing_frame();
        }
        if (show_mirrors) {
            rotate([0, 0, -45])
                mirror_wing_glass();
            rotate([0, 0, 45])
                mirror_wing_glass();
        }
    }
}

module mirror_groove_cutouts() {
    well_h = JUNCTION_BOX;
    ay = mirror_apex_y();

    translate([0, ay, 0])
    rotate([0, 0, 180]) {
        for (ang = [-45, 45]) {
            rotate([0, 0, ang])
                translate([-(MIRROR_THICK / 2 + CARTRIDGE_WALL + RAIL_W / 2),
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
