// Nikkor-W 180mm f/5.6 in Copal No. 1. Nikon large-format sheet, page 16.
//
// Origin is the flange face, the face that seats on the front of the
// lensboard. +Z is the front of the lens. The focal plane is at −178.8.
//
// Sheet:
//   178.8  flange focal distance, from this face
//   60.5   overall, front rim to rear rim
//   70     front mount
//   67×0.75  front filter
//   54     rear mount
//   39×0.75  flange attachment, the ring behind the board
//   41.6   Copal 1 barrel through the board
//   5.1    that barrel, behind the flange
//   17.2   Ø54 cell behind the barrel (5.1 + 17.2 = 22.3)
//   2.6    front rim to the front vertex
//   1.2    rear vertex to the rear rim
//   145.1  front focus    157.7  back focus
//   32.2   entrance pupil  32.6  exit pupil

include <../lib/threads.scad>

NW_FFD   = 178.8;
NW_OAL   = 60.5;
NW_NECK  = 5.1;     // Ø41.6 behind the flange
NW_CELL  = 17.2;    // Ø54 behind that
NW_REAR  = NW_NECK + NW_CELL;
NW_FRONT = NW_OAL - NW_REAR;
NW_THREAD = 4;      // M39 of the 5.1 mm neck, from the flange back

// Front of the flange is 38.2. The drawing's 35.2 is that barrel, from
// the rim back to the shutter. The 73 is its outside; callout A (70) is
// the step on the front face. The shutter in front of the flange is the
// remaining 3.0, with the drawing's 1.1 mm groove at the junction.
NW_TUBE    = 35.2;
NW_D_TUBE  = 73;      // clamp land
NW_D_MOUNT = 70;      // front mount A
NW_GROOVE  = 1.1;
NW_D_REAR  = 54;
NW_D_NECK  = 41.6;
M67_D    = 67;
M67_P    = 0.75;
M39_D    = 39;
M39_P    = 0.75;
L_FILTER = 4;
NW_SHUTTER = NW_FRONT - NW_TUBE;

NW_FRONT_LIP = 2.6;
NW_REAR_LIP  = 1.2;
NW_FRONT_FOC = 145.1;
NW_BACK_FOC  = 157.7;
NW_PUPIL_IN  = 32.2;
NW_PUPIL_OUT = 32.6;

module nw180_metal() {
    color("Silver")
    ScrewHole(M67_D, L_FILTER, pitch = M67_P, tolerance = 0.15,
              position = [0, 0, NW_FRONT - L_FILTER])
    difference() {
        union() {
            translate([0, 0, -NW_REAR])
                cylinder(h = NW_CELL, d = NW_D_REAR, $fn = 96);
            translate([0, 0, -NW_NECK])
                cylinder(h = NW_NECK, d = NW_D_NECK, $fn = 96);
            cylinder(h = NW_SHUTTER, d = NW_D_TUBE, $fn = 128);
            translate([0, 0, NW_SHUTTER])
                cylinder(h = NW_TUBE, d = NW_D_TUBE, $fn = 128);
        }
        // Callout A: Ø70 step on the front face, outside the filter thread.
        translate([0, 0, NW_FRONT - 1.5])
            difference() {
                cylinder(h = 2, d = NW_D_TUBE + 1, $fn = 128);
                cylinder(h = 2.2, d = NW_D_MOUNT, $fn = 128);
            }
        // 1.1 mm groove where the barrel meets the shutter. The clamp seats here.
        translate([0, 0, NW_SHUTTER])
            difference() {
                cylinder(h = NW_GROOVE, d = NW_D_TUBE + 1, $fn = 128);
                cylinder(h = NW_GROOVE + 0.1, d = NW_D_TUBE - 2, $fn = 128);
            }
    }
    // The ring that clamps the flange. It comes in from the rear.
    color("Crimson")
        translate([0, 0, -NW_THREAD])
            ScrewThread(M39_D, NW_THREAD, pitch = M39_P, tolerance = 0);
}

module nw180(show_glass = false) {
    nw180_metal();
    if (show_glass) {
        color("SteelBlue", 0.35) {
            translate([0, 0, NW_FRONT - NW_FRONT_LIP])
                cylinder(h = 0.2, d = 40, center = true, $fn = 64);
            translate([0, 0, -NW_REAR + NW_REAR_LIP])
                cylinder(h = 0.2, d = 36, center = true, $fn = 64);
        }
        color("Orange", 0.25)
            translate([0, 0, -NW_FFD])
                cylinder(h = 0.2, d = 40, center = true, $fn = 64);
    }
}
