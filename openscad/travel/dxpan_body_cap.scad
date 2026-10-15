// Dust cap for the DXPAN chassis lens port (M65 in the body lip).
// Screw it on when the helicoid and lens are off; the arms keep their
// own caps.
//
// The lip is 4.25 mm of M65×1. The male is longer than that so the
// flange seats on the skin and the tip clears the back of the crests.
// The whole male stands past the flange — the flange used to swallow
// it and leave under 3 mm in the hole.
//
// Print outer face down. z = 0 is that face. The male points up.
// Flanks are 50° so the thread holds itself; the flare under the
// seal is 45°. The chassis female stays the 30° hole the helicoid uses.
//
//   openscad -o dxpan_body_cap.stl dxpan_body_cap.scad
//
// Preview on the chassis: dxpan_body_cap_section.scad

include <../lib/threads.scad>

// Chassis lens port (dx_body.scad / params.scad). Keep in sync.
M65_MAJOR       = 65;
EL180_M62_PITCH = 1.0;
EL180_M62_TOL   = 0.45;
STEM_W_CLOCK    = 90;
M65_HELI_OD     = 82.67;
M65_HELI_CLEAR  = 1.0;

MALE_LEN  = 5.2;   // 4.25 in the lip, the rest out the back of the crests
CAP_TOOTH = 50;    // printed male. Clears the 30° female crest.
DOME_H    = 8;
FLANGE_H  = 2.2;
// Covers the helicoid relief on the lens face and lands on flat skin.
SEAL_OD   = M65_HELI_OD + M65_HELI_CLEAR + 5;
GRIP_OD   = SEAL_OD - 4;

function flare_h() = (SEAL_OD - GRIP_OD) / 2;
function seat_z()  = DOME_H + flare_h() + FLANGE_H;

module cap() {
    color("DimGray")
    difference() {
        union() {
            cylinder(h = DOME_H, d = GRIP_OD, $fn = 160);
            translate([0, 0, DOME_H])
                cylinder(h = flare_h(), d1 = GRIP_OD, d2 = SEAL_OD, $fn = 160);
            translate([0, 0, DOME_H + flare_h()])
                cylinder(h = FLANGE_H, d = SEAL_OD, $fn = 160);
            rotate([0, 0, STEM_W_CLOCK])
                translate([0, 0, seat_z()])
                    ScrewThread(M65_MAJOR, MALE_LEN,
                                pitch = EL180_M62_PITCH,
                                tolerance = EL180_M62_TOL,
                                tooth_angle = CAP_TOOTH,
                                tip_height = 1.1, tip_min_fract = 0.3);
        }
        for (a = [0, 180])
            rotate([0, 0, a])
                translate([GRIP_OD / 2 - 0.3, 0, (DOME_H - 0.1) / 2])
                    cube([3.0, 18, DOME_H - 0.1], center = true);
    }
}

// Seating face at the origin, male along +Z (into the chassis).
module cap_seated() {
    translate([0, 0, -seat_z()])
        cap();
}

echo(str("dxpan body cap  M65×", EL180_M62_PITCH,
         "  engaged ", 4.25, " of ", MALE_LEN,
         "  seal od ", SEAL_OD,
         "  print height ", seat_z() + MALE_LEN));

cap();
