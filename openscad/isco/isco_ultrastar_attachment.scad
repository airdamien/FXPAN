// ISCO Ultra-Star HD Cinemascope attachment (2× afocal front adapter).
// Include this; open WATCH_ME.scad to look at it on the EL-Nikkor 180/5.6N.
//
// Origin is the rear face of the barrel — the plane that faces the taking
// lens. +Z is the front, toward the subject. The Ø67 mount thread hangs
// out behind that face, in −Z.
//
// Measured on this unit (US turret / Cinelux class):
//   67.0   rear thread major OD
//   70.6   rear tube OD — RafCamera 71 mm clamp land
//   ~165   overall, rear face to front rim
//
// The input barrel (front, light in) is Ø90. The steps between the 70.6
// clamp land and that barrel follow the photos.
// Lengths are shares of the 165 mm. Caliper a land and replace it.
//
// One solid. Each section overlaps the next by 0.4 mm.

include <../lib/threads.scad>

SQUEEZE        = 2.0;

REAR_THREAD_OD = 67.0;    // black rear ring, measured thread OD
D_REAR_TUBE    = 70.6;    // long gold barrel, clamp land
D_STEP         = 74.0;
D_SCALE_A      = 78.0;    // rear focus scale
D_SCALE_B      = 82.0;    // front focus scale
D_KNURL        = 86.0;
D_FRONT        = 90.0;    // input barrel, measured
D_FRONT_BORE   = 78.0;
D_REAR_GLASS   = 43.6;
D_FRONT_GLASS  = 48.75;

L_OAL          = 165;    // rear face of the barrel to the front rim
L_THREAD_PAST  = 5;     // only about 5 mm of Ø67 thread, into −Z
THREAD_PITCH   = 1.0;
L_REAR_TUBE    = 70;    // rear face to the first step up
L_SCALE        = 22;    // focus ring ahead of that step
L_KNURL        = 28;
L_NOSE         = 45;    // Ø90 input barrel; 70+22+28+45 = 165
L_FRONT_RECESS = 6;
L_TOTAL        = L_OAL;

function z_scale() = L_REAR_TUBE;
function z_knurl() = z_scale() + L_SCALE;
function z_nose()  = z_knurl() + L_KNURL;

module barrel(z, h, d) {
    translate([0, 0, z])
        cylinder(h = h, d = d, $fn = 128);
}

module attachment_metal() {
    difference() {
        union() {
            translate([0, 0, -L_THREAD_PAST])
                ScrewThread(REAR_THREAD_OD, L_THREAD_PAST + 0.6,
                            pitch = THREAD_PITCH, tolerance = 0);
            barrel(0, L_REAR_TUBE + 0.4, D_REAR_TUBE);
            barrel(z_scale(), L_SCALE + 0.4, D_SCALE_A);
            barrel(z_knurl(), L_KNURL + 0.4, D_KNURL);
            barrel(z_nose(), L_NOSE, D_FRONT);
        }
        translate([0, 0, L_OAL - L_FRONT_RECESS])
            cylinder(h = L_FRONT_RECESS + 1, d = D_FRONT_BORE, $fn = 96);
    }
}

module glass_marks() {
    color("SteelBlue", 0.35) {
        translate([0, 0, 8])
            cylinder(h = 0.2, d = D_REAR_GLASS, center = true, $fn = 64);
        translate([0, 0, L_OAL - 6])
            cylinder(h = 0.2, d = D_FRONT_GLASS, center = true, $fn = 64);
    }
}

module isco_ultrastar(show_glass = false, cut = false) {
    if (cut)
        difference() {
            attachment_metal();
            translate([-D_FRONT, -D_FRONT / 2, -L_THREAD_PAST - 1])
                cube([D_FRONT, D_FRONT, L_OAL + L_THREAD_PAST + 2]);
        }
    else
        attachment_metal();
    if (show_glass)
        glass_marks();
}
