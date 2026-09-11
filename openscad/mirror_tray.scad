// Field-splitter mirrors — roof pointing at the LENS, coating faces incoming light.
//
// Optical frame: lens at -Y, rays travel +Y into knife at origin.
//   Right mirror (+X camera): plane ≈ y=x, normal (−1,1)/√2 → reflects +Y → +X
//   Left  mirror (−X camera): plane ≈ y=−x, normal (+1,1)/√2 → reflects +Y → −X
// Glass substrate sits BEHIND the coating (away from lens), so it does not block
// the path from coating → camera.

include <params.scad>

module mirror_glass() {
    // Thin dim = local Y. Coating on local −Y face (toward knife / lens).
    color("silver", 0.9)
        cube([MIRROR_SIZE, MIRROR_THICK, MIRROR_SIZE], center = true);
}

// side: +1 = right (+X), −1 = left (−X)
module mirror_tray(side = 1, show_mirror = true) {
    pocket = MIRROR_SIZE + MIRROR_CLEAR * 2;
    depth  = MIRROR_THICK + MIRROR_CLEAR + 2;
    frame  = 5;

    // Right needs rotate −45° so local +Y = world normal (−√2/2, √2/2)
    // Left  needs rotate +45° so local +Y = world normal (+√2/2, √2/2)
    rot = -side * 45;

    // Put tray center along the normal, OUTWARD into ±X,+Y (behind coating).
    // Near edge of glass stays close to the knife so the roof points at the lens.
    along_n = MIRROR_SIZE * 0.5 + MIRROR_THICK;

    rotate([0, 0, rot])
        translate([0, along_n, 0]) {
            difference() {
                // Frame mostly on the +local-Y (substrate) side — keeps −Y face open to light
                translate([0, depth / 2, 0])
                    cube([pocket + frame * 2, depth + 3, pocket + frame * 2], center = true);
                // Pocket from the coating side
                translate([0, MIRROR_CLEAR, 0])
                    cube([pocket, depth + 2, pocket], center = true);
                // Open window toward knife (local −Y) AND toward camera (through)
                translate([0, -5, 0])
                    cube([pocket - 6, 20, pocket - 6], center = true);
                // Tip/tilt set-screw holes from behind (substrate side)
                for (z = [-MIRROR_SIZE * 0.3, MIRROR_SIZE * 0.3])
                    for (x = [-MIRROR_SIZE * 0.3, MIRROR_SIZE * 0.3])
                        if (!(x > 0 && z > 0))
                            translate([x, depth + 1, z])
                                rotate([90, 0, 0])
                                    cylinder(h = 14, d = 2.6, $fn = 20);
            }
            if (show_mirror)
                // Coating on local −Y face (toward knife); glass body toward +Y
                translate([0, MIRROR_THICK / 2 + MIRROR_CLEAR, 0])
                    mirror_glass();
        }
}

module knife_edge_rib(h = MIRROR_SIZE + 6) {
    // Thin vertical rib at origin; bevelled so coated edges can meet
    color("DimGray")
        intersection() {
            rotate([0, 0, 45])
                cube([2.0, 2.0, h], center = true);
            cube([8, 8, h], center = true);
        }
}

// Preview rays: lens → knife → each camera (proves path is not blocked)
module mirror_ray_guides() {
    if ($preview) {
        color("gold", 0.55) {
            // incoming from lens
            translate([0, -D_LENS_TO_KNIFE / 2, 0])
                cube([1.2, D_LENS_TO_KNIFE, 1.2], center = true);
            // to right camera
            translate([D_KNIFE_TO_MOUNT / 2, 0, 0])
                cube([D_KNIFE_TO_MOUNT, 1.2, 1.2], center = true);
            // to left camera
            translate([-D_KNIFE_TO_MOUNT / 2, 0, 0])
                cube([D_KNIFE_TO_MOUNT, 1.2, 1.2], center = true);
        }
    }
}

module mirror_pair(show_mirrors = true) {
    mirror_tray(side = -1, show_mirror = show_mirrors);
    mirror_tray(side =  1, show_mirror = show_mirrors);
    knife_edge_rib();
    mirror_ray_guides();
}
