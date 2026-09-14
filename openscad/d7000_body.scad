// Nikon D-body visualization mesh, lens cut off at the F-mount.
// Source: José Pedro, Printables #1733741, CC BY-NC-SA 4.0
// https://www.printables.com/model/1733741-nikon-dslr-camera-model-3d-printable
//
// Mesh is ~175 mm wide; scale 0.75 → ~132 mm (D7000 envelope).
// Origin after this module ≈ F-register. +Z into the body. +Y top. +X grip.
// Hybrid upright: R local +X (roll 90), T local −Y (roll 180).
// Older R ghost was roll −90 (upside down). V left / −X arm local +X (roll 90).

D7000_STL   = "d7000_body.stl";
D7000_SCALE = 0.75;
D7000_RX    = 90;
D7000_RY    = 0;
D7000_RZ    = 180;
// Raw mount axis ≈ (22, −4, −16.9). After scale / RX90 / RZ180 that
// lands at (−16.5, −12.7, −3); shift it onto the F-register origin.
D7000_TX    = 16.5;
D7000_TY    = 12.7;
D7000_TZ    = 3.0;

module d7000_body(roll = 0) {
    rotate([0, 0, roll])
        translate([D7000_TX, D7000_TY, D7000_TZ])
            rotate([D7000_RX, D7000_RY, D7000_RZ])
                scale(D7000_SCALE)
                    import(D7000_STL, convexity = 8);
}
