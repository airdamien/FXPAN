// Phone mounts for a D800 hot shoe. Each is two prints: a shoe foot, printed
// foot-down so the foot's layers run along the rails, and the phone part,
// printed flat on its back. They meet on a 45° key that centres itself, and
// one M3 countersunk from the phone side pulls them together into a nut
// trapped in the foot.
//
//   pm17_cradle    iPhone 17 Pro Max in the Apple silicone case, landscape,
//                  screen toward you, leaning back PM_TILT.
//   pm17_shoe      its foot, with the lean built in.
//   duo_tray_cased iPhone Duo lower half, half open like a laptop, cased.
//   duo_tray_bare  the same, bare.
//   duo_shoe       their foot.
//
// Duo sizes are a guess until it ships: 7.8" inner, 5.5" cover, 4.7 mm a
// half. Measure the half that lies in the tray and set DUO_BARE / DUO_CASED.

include <../lib/part_stamp.scad>

PART = "assembly"; // [assembly, pm17_cradle, pm17_shoe, duo_tray_cased, duo_tray_bare, duo_shoe]

$fn = 48;

// --- shoe foot, ISO 518 ------------------------------------------------------
FOOT_W = 18.3;   // across the shoe; the slot is 18.6
FOOT_L = 18.0;   // along the slide
FOOT_T = 2.05;   // under the rail lips. 1.9 rattled on the D800
NECK_W = 12.0;   // between the lips, 12.5 apart
NECK_H = 2.4;
PLAT_H = 4.0;
// The platform grows out of the neck at 45°, so it prints without a ledge.
function plat_z0() = FOOT_T + NECK_H;
function plat_z1() = plat_z0() + PLAT_H;
function plat_w()  = NECK_W + 2 * PLAT_H;

// --- key and fasteners -------------------------------------------------------
KEY_W = 12;
KEY_L = 16;
KEY_H = 2.5;
KEY_CLEAR = 0.2;
M3_D = 3.3;
M3_CSK_D = 6.4;
NUT_AF = 5.7;
NUT_T  = 2.6;
function nut_r() = NUT_AF / cos(30) / 2;

// --- iPhone 17 Pro Max, Apple silicone case ----------------------------------
PM_W    = 82.13;   // measured, across the long edges
PM_T    = 10.9;    // edge thickness in the case. Measure it.
PM_TILT = 30;      // screen leans back this far from vertical
PM_GAP  = 0.15;    // each side, at the long edges
PM_PLATEAU = 6;    // back clear of the frame, for the camera plateau
PM_PAD_X   = 24;   // the back only touches inside this; the plateau is past it
PM_FRAME_X = 72;
// Grips sit 13–25 mm from each end: past the corner radius, short of the
// Action button, and clear of Camera Control and the volume and side buttons.
PM_CLIP_X0 = 58;
PM_CLIP_X1 = 70;
PM_KEY_Y   = -20;  // below the middle, so the foot stays short
PM_LOW_Z   = 14;   // lowest point of the cradle over the foot's base

// --- iPhone Duo lower half: [along the hinge, hinge to front edge, thickness]
DUO_BARE  = [118.0, 82.0, 4.7];
DUO_CASED = [120.6, 83.4, 6.4];
DUO_GAP   = 0.2;
DUO_FLOOR = 2.5;
DUO_RIB_H = 3.5;   // the half rests on a cross, so a camera bump anywhere off it is clear
DUO_RIB_W = 16;
DUO_KEY_Y = 6;     // toward the hinge, under the standing half

CLIP_WALL = 2.0;
LIP_IN    = 1.4;   // over the case rim or bezel
LIP_T     = 1.6;

// -----------------------------------------------------------------------------
module rrect(w, l, r) {
    offset(r = r) square([w - 2 * r, l - 2 * r], center = true);
}

// 45° frustum. g grows it for the socket.
module key_frustum(g = 0, extra = 0) {
    hull() {
        translate([0, 0, -extra])
            linear_extrude(0.01 + extra)
                square([KEY_W + 2 * g, KEY_L + 2 * g], center = true);
        translate([0, 0, KEY_H + g - 0.01])
            linear_extrude(0.01)
                square([KEY_W - 2 * KEY_H + 2 * g, KEY_L - 2 * KEY_H + 2 * g],
                       center = true);
    }
}

// Socket on a back face at z = 0, screw out through face_z, countersunk.
module socket_cut(face_z) {
    key_frustum(KEY_CLEAR, 0.2);
    translate([0, 0, -1])
        cylinder(h = face_z + 2, d = M3_D);
    h = (M3_CSK_D - M3_D) / 2;
    translate([0, 0, face_z - h])
        cylinder(h = h + 0.01, d1 = M3_D, d2 = M3_CSK_D);
    translate([0, 0, face_z - 0.01])
        cylinder(h = 1, d = M3_CSK_D);
}

module shoe_foot() {
    hull() {
        translate([0, 0, 0.4])
            linear_extrude(FOOT_T - 0.4)
                square([FOOT_W, FOOT_L], center = true);
        linear_extrude(0.4)
            square([FOOT_W - 0.8, FOOT_L - 0.8], center = true);
    }
    translate([0, 0, FOOT_T - 0.01])
        linear_extrude(NECK_H + 0.02)
            square([NECK_W, FOOT_L], center = true);
    hull() {
        translate([0, 0, plat_z0()])
            linear_extrude(0.01) square([NECK_W, FOOT_L], center = true);
        translate([0, 0, plat_z1() - 0.01])
            linear_extrude(0.01) square([plat_w(), FOOT_L], center = true);
    }
}

// Inward lip on top of a grip wall, flat under the phone face, 45° on top so
// the phone pushes the wall out on the way in. Profile in (across, z); the
// wall's inner face is at across = 0, inward is negative.
module lip_2d(lip_z) {
    tip = -LIP_IN - 0.15;
    polygon([
        [CLIP_WALL, 0], [0, 0], [0, lip_z], [tip, lip_z], [tip, lip_z + 0.5],
        [CLIP_WALL, lip_z + 0.5 + CLIP_WALL - tip]
    ]);
}

// A grip along X, its wall's inner face at y = y_in, facing -y when s = +1.
module grip_x(x0, x1, y_in, s, lip_z) {
    translate([x0, y_in, 0])
        mirror([0, s > 0 ? 0 : 1, 0])
            rotate([90, 0, 90])
                linear_extrude(x1 - x0)
                    lip_2d(lip_z);
}

module grip_y(y0, y1, x_in, s, lip_z) {
    translate([x_in, y1, 0])
        mirror([s > 0 ? 0 : 1, 0, 0])
            rotate([90, 0, 0])
                linear_extrude(y1 - y0)
                    lip_2d(lip_z);
}

// --- 17 Pro Max --------------------------------------------------------------
function pm_in()      = PM_W / 2 + PM_GAP;
function pm_pad_top() = 3 + PM_PLATEAU;
function pm_lip_z()   = pm_pad_top() + PM_T + 0.1;
function pm_out()     = pm_in() + CLIP_WALL;
function pm_u() = [0, sin(PM_TILT), cos(PM_TILT)];
function pm_n() = [0, -cos(PM_TILT), sin(PM_TILT)];
// Cradle back-centre in the foot's frame: phone centre over the foot, lowest
// edge PM_LOW_Z up.
function pm_p() = [0, (pm_pad_top() + PM_T / 2) * cos(PM_TILT),
                   PM_LOW_Z + pm_out() * cos(PM_TILT)];

module pm17_place() {
    translate(pm_p()) rotate([90 - PM_TILT, 0, 0]) children();
}

module pm17_cradle() {
    difference() {
        union() {
            linear_extrude(3)
                rrect(2 * PM_FRAME_X, 2 * pm_out(), 4);
            hull() {
                translate([0, 0, 2.9])
                    linear_extrude(0.1)
                        rrect(2 * PM_PAD_X, PM_W - 6, 3);
                translate([0, 0, pm_pad_top() - 0.1])
                    linear_extrude(0.1)
                        rrect(2 * PM_PAD_X - 2, PM_W - 8, 2);
            }
            for (sx = [-1, 1], s = [-1, 1]) {
                x0 = sx > 0 ? PM_CLIP_X0 : -PM_CLIP_X1;
                grip_x(x0, x0 + PM_CLIP_X1 - PM_CLIP_X0, s * pm_in(), s,
                       pm_lip_z());
            }
        }
        translate([0, PM_KEY_Y, 0])
            socket_cut(pm_pad_top());
        for (sx = [-1, 1])
            translate([sx * 41, 0, -1])
                linear_extrude(5)
                    rrect(20, PM_W - 18, 5);
        translate([0, 12, pm_pad_top() - STAMP_DEPTH])
            part_stamp_cut("pm17_cradle", size = 2.8);
    }
}

module pm17_shoe() {
    difference() {
        union() {
            shoe_foot();
            hull() {
                translate([0, 0, plat_z1() - 0.01])
                    linear_extrude(0.01)
                        square([plat_w(), FOOT_L], center = true);
                pm17_place()
                    translate([0, PM_KEY_Y, -4])
                        linear_extrude(4)
                            square([KEY_W + 14, KEY_L + 10], center = true);
            }
            pm17_place()
                translate([0, PM_KEY_Y, -0.01])
                    key_frustum();
        }
        // Nut goes in from the back along the screw; the screw pulls it
        // onto the end of its tunnel, just behind the key.
        pm17_place()
            translate([0, PM_KEY_Y, 0]) {
                translate([0, 0, -40])
                    cylinder(h = 40 + KEY_H + 1, d = M3_D);
                translate([0, 0, -40])
                    rotate([0, 0, 90])
                        cylinder(h = 40 - 3, r = nut_r(), $fn = 6);
            }
    }
}

// --- Duo ---------------------------------------------------------------------
// x along the hinge, -y toward you, hinge at +y. The half's back on the cross.
function duo_back_z() = DUO_FLOOR + DUO_RIB_H;

module duo_tray(d, tag) {
    len = d[0]; dep = d[1]; t = d[2];
    xi = len / 2 + DUO_GAP;
    yf = -dep / 2 - DUO_GAP;
    yr = dep / 2;
    lip_z = duo_back_z() + t + 0.1;
    xo = xi + CLIP_WALL;
    difference() {
        union() {
            translate([0, (yf - CLIP_WALL + yr + 2.5) / 2, 0])
                linear_extrude(DUO_FLOOR)
                    rrect(2 * xo, yr + 2.5 - (yf - CLIP_WALL), 4);
            translate([0, 0, DUO_FLOOR - 0.01])
                linear_extrude(DUO_RIB_H + 0.01) {
                    square([len - 2, DUO_RIB_W], center = true);
                    square([DUO_RIB_W, dep - 2], center = true);
                    translate([0, DUO_KEY_Y])
                        rrect(KEY_W + 12, KEY_L + 12, 3);
                }
            // Front corners: an L, side and front, that the front edge slides
            // under. Rear grips flex out as the hinge end presses down.
            for (s = [-1, 1]) {
                grip_y(yf - CLIP_WALL, yf + 14, s * xi, s, lip_z);
                grip_x(s > 0 ? xi - 14 : -xi - CLIP_WALL,
                       s > 0 ? xi + CLIP_WALL : -xi + 14,
                       yf, -1, lip_z);
                grip_y(yr - 34, yr - 20, s * xi, s, lip_z);
                // Low stops behind the rear edge, under the spine.
                translate([s * (len / 2 - 5) - 3, yr + DUO_GAP, 0])
                    cube([6, 2.3, duo_back_z() + 2]);
            }
        }
        translate([0, DUO_KEY_Y, 0])
            socket_cut(duo_back_z());
        translate([-len / 4 - DUO_RIB_W / 4, -dep / 4 - DUO_RIB_W / 4,
                   DUO_FLOOR - STAMP_DEPTH])
            part_stamp_cut(tag, size = 2.2);
    }
}

module duo_shoe() {
    difference() {
        union() {
            shoe_foot();
            translate([0, 0, plat_z1() - 0.01])
                key_frustum();
        }
        translate([0, 0, -1])
            cylinder(h = plat_z1() + KEY_H + 2, d = M3_D);
        // Nut in from underneath, up against the roof; recessed off the
        // shoe's contacts.
        translate([0, 0, -0.1])
            rotate([0, 0, 90])
                cylinder(h = plat_z1() - 1.0 + 0.1, r = nut_r(), $fn = 6);
    }
}

// -----------------------------------------------------------------------------
module assembly() {
    color("DimGray") pm17_shoe();
    color("SlateGray") pm17_place() pm17_cradle();
    if ($preview)
        color("Black", 0.4) pm17_place()
            translate([0, 0, pm_pad_top() + PM_T / 2])
                cube([166, PM_W, PM_T], center = true);
    translate([0, 160, 0]) {
        color("DimGray") duo_shoe();
        translate([0, -DUO_KEY_Y, plat_z1()])
            color("SlateGray") duo_tray(DUO_CASED, "duo_tray_cased");
    }
}

if (PART == "assembly") assembly();
else if (PART == "pm17_cradle") pm17_cradle();
else if (PART == "pm17_shoe") pm17_shoe();
else if (PART == "duo_tray_cased") duo_tray(DUO_CASED, "duo_tray_cased");
else if (PART == "duo_tray_bare") duo_tray(DUO_BARE, "duo_tray_bare");
else if (PART == "duo_shoe") duo_shoe();
