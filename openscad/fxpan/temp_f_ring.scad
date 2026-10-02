// Temporary printed stand-in for one metal M52-to-F ring on a camera
// helicoid. M52×1 male into the helicoid front, the Archive-663 F flange on
// the helicoid face, faced down to the metal ring's CAM_F_RING so the focus
// numbers do not move.
//
// Print male down, with build-plate supports under the flange overhang.
// The flange lands on the helicoid face; the male is shorter than the front
// female so it never bottoms first.
//
//   OpenSCAD -o stls/fxpan/temp_f_ring.stl openscad/fxpan/temp_f_ring.scad

include <params.scad>
include <../lib/threads.scad>
include <fxp_f_mount.scad>

screw_resolution = 0.25;

TEMP_MALE  = 4.5;    // into the helicoid's ~5 mm front female
// Into a metal female, and printed males come out fat. Crest lands ~51.7.
TEMP_MAJOR = CAM_HELI_NOSE - 0.4;
TEMP_BORE  = 44;     // the 40 mm F lip stays the stop
// Where the bottomed ring leaves the bayonet depends on the helicoid's thread
// start. Degrees; set from a test fit and reprint.
TEMP_CLOCK = 0;

trim = F_FMOUNT_STACK - CAM_F_RING;

module temp_f_ring() {
    union() {
        translate([0, 0, -trim])
            intersection() {
                f_mount_stl_raw();
                translate([0, 0, trim])
                    cylinder(h = F_STL_HEIGHT, d = F_STL_OD + 2, $fn = 96);
            }
        rotate([0, 0, TEMP_CLOCK])
            difference() {
                // Turned over so the lead-in taper is at the free tip.
                translate([0, 0, 0.4])
                    rotate([180, 0, 0])
                        ScrewThread(TEMP_MAJOR, TEMP_MALE + 0.4,
                                    pitch = CAM_HELI_PITCH,
                                    tolerance = CAM_HELI_TOL,
                                    tooth_height = CAM_HELI_TOOTH,
                                    tip_height = 1.0,
                                    tip_min_fract = 0.75);
                translate([0, 0, -TEMP_MALE - 1])
                    cylinder(h = TEMP_MALE + 1.6, d = TEMP_BORE, $fn = 96);
            }
    }
}

temp_f_ring();
