// EL-Nikkor 180mm f/5.6N. Include this; open WATCH_ME.scad to look at it.
//
// Origin is the flange seating face, the face that bottoms on the stem.
// +Z is the front of the lens. −Z runs through the mount thread toward the
// focal plane. The Ø60 barrel sticks out past that thread.
//
// Sheet dimensions, and where they landed:
//   62.6   sheet overall. This lens's rear barrel is longer; see L_PAST.
//   10     front ring
//    9     external M62×1, the whole recess under the front cover
//   37.1   main barrel
//    6     sheet shoulder. On this lens it is the same Ø76 as the barrel,
//          not the Ø78 / Ø88 lip drawn around the mount thread.
//    8     M62×1 mount thread, from the seating face back
//    9.2   Ø60 barrel past that thread, measured on this lens
//          (the sheet's rear tip was only 9.5 from the flange)
//   76     barrel OD, straight down to the mount thread
//   60     rear barrel, the tube that has to clear the stem bore
//   62×1   rear mount thread, and the external thread under the front cover
//   58×0.75  retaining-ring thread, both cells. Internal, not cut here.
//   65, 4.3, and the 6 radial holes are on the sheet without a station or a
//          hole diameter, so they are not in the solid.
//
// Optical stations, same origin:
//   flange focal distance 158.5 → focal plane at z = −158.5
//   back focus 152.7 → rear vertex at −5.8
//   vertex spacing 57.1 → front vertex at 51.3
//   front rim is at 53.1, so the rim-to-vertex gap is the sheet's 1.8
//   entrance pupil Ø31, 30.1 behind the front vertex
//   exit pupil Ø32.4, 29.4 ahead of the rear vertex
//   H to H' is the sheet's 0.3
// Focal length is 180. The flange register is 158.5, so the rear principal
// point sits 21.5 mm in front of this flange.

include <../lib/threads.scad>

L_FRONT   = 10;
L_EXT      = 9;       // M62×1 male, the whole recess under the front cover
FRONT_BORE = 57;      // M58 cell, clear of the front element
L_BARREL  = 37.1;
L_SHLDR   = 6;
L_THREAD  = 8;
L_PAST    = 9.2;   // Ø60 barrel beyond the mount thread, this lens
L_REAR    = L_THREAD + L_PAST;

D_BARREL  = 76;
D_REAR    = 60;
M62_D     = 62;
M62_P     = 1.0;

FFD       = 158.5;
BACK_FOC  = 152.7;
VV        = 57.1;     // vertex to vertex
FRONT_LIP = 1.8;      // front rim to front vertex
PUPIL_IN  = 31;
PUPIL_IN_Z = 30.1;    // behind the front vertex
PUPIL_OUT = 32.4;
PUPIL_OUT_Z = 29.4;   // ahead of the rear vertex
HH        = 0.3;
FOCAL     = 180;

// Flange face at 0. Front rim is the sheet stack ahead of the mount.
front_z = L_FRONT + L_BARREL + L_SHLDR;          // 53.1
rear_z  = -L_REAR;                                // −17.2
rear_vertex_z = -(FFD - BACK_FOC);                // −5.8
front_vertex_z = rear_vertex_z + VV;              // 51.3

module lens_metal() {
    difference() {
        union() {
            // Ø60 barrel: through the thread and 9.2 mm past it.
            translate([0, 0, rear_z])
                cylinder(h = L_REAR, d = D_REAR, $fn = 96);
            translate([0, 0, rear_z + (L_REAR - L_THREAD)])
                ScrewThread(M62_D, L_THREAD, pitch = M62_P, tolerance = 0);
            // Ø76 ends at the shoulder. The recess in front of it is all thread.
            cylinder(h = L_SHLDR + L_BARREL + (L_FRONT - L_EXT),
                     d = D_BARREL, $fn = 128);
            translate([0, 0, L_SHLDR + L_BARREL + (L_FRONT - L_EXT)])
                ScrewThread(M62_D, L_EXT, pitch = M62_P, tolerance = 0);
        }
        translate([0, 0, front_z - L_EXT])
            cylinder(h = L_EXT + 0.2, d = FRONT_BORE, $fn = 96);
    }
}

module pupil(d) {
    color("Gold", 0.55)
        cylinder(h = 0.15, d = d, center = true, $fn = 64);
}

module glass_marks() {
    color("SteelBlue", 0.35) {
        translate([0, 0, front_vertex_z])
            cylinder(h = 0.2, d = 40, center = true, $fn = 64);
        translate([0, 0, rear_vertex_z])
            cylinder(h = 0.2, d = 36, center = true, $fn = 64);
    }
    translate([0, 0, front_vertex_z - PUPIL_IN_Z])
        pupil(PUPIL_IN);
    translate([0, 0, rear_vertex_z + PUPIL_OUT_Z])
        pupil(PUPIL_OUT);
    // Rear principal point: one focal length in front of the focal plane.
    color("Red")
        translate([0, 0, -FFD + FOCAL])
            cylinder(h = HH, d = 8, $fn = 24);
    color("Orange", 0.25)
        translate([0, 0, -FFD])
            cylinder(h = 0.2, d = 40, center = true, $fn = 64);
}

// cut opens the metal. show_glass draws the pupils, vertices and focal plane.
module el180n(show_glass = false, cut = false) {
    if (cut)
        difference() {
            lens_metal();
            translate([0, -D_BARREL, rear_z - 1])
                cube([D_BARREL, D_BARREL * 2, front_z - rear_z + 2]);
        }
    else
        lens_metal();
    if (show_glass)
        glass_marks();
}
