// Sony α7 (ILCE-7) envelope for assembly preview. No mesh.
// 126.9 × 94.4 × 48.2 mm (CIPA, grip to monitor).
// Origin = E register. +Z into the body. +Y top. +X grip.
// Flange-mark up: R local −X (roll −90), T local −Y (roll 180).

include <params.scad>

module body_a7(roll = 0) {
    rotate([0, 0, roll])
        translate([12, 0, BODY_D / 2])
            cube([BODY_W, BODY_H, BODY_D], center = true);
}
