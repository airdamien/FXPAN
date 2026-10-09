// Canon EOS 5D Mark III envelope for assembly preview. No mesh.
// 152 × 116.4 × 76.4 mm (CIPA, body only).
// Origin = EF register. +Z into the body. +Y top. +X grip.
// Flange-mark up: R local −X (roll −90), T local −Y (roll 180).

include <params.scad>

module body_5dmk3(roll = 0) {
    rotate([0, 0, roll])
        translate([14, 0, BODY_D / 2])
            cube([BODY_W, BODY_H, BODY_D], center = true);
}
