// Clamp and adapter that hang the ISCO Ultra-Star on the EL-Nikkor 180
// filter thread, plus a bench stand at the FXPAN optical-axis height.
//
// One piece. Female M62×1 runs onto the external thread on the 180
// and the back face seats on the Ø76 shoulder behind that thread.
// The collar grips the Ø70.6 land. A shoulder stops that face; the
// Ø67 thread nests in a pocket and cannot reach the 180. The slot
// closes the collar only — it does not cut the M62.
// Stand: saddle under the Ø90 barrel. Axis height is 70 mm — BOX_Z/2 +
// chassis plinth + base, with the base on the bench. 1/4-20 insert in
// the foot, same Ø8.1 × 6.4 as the chassis, opening downward.

include <../lib/threads.scad>

M62_D = 62;
M62_P = 1.0;
EXT_MALE   = 9;       // male thread, the whole recess on the 180
M62_ENGAGE = 8.6;     // female, a hair short so it seats on the shoulder
M62_LEN    = EXT_MALE;

CLAMP_ID   = 71.0;    // 70.6 land + clearance
CLAMP_T    = 5.0;
CLAMP_W    = 18;      // along the tube, on the 70 mm land
CLAMP_OD   = CLAMP_ID + 2 * CLAMP_T;
STOP_T     = 3.0;     // shoulder the Ø70.6 face sits on
STOP_BORE  = 68.4;    // Ø67 thread passes; the 70.6 face does not
THREAD_POCKET = 7;    // deeper than the 5 mm thread
OPTIC_D    = 57;      // M58 cell; still stops the Ø67 thread

// CNC Kitchen / Ruthex short M3×5.7. Hole is the insert OD.
M3_INSERT_D = 4.0;
M3_INSERT_L = 5.7;
M3_CLEAR    = 3.4;
M3_HEAD_D   = 6.0;
M3_HEAD_H   = 3.2;
EAR_T       = 10;
EAR_W       = 16;

FLANGE_T   = 4;
FLANGE_OD  = 84;
SLOT_W     = 1.6;
function seat_z()     = M62_LEN;
function shoulder_z() = M62_LEN + FLANGE_T + THREAD_POCKET;

// FXPAN: axis above the underside of the base.
AXIS_H     = 70;
SADDLE_D   = 91.0;     // Ø90 barrel, loose
SADDLE_W   = 32;
FOOT_T     = 10;
TRIPOD_D   = 8.1;
TRIPOD_L   = 6.4;

module m3_insert_hole() {
    cylinder(h = M3_INSERT_L + 0.4, d = M3_INSERT_D, $fn = 32);
    translate([0, 0, M3_INSERT_L])
        cylinder(h = 1.2, d1 = M3_INSERT_D, d2 = M3_INSERT_D + 1.2, $fn = 32);
}

module isco_clamp(tone = "DimGray") {
    color(tone)
    difference() {
        ScrewHole(M62_D, M62_ENGAGE, pitch = M62_P, tolerance = 0.2)
        union() {
            translate([0, 0, -0.2])
                cylinder(h = seat_z() + FLANGE_T + 0.2, d = FLANGE_OD, $fn = 96);
            translate([0, 0, seat_z() + FLANGE_T - 0.2])
                cylinder(h = THREAD_POCKET + CLAMP_W + 0.2, d = CLAMP_OD, $fn = 128);
            translate([CLAMP_OD / 2 - 1, -EAR_W / 2, shoulder_z()])
                cube([EAR_T + 8, EAR_W, CLAMP_W]);
        }
        translate([0, 0, -0.2])
            cylinder(h = shoulder_z() + 0.2, d = OPTIC_D, $fn = 64);
        translate([0, 0, seat_z() + FLANGE_T - 0.1])
            cylinder(h = THREAD_POCKET + 0.2, d = STOP_BORE, $fn = 72);
        translate([0, 0, shoulder_z() - 0.1])
            cylinder(h = CLAMP_W + 1, d = CLAMP_ID, $fn = 96);
        // Slot through the collar only.
        translate([CLAMP_ID / 2 - 1, -SLOT_W / 2, shoulder_z() - 0.1])
            cube([CLAMP_OD, SLOT_W, CLAMP_W + 1]);
        for (z = [shoulder_z() + CLAMP_W * 0.32, shoulder_z() + CLAMP_W * 0.68])
            translate([CLAMP_OD / 2 + EAR_T / 2, 0, z])
                rotate([-90, 0, 0]) {
                    translate([0, 0, -EAR_W / 2 - 0.2])
                        m3_insert_hole();
                    translate([0, 0, -0.1])
                        cylinder(h = EAR_W / 2 + 0.2, d = M3_CLEAR, $fn = 24);
                    cylinder(h = M3_HEAD_H, d = M3_HEAD_D, $fn = 24);
                }
    }
}

module isco_stand() {
    saddle_z = AXIS_H;
    foot_x = 130;
    foot_y = 100;
    color("SteelBlue")
    difference() {
        union() {
            cube([foot_x, foot_y, FOOT_T]);
            translate([25, 30, FOOT_T])
                cube([80, 40, saddle_z - SADDLE_D / 2 - FOOT_T + 8]);
            translate([15, (foot_y - SADDLE_W) / 2, FOOT_T])
                cube([100, SADDLE_W, saddle_z + 8]);
        }
        translate([-1, foot_y / 2, saddle_z])
            rotate([0, 90, 0])
                cylinder(h = foot_x + 2, d = SADDLE_D, $fn = 96);
        translate([foot_x / 2, foot_y / 2, -0.2])
            cylinder(h = TRIPOD_L + 1.2, d = TRIPOD_D, $fn = 48);
    }
}
