// Nikon D800 / D810 FX body ghost.
// Mesh: your Nikon_D800.STL (Thingiverse #4815092) → openscad/d800_body.stl.
// Binary header must NOT start with "solid" or OpenSCAD loads 0 facets.
//
// Raw mesh: +Z = front (F-mount), −Z = back. Y-180 faces the register toward
// the chassis (−Z) with +Z into the body. Origin ≈ F-register.

D800_STL   = "d800_body.stl";
D800_SCALE = 146 / 200; // CIPA width ~146 mm
// F-mount recess center + register plane on the front face.
D800_OX    = 102.0;
D800_OY    = 64.0;
D800_OZ    = 81.0;

module d800_body(roll = 0) {
    rotate([0, 0, roll])
        rotate([0, 180, 0])
            scale(D800_SCALE)
                translate([-D800_OX, -D800_OY, -D800_OZ])
                    import(D800_STL, convexity = 12);
}
