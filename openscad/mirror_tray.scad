// Drop-in field-splitter cartridges — slide in from +Z, knife at ORIGIN (box center).
//
// V opens toward the lens (−Y); coatings face INWARD (into the V / toward the axis).
// Right (+X cam) in +X,+Y; left (−X cam) in −X,+Y.

include <params.scad>

GROOVE_CLEAR   = 0.4;
CARTRIDGE_WALL = 2.0;
RAIL_W         = 2.4;
RAIL_T         = 2.8;

module mirror_glass() {
    // Thin = local X. Used with coating on the +X face (toward the V interior).
    color("silver", 0.92)
        cube([MIRROR_THICK, MIRROR_SIZE, MIRROR_SIZE], center = true);
}

// Local: coating plane X=0 facing +X (into V); glass/substrate in −X; blade +Y from knife.
module mirror_cartridge(show_mirror = true) {
    pocket_y = MIRROR_SIZE + MIRROR_CLEAR * 2;
    pocket_z = MIRROR_SIZE + MIRROR_CLEAR * 2;
    // glass center on −X so +X face of glass sits on X=0 (coating into V)
    gx = -(MIRROR_THICK / 2 + MIRROR_CLEAR);

    difference() {
        union() {
            // back plate behind glass (further −X)
            translate([gx - MIRROR_THICK / 2 - CARTRIDGE_WALL / 2, MIRROR_SIZE / 2, 0])
                cube([CARTRIDGE_WALL,
                      pocket_y + CARTRIDGE_WALL * 2,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            // top/bottom walls
            for (z = [-1, 1])
                translate([gx,
                           MIRROR_SIZE / 2,
                           z * (pocket_z / 2 + CARTRIDGE_WALL / 2)])
                    cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                          pocket_y + CARTRIDGE_WALL * 2,
                          CARTRIDGE_WALL], center = true);
            // far end (away from knife, +Y)
            translate([gx, MIRROR_SIZE + CARTRIDGE_WALL / 2, 0])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                      CARTRIDGE_WALL,
                      pocket_z + CARTRIDGE_WALL * 2], center = true);
            // bottom sill
            translate([gx, MIRROR_SIZE / 2, -pocket_z / 2 - CARTRIDGE_WALL / 2])
                cube([MIRROR_THICK + CARTRIDGE_WALL * 2,
                      pocket_y + CARTRIDGE_WALL * 2,
                      CARTRIDGE_WALL], center = true);
            // drop-in rails (outer side)
            for (z = [-1, 1])
                translate([gx - MIRROR_THICK / 2 - CARTRIDGE_WALL - RAIL_W / 2,
                           MIRROR_SIZE / 2,
                           z * (pocket_z / 2 + CARTRIDGE_WALL + RAIL_W / 2)])
                    cube([RAIL_W, pocket_y + 4, RAIL_T], center = true);
        }
        translate([gx, MIRROR_SIZE / 2, 0])
            cube([MIRROR_THICK + MIRROR_CLEAR * 2 + 0.2,
                  pocket_y,
                  pocket_z], center = true);
    }

    if (show_mirror)
        translate([gx, MIRROR_SIZE / 2, 0])
            mirror_glass();
}

module mirror_tray(side = 1, show_mirror = true) {
    // side=+1: Rz(-45) → local +X=(1,-1)/√2 (into V for right), local +Y=(1,1)/√2
    rot = -side * 45;
    rotate([0, 0, rot])
        mirror_cartridge(show_mirror = show_mirror);
}

module mirror_groove_cutouts() {
    slot_x = MIRROR_THICK + CARTRIDGE_WALL * 2 + RAIL_W * 2 + GROOVE_CLEAR * 2;
    slot_y = MIRROR_SIZE + CARTRIDGE_WALL * 2 + GROOVE_CLEAR * 2;
    slot_h = JUNCTION_BOX;

    for (side = [-1, 1]) {
        rot = -side * 45;
        // slot centered on cartridge body (glass toward −X local)
        rotate([0, 0, rot])
            translate([-(slot_x / 2 - GROOVE_CLEAR),
                       MIRROR_SIZE / 2,
                       WALL])
                cube([slot_x, slot_y, slot_h], center = true);
    }
}

module knife_edge_rib(h = MIRROR_SIZE * 0.85) {
    color("DimGray")
        cube([0.8, 0.8, h], center = true);
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
    translate([0, 0, explode_z]) {
        mirror_tray(side = -1, show_mirror = show_mirrors);
        mirror_tray(side =  1, show_mirror = show_mirrors);
        if (explode_z == 0)
            knife_edge_rib();
    }
    mirror_ray_guides();
}
