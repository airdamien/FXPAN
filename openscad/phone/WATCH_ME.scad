// Phone mounts for a D800 hot shoe. Each is two prints: a shoe foot, printed
// foot-down so the foot's layers run along the rails, and the phone part,
// printed flat on its back. They meet on a minor spline: straight teeth with
// a short lead chamfer, so the joint centres on the teeth and cannot rock
// on them, and one M3 countersunk from the phone side pulls the faces
// together into a nut trapped in the foot.
//
//   pm17_cradle    iPhone 17 Pro Max in the Apple silicone case, landscape,
//                  screen toward you, leaning back PM_TILT.
//   pm17_shoe      its foot, with the lean built in.
//   pm17_ms_cradle the same phone, nearer vertical, with a press-in MagSafe
//                  puck, the camera plateau left open, USB-C on the right.
//   pm17_ms_shoe   its foot.
//   duo_tray_cased iPhone Duo lower half, half open like a laptop, cased.
//   duo_tray_bare  the same, bare.
//   duo_shoe       their foot.
//
// Duo bare sizes are Apple's published specs; the cased set adds the
// regular two-part case estimate from the DUO_CASED comment below.
// Measure the cased half when it lands and trim DUO_CASED to fit.

include <../lib/part_stamp.scad>

PART = "assembly"; // [assembly, pm17_cradle, pm17_shoe, pm17_ms_cradle, pm17_ms_shoe, duo_tray_cased, duo_tray_bare, duo_shoe]

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
KEY_H = 3.2;
KEY_CLEAR = 0.15;  // per side, on the spline teeth
SPL_T    = 1.5;    // spline tooth depth
SPL_TW   = 2.4;    // spline tooth width
SPL_LEAD = 0.8;    // lead chamfer at the tip; the rest runs straight
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

// The nearer-vertical mount. 12° off the panorama camera's axis instead of
// 30, so its view lines up with the stitch. The phone lies the other way
// round: USB-C on the right, camera plateau on the left.
PM_MS_TILT = 12;
PM_LEN     = 166;  // long edge, in the case
// Camera plateau on the 1:1 model (Furkan Bahçavan, Printables 1482045).
// The outline, not the lens rings: x 5.35..72.50 and y 120.80..158.13 on
// the bare phone (body x -0.45..78.43, y 0..163.43). That is 67.2 across
// by 37.3 along, centred on the width, 5.3 in from the top edge, corners
// about 9. In the case the island measures 72 across and 42.6 along.
// The cradle holds the cased phone centred on the same point, so the
// window sits at -57.8 along.
PM_CAM   = [42.6, 72];    // opening, along the phone and across it
PM_CAM_X = -57.8;         // centre, phone centre at 0, plateau toward -X
PM_CAM_Y = 0;
// MagSafe puck, press fit. The ring's centre is the middle of the phone,
// which clears the plateau.
PM_MS_X   = 4;
PM_MS_D   = 55.7;       // snug on the 55.5 puck
PM_MS_T   = 4.6;        // puck is 4.5, finishes just under the plate
// USB-C, right end. The opening is wider than the plug so a cable seats.
PM_USB_W  = 16;
PM_USB_H  = 8;

// --- iPhone Duo lower half: [along the hinge, hinge to front edge, thickness]
// Bare is one half of the open phone: 117.8 along the hinge, 164.6 / 2 =
// 82.3 hinge to front edge, 5.2 thick. Cased adds the regular two-part
// case estimate: ~1.1 over each capped end and the front edge, ~1.3 of
// back wall. Design envelope was 121 / 88 / 14.5 closed; the tray only
// holds one half, so its numbers sit well inside that.
DUO_BARE  = [117.8, 82.3, 5.2];
DUO_CASED = [120.0, 83.5, 6.5];
DUO_GAP   = 0.2;
// Base thickness. One flat plane on the bottom, and deep enough that the
// countersunk screw and the cable groove both finish inside it.
DUO_FLOOR = 5.0;
DUO_RIB_H = 3.5;   // the half rests on a cross, so a camera bump anywhere off it is clear
DUO_RIB_W = 16;
// The shoe joint sits under the puck pocket, where the pad is thick enough
// for the countersunk M3 and its nut.
function duo_key_xy() = MS_XY;
// Apple MagSafe puck, measured: 55.5 across, 4.5 thick, cable out the rim.
// It slides in from the side under a rail, so the tray holds it rather than
// a lip it has to squeeze past. The slot sits in the front quadrant, clear
// of the shoe screw at the hinge and of the camera corner.
MS_D  = 55.7;      // pocket, a snug press fit on the 55.5 puck
MS_T  = 4.6;       // puck is 4.5; finishes just under the tray top
MS_XY = [14, -8];
// The puck presses in from the top. The cable leaves through a groove from
// the pocket rim to the tray's back edge.
MS_CABLE = 4.0;    // groove width, a braided MagSafe lead
MS_CABLE_D = 3.2;  // groove depth below the pocket floor
MS_FLOOR = DUO_RIB_H;
// The countersink cone needs this much pad below the pocket floor to taper
// from the head diameter to the screw bore. It stays inside the base, so
// the bottom of the tray is still the one flat plane it prints on.
DUO_PAD  = 1.6;

CLIP_WALL = 2.0;
LIP_IN    = 1.4;   // over the case rim or bezel
LIP_T     = 1.6;

// -----------------------------------------------------------------------------
module rrect(w, l, r) {
    offset(r = r) square([w - 2 * r, l - 2 * r], center = true);
}

// Minor spline in plan: a core with straight teeth on all four sides,
// inside the old KEY_W × KEY_L envelope. g grows it for the socket.
// Three teeth ride each long side, two each end, so the joint has hard
// contact all round: no rocking on a taper, no turning on the screw.
module spline_2d(g = 0) {
    offset(r = g)
        union() {
            square([KEY_W - 2 * SPL_T, KEY_L - 2 * SPL_T], center = true);
            for (sx = [-1, 1], ty = [-5.25, 0, 5.25])
                translate([sx * (KEY_W / 2 - SPL_T), ty])
                    square([2 * SPL_T, SPL_TW], center = true);
            for (sy = [-1, 1], tx = [-3.2, 3.2])
                translate([tx, sy * (KEY_L / 2 - SPL_T)])
                    square([SPL_TW, 2 * SPL_T], center = true);
        }
}

// Straight spline for most of its height, so an engaged joint only has
// KEY_CLEAR of play wherever it bears. The lead chamfer is at the base,
// widening downward onto the platform, so the shoe prints foot-down with
// no overhang and the top of every tooth stays full width.
module spline_key(g = 0, extra = 0) {
    hull() {
        translate([0, 0, -extra])
            linear_extrude(0.01 + extra)
                spline_2d(g - 0.65);
        translate([0, 0, SPL_LEAD])
            linear_extrude(0.01)
                spline_2d(g);
    }
    translate([0, 0, SPL_LEAD])
        linear_extrude(KEY_H - SPL_LEAD)
            spline_2d(g);
}

// Socket on a back face at z = 0, screw out through face_z, countersunk.
module socket_cut(face_z) {
    spline_key(KEY_CLEAR, 0.2);
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

// Nearer vertical, and the phone runs the other way: camera plateau at -X,
// USB-C at +X.
function pm_ms_p() = [0, (pm_pad_top() + PM_T / 2) * cos(PM_MS_TILT),
                      PM_LOW_Z + pm_out() * cos(PM_MS_TILT)];

module pm17_ms_place() {
    translate(pm_ms_p()) rotate([90 - PM_MS_TILT, 0, 0]) children();
}

module pm17_ms_cradle() {
    lip_z = pm_pad_top() + PM_T + 0.1;
    difference() {
        union() {
            linear_extrude(3)
                rrect(PM_LEN + 8, 2 * pm_out(), 4);
            hull() {
                translate([PM_MS_X, 0, 2.9])
                    linear_extrude(0.1) circle(d = PM_MS_D + 10, $fn = 96);
                translate([PM_MS_X, 0, pm_pad_top() - 0.1])
                    linear_extrude(0.1) circle(d = PM_MS_D + 6, $fn = 96);
            }
            // Clips on the right end and the bottom edge. The plateau fills
            // the top-left corner, so that end and the top edge stay open.
            for (s = [-1, 1]) {
                grip_x(PM_LEN / 2 - 14, PM_LEN / 2 + CLIP_WALL, s * pm_in(),
                       s, lip_z);
                grip_y(s * pm_in() - 12, s * pm_in() + CLIP_WALL,
                       PM_LEN / 2 - 14, -s, lip_z);
            }
            grip_x(-PM_LEN / 2 + 30, PM_LEN / 2 - 30, -pm_in(), -1, lip_z);
        }
        // Camera plateau, open through the plate.
        translate([PM_CAM_X, PM_CAM_Y, -1])
            linear_extrude(pm_pad_top() + 2)
                rrect(PM_CAM[0], PM_CAM[1], 11);
        // MagSafe puck, pressed in from the front.
        translate([PM_MS_X, 0, pm_pad_top() - PM_MS_T])
            cylinder(h = PM_MS_T + 1, d = PM_MS_D, $fn = 96);
        // USB-C on the right end.
        translate([PM_LEN / 2 - 2, 0, pm_pad_top() + PM_T / 2])
            cube([PM_USB_W, PM_USB_W, PM_USB_H], center = true);
        // Countersink opens at the puck recess floor, wide end up, so the
        // head sits flush under the puck. The cone stops above the spline.
        translate([0, PM_KEY_Y, 0])
            socket_cut(pm_pad_top() - PM_MS_T);
        translate([30, 14, pm_pad_top() - STAMP_DEPTH])
            part_stamp_cut("pm17_ms", size = 2.8);
    }
}

// Foot side of the socket face. At 12° the hotshoe straddles that plane, so
// a hull of the whole platform crosses it and swallows the spline.
module pm_ms_back() {
    pm17_ms_place()
        translate([0, 0, -100.2])
            cube([400, 400, 200], center = true);
}

module pm17_ms_shoe() {
    difference() {
        union() {
            shoe_foot();
            // Pad ends on the socket plane. The spline stands on it, clear
            // of the arm, for the full tooth height.
            pm17_ms_place()
                translate([0, PM_KEY_Y, -4])
                    linear_extrude(4)
                        square([KEY_W + 14, KEY_L + 10], center = true);
            hull() {
                intersection() {
                    shoe_foot();
                    pm_ms_back();
                }
                pm17_ms_place()
                    translate([0, PM_KEY_Y, -4])
                        linear_extrude(0.01)
                            square([KEY_W + 14, KEY_L + 10], center = true);
            }
            pm17_ms_place()
                translate([0, PM_KEY_Y, -0.01])
                    spline_key();
        }
        pm17_ms_place()
            translate([0, PM_KEY_Y, 0]) {
                translate([0, 0, -40])
                    cylinder(h = 40 + KEY_H + 1, d = M3_D);
                translate([0, 0, -40])
                    rotate([0, 0, 90])
                        cylinder(h = 40 - 3, r = nut_r(), $fn = 6);
            }
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
                    spline_key();
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
                    translate(duo_key_xy())
                        rrect(KEY_W + 12, KEY_L + 12, 3);
                }
            // Pad under the MagSafe pocket. It fills the base only; the
            // pocket is cut through the tray above it, so nothing stands
            // over the puck but the lip.
            if (tag == "duo_tray_cased")
                translate([MS_XY[0], MS_XY[1], -0.01])
                    cylinder(h = duo_back_z() + 0.02, d = MS_D + 8, $fn = 96);
            // The base out to the back edge, so the cable groove has a floor
            // the whole way and the bottom stays one plane.
            if (tag == "duo_tray_cased")
                translate([MS_XY[0] - (MS_CABLE + 8) / 2, MS_XY[1], -0.01])
                    cube([MS_CABLE + 8, yr - MS_XY[1] + 2, DUO_FLOOR + 0.02]);
            // Front corners: an L, side and front, that the front edge slides
            // under. The side grips stay low, below the hinge, so the phone
            // folds down past them. The rear stops are only bumpers.
            for (s = [-1, 1]) {
                grip_y(yf - CLIP_WALL, yf + 14, s * xi, s, lip_z);
                grip_x(s > 0 ? xi - 14 : -xi - CLIP_WALL,
                       s > 0 ? xi + CLIP_WALL : -xi + 14,
                       yf, -1, lip_z);
                grip_y(yr - 30, yr - 14, s * xi, s, lip_z);
                translate([s * (len / 2 - 5) - 3, yr + DUO_GAP, 0])
                    cube([6, 2.3, duo_back_z() + 2]);
            }
        }
        translate(duo_key_xy()) {
            translate([0, 0, -DUO_PAD - 0.2])
                spline_key(KEY_CLEAR, 0.2);
            translate([0, 0, -DUO_PAD - 1])
                cylinder(h = DUO_PAD + MS_FLOOR + 2, d = M3_D);
            // Screw drops in from above, through the puck recess. The cone
            // opens at the recess floor and stops at the spline socket, so
            // the head sits flush under the puck and the socket survives.
            translate([0, 0, MS_FLOOR - 0.01])
                cylinder(h = duo_back_z() - MS_T - MS_FLOOR + 0.02,
                         d1 = M3_D, d2 = M3_CSK_D);
        }
        translate([-len / 4 - DUO_RIB_W / 4, -dep / 4 - DUO_RIB_W / 4,
                   DUO_FLOOR - STAMP_DEPTH])
            part_stamp_cut(tag, size = 2.2);
        // MagSafe puck, cased tray only. The bare tray has no case magnets
        // to meet it.
        if (tag == "duo_tray_cased")
            duo_magsafe_cut(yr);
    }
}

// Round pocket for the puck, open out the back of the tray. A lip rings the
// rim everywhere except that rear opening, so the puck slides in from behind
// and the lip holds it down once it is in.
module duo_magsafe_cut(yr) {
    z1 = duo_back_z();
    translate(MS_XY) {
        // Straight recess, open at the top. The puck presses in.
        translate([0, 0, z1 - MS_T])
            cylinder(h = MS_T + 0.2, d = MS_D, $fn = 128);
        // Cable groove. Rounded floor, runs straight back from the pocket
        // rim and out through the tray's back edge.
        translate([-MS_CABLE / 2, MS_D / 2 - 4, -0.2])
            cube([MS_CABLE, yr + 8 - MS_XY[1] - MS_D / 2,
                  MS_CABLE_D + z1 + 0.2]);
        translate([0, MS_D / 2 - 4, -0.2])
            rotate([-90, 0, 0])
                cylinder(h = yr + 8 - MS_XY[1] - MS_D / 2,
                         d = MS_CABLE, $fn = 32);
    }
}

module duo_shoe() {
    difference() {
        union() {
            shoe_foot();
            translate([0, 0, plat_z1() - 0.01])
                spline_key();
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
    translate([0, -150, 0]) {
        color("DimGray") pm17_ms_shoe();
        color("SlateGray") pm17_ms_place() pm17_ms_cradle();
    }
    translate([0, 160, 0]) {
        color("DimGray") duo_shoe();
        translate([-duo_key_xy()[0], -duo_key_xy()[1], plat_z1() + DUO_PAD])
            color("SlateGray") duo_tray(DUO_CASED, "duo_tray_cased");
    }
}

if (PART == "assembly") assembly();
else if (PART == "pm17_cradle") pm17_cradle();
else if (PART == "pm17_shoe") pm17_shoe();
else if (PART == "pm17_ms_cradle") pm17_ms_cradle();
else if (PART == "pm17_ms_shoe") pm17_ms_shoe();
else if (PART == "duo_tray_cased") duo_tray(DUO_CASED, "duo_tray_cased");
else if (PART == "duo_tray_bare") duo_tray(DUO_BARE, "duo_tray_bare");
else if (PART == "duo_shoe") duo_shoe();
