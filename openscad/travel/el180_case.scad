// Travel tube for the EL-Nikkor 180/5.6N with the helicoid and the
// M65→M62 adapter left on it.
//
// The stack screws in on the helicoid's M65 male, the same thread that
// goes into the stem. Collapse the helicoid first. The cap screws on past
// the front rim and stops on a shoulder, so it cannot reach the glass.
//
// Measured stack, seating face of the helicoid at z = 0, +z toward the front:
//   M65 male          4.47   behind the seat, into the adapter
//   helicoid body    16.58   collapsed, Ø82.67 widest
//   printed m65_ring  8      set RING_ADD to 0 when the flangeless ring is on
//   flange to rim    53.1    the 180, Ø76 barrel
//   air              16      rim to the inside of the cap
//
// The lens threads into a small adapter. The adapter's outer thread is
// coarse and steep, and that is what screws into the bottom of the can.
// Print the can and the cap standing up; those threads hold themselves.
// The adapter is the only part with a real M65, seat-face down.
// The mark STL shares the cap's origin and sits in the pocket.
//   openscad -D 'PART="tube"'    -o el180_tube.stl    el180_case.scad
//   openscad -D 'PART="cover"'   -o el180_cover.stl   el180_case.scad
//   openscad -D 'PART="adapter"' -o el180_adapter.stl el180_case.scad
//   openscad -D 'PART="mark"'    -o el180_mark.stl    el180_case.scad

include <../lib/threads.scad>
include <../isco/el_nikkor_180n.scad>

PART = "assembly"; // [assembly:Assembly, tube:Tube, cover:Cover, adapter:Adapter, mark:EL180 mark, section:Section]

M65_MAJOR = 65;
M65_PITCH = 1.0;
M65_TOL   = 0.45;    // same female the metal male already starts in
M65_MALE  = 4.47;
M65_H     = 6.5;     // deeper than the male, so the body face seats

// Printed-to-printed thread between the adapter and the can.
// 50° flanks stand up without support. The flange, not the thread,
// stops the adapter, so the lens seat stays at z = 0.
AD_MAJOR    = 76;
AD_PITCH    = 3;
AD_LEN      = 9;
AD_EXTRA    = 1.8;   // female runs past the male
AD_TOL      = 0.4;
AD_TOOTH    = 50;
AD_FLANGE   = 2.6;
AD_FLANGE_OD = 83.2; // slips the Ø85 bore, covers the helicoid face
AD_SKIN     = 2.8;   // floor under the thread

HELI_OD   = 82.67;
HELI_BODY = 16.58;
RING_ADD  = 8;       // printed m65_ring. 0 for the flangeless ring.
RING_OD   = 72;
AIR       = 16;      // front rim to the inside of the cap

BORE  = 85;          // clears the Ø82.67 helicoid

CAP_MAJOR = 98;
CAP_PITCH = 2;
CAP_LEN   = 8;
CAP_TOL   = 0.4;
CAP_END   = 4.4;   // 2 mm of shell under the mark pocket
// Library tooth angle. 50° lands near 48° from horizontal after the
// tolerance is applied, so the underside of each tooth supports itself.
CAP_TOOTH = 50;
// ScrewHole's cutter crest sits this far outside the major.
CAP_OD = 1.01 * CAP_MAJOR + 1.5 * CAP_TOL + 2 * 3.6;
// Same diameter as the cap-thread crests, so the thread is cut into
// the top of the tube instead of standing out from a smaller wall.
BODY_OD = CAP_MAJOR + 0.25 * CAP_TOL;

function stack_front() = HELI_BODY + RING_ADD + front_z;
function mouth_z()     = stack_front() + AIR;
function shoulder_z()  = mouth_z() - CAP_LEN;
function tube_z0()     = -(AD_FLANGE + AD_LEN + AD_EXTRA + AD_SKIN);

// Second-color inlay in the outer face. 1.5 mm sits in the pocket,
// 0.5 mm stands proud of the top. 2 mm overall prints solid.
MARK_SIZE  = 24;
MARK_DEEP  = 2.0;
MARK_PROUD = 0.5;
MARK_FIT   = 0.2;

module mark_2d() {
    text("el180", size = MARK_SIZE,
         font = "Liberation Sans:style=Bold",
         halign = "center", valign = "center");
}

module mark_inlay() {
    linear_extrude(MARK_DEEP)
        offset(delta = -MARK_FIT)
            mark_2d();
}

function mark_z() = CAP_LEN + CAP_END - (MARK_DEEP - MARK_PROUD);

module mark_pocket() {
    // Opens through the outer face only. The mouth side stays closed.
    translate([0, 0, mark_z()])
        linear_extrude(MARK_DEEP - MARK_PROUD + 0.3)
            mark_2d();
}

// Diamond lattice. Two helices, opposite hands, about 45° on the unrolled
// wall. The cut stays inside the wall: crossings are no deeper than one groove.
PAT_BITE = 1.75;
PAT_W    = 5.6;

function pat_n(od) = max(8, round(PI * od / 32));
function pat_twist(od, h) = h * 360 / (PI * od);

module pat_peg(i, z0, h, twist, r, steps) {
    t = i / steps;
    rotate([0, 0, twist * t])
        translate([r, 0, z0 + h * t])
            cube([PAT_BITE + 2.4, PAT_W, h / steps + 0.45], center = true);
}

module helix_grooves(z0, z1, od, twist) {
    h = z1 - z0;
    steps = max(8, round(abs(twist) / 12));
    r = od / 2 - PAT_BITE / 2 + 1.2;
    n = pat_n(od);
    for (k = [0:n - 1])
        for (i = [0:steps - 1])
            rotate([0, 0, k * 360 / n])
                hull() {
                    pat_peg(i,     z0, h, twist, r, steps);
                    pat_peg(i + 1, z0, h, twist, r, steps);
                }
}

module wall_pattern(z0, z1, od) {
    tw = pat_twist(od, z1 - z0);
    // Grooves run out of the wall on a slope instead of ending on a
    // flat shelf. The shelf under the cap threads was a downward face.
    fade = 4.2;
    R = od / 2;
    deep = 2 * (R - PAT_BITE - 1.2);
    proud = 2 * (R + 0.4);
    difference() {
        intersection() {
            union() {
                helix_grooves(z0, z1, od,  tw);
                helix_grooves(z0, z1, od, -tw);
            }
            translate([0, 0, (z0 + z1) / 2])
                cube([od + 30, od + 30, z1 - z0], center = true);
        }
        translate([0, 0, z1 - fade])
            cylinder(h = fade + 0.2, d1 = deep, d2 = proud, $fn = 96);
        translate([0, 0, z0 - 0.2])
            cylinder(h = fade + 0.2, d1 = proud, d2 = deep, $fn = 96);
    }
}

module tube() {
    color("SlateGray")
    difference() {
        union() {
            translate([0, 0, tube_z0()])
                cylinder(h = shoulder_z() - tube_z0(),
                         d = BODY_OD, $fn = 160);
            translate([0, 0, shoulder_z() - 0.12])
                ScrewThread(CAP_MAJOR, CAP_LEN + 0.12,
                            pitch = CAP_PITCH, tolerance = CAP_TOL,
                            tooth_angle = CAP_TOOTH,
                            tip_height = 1.6, tip_min_fract = 0.2);
        }
        // Female for the adapter. Stops short of the ledge so the
        // flange seats on the ledge, not on the last thread.
        translate([0, 0, -(AD_FLANGE + 0.2 + AD_LEN + AD_EXTRA)])
            ScrewThread(1.01 * AD_MAJOR + 1.25 * AD_TOL,
                        AD_LEN + AD_EXTRA,
                        pitch = AD_PITCH, tolerance = AD_TOL,
                        tooth_angle = AD_TOOTH);
        // Opens into the counterbore, leaving a ledge for the flange.
        translate([0, 0, -AD_FLANGE - 1.75])
            cylinder(h = 1.85, d1 = AD_MAJOR - 1, d2 = AD_MAJOR + 3,
                     $fn = 96);
        translate([0, 0, -AD_FLANGE - 0.02])
            cylinder(h = AD_FLANGE + 0.2, d = AD_FLANGE_OD + 0.8, $fn = 160);
        wall_pattern(tube_z0() + 1.5, shoulder_z() - 2.5, BODY_OD);
        translate([0, 0, -0.04])
            cylinder(h = mouth_z() + 4, d = BORE, $fn = 160);
    }
}

// z = 0 is the helicoid seat. The male thread hangs below the flange.
// Print seat-down. The M65 is a through hole for the metal male.
module adapter() {
    color("Tan")
    difference() {
        ScrewHole(M65_MAJOR, AD_FLANGE + AD_LEN + 0.4,
                  pitch = M65_PITCH, tolerance = M65_TOL,
                  position = [0, 0, -AD_FLANGE - AD_LEN - 0.2])
            union() {
                translate([0, 0, -AD_FLANGE])
                    cylinder(h = AD_FLANGE, d = AD_FLANGE_OD, $fn = 160);
                translate([0, 0, -AD_FLANGE - AD_LEN])
                    ScrewThread(AD_MAJOR, AD_LEN + 0.3,
                                pitch = AD_PITCH, tolerance = AD_TOL,
                                tooth_angle = AD_TOOTH);
            }
        // Nose taper, so the male finds the can's thread.
        translate([0, 0, -AD_FLANGE - AD_LEN - 0.05])
            cylinder(h = 2.0, d1 = AD_MAJOR + 1, d2 = AD_MAJOR - 3,
                     $fn = 96);
        // Lead-in on the seat, so the metal male finds the thread.
        translate([0, 0, -1.15])
            cylinder(h = 1.4, d1 = M65_MAJOR - 2, d2 = M65_MAJOR + 2.6,
                     $fn = 96);
        // Flats so the flange can still be turned as it seats.
        for (a = [0, 180])
            rotate([0, 0, a])
                translate([AD_FLANGE_OD / 2 + 0.2, 0, -AD_FLANGE / 2])
                    cube([3.2, 16, AD_FLANGE + 0.6], center = true);
    }
}

// z = 0 is the open mouth. The end wall is at +z.
module cover() {
    color("DimGray")
    difference() {
        union() {
            ScrewHole(CAP_MAJOR, CAP_LEN - 0.05,
                      pitch = CAP_PITCH, tolerance = CAP_TOL,
                      tooth_angle = CAP_TOOTH)
                cylinder(h = CAP_LEN, d = CAP_OD, $fn = 160);
            translate([0, 0, CAP_LEN - 0.15])
                cylinder(h = CAP_END + 0.15, d = CAP_OD, $fn = 160);
        }
        // Side wall only. The end disk stays a plain cylinder so the
        // closed face is flat, not a patterned crown.
        wall_pattern(1.4, CAP_LEN - 0.8, CAP_OD);
        translate([0, 0, -0.2])
            cylinder(h = 1.6, d = CAP_MAJOR + 2.5, $fn = 96);
        mark_pocket();
    }
}

module mark() {
    color("Gold") mark_inlay();
}

// Seated stack. The male hangs through the seat into the M65 thread.
module stack() {
    color("Goldenrod") {
        translate([0, 0, -M65_MALE])
            cylinder(h = M65_MALE, d = M65_MAJOR - 1.2, $fn = 96);
        cylinder(h = HELI_BODY, d = HELI_OD, $fn = 128);
    }
    if (RING_ADD > 0)
        color("Silver")
            translate([0, 0, HELI_BODY])
                cylinder(h = RING_ADD, d = RING_OD, $fn = 96);
    color("SteelBlue")
        translate([0, 0, HELI_BODY + RING_ADD])
            el180n();
}

echo(str("el180 case  bore ", BORE,
         "  rim z ", stack_front(),
         "  cap face z ", mouth_z(),
         "  tube ", mouth_z() - tube_z0(), " long",
         "  cap od ", CAP_OD));

if (PART == "tube")
    tube();
else if (PART == "cover")
    cover();
else if (PART == "adapter")
    adapter();
else if (PART == "mark")
    translate([0, 0, mark_z()]) mark();
else if (PART == "section")
    difference() {
        union() {
            tube();
            adapter();
            translate([0, 0, shoulder_z()]) {
                cover();
                translate([0, 0, mark_z()]) mark();
            }
            stack();
        }
        translate([0, -220, -40]) cube([400, 440, 220]);
    }
else {
    %tube();
    adapter();
    stack();
    translate([0, 0, shoulder_z() + 34]) {
        cover();
        translate([0, 0, mark_z()]) mark();
    }
}
