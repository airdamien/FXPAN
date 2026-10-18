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
//   duo_flat_cradle the Duo opened flat, landscape, in the case, at the
//                  same 12° aim as the Pro Max scene mount.
//   duo_flat_shoe  its foot.
//
// Duo bare sizes are Apple's published specs; the cased set adds the
// regular two-part case estimate from the DUO_CASED comment below.
// Measure the cased half when it lands and trim DUO_CASED to fit.

include <../lib/part_stamp.scad>

PART = "assembly"; // [assembly, pm17_cradle, pm17_shoe, pm17_ms_cradle, pm17_ms_shoe, duo_tray_cased, duo_tray_bare, duo_shoe, duo_flat_cradle, duo_flat_shoe]

$fn = 48;

// --- shoe foot, ISO 518 ------------------------------------------------------
FOOT_W = 18.3;   // across the shoe; the slot is 18.6
FOOT_L = 36.0;   // along the slide, long enough to enter from either end
POST_L = 16.0;   // upright, only the middle; both ends of the rail stay clear
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
// Inside the case, across the long edges. Bare body is 78.88
// (x -0.45..78.43); the case adds 3.52.
PM_W    = 82.4;
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
// Long edge in the case. Bare length is 163.43; the case adds the
// same 3.52 it adds across the width.
PM_LEN     = 166.95;
// Camera plateau on the 1:1 model (Furkan Bahçavan, Printables 1482045).
// The outline, not the lens rings: x 5.35..72.50 and y 120.80..158.13 on
// the bare phone (body x -0.45..78.43, y 0..163.43). That is 67.2 across
// by 37.3 along, centred on the width, 5.3 in from the top edge, corners
// about 9. In the case the island measures 72 across and 42.6 along.
// The cradle holds the cased phone centred on the same point, so the
// window sits at -57.8 along.
PM_CAM   = [42.6, 72];    // cased island, along the phone and across it
PM_CAM_X = -57.8;         // centre, phone centre at 0, plateau toward -X
PM_CAM_Y = 0;
PM_CAM_FIT = 1.5;         // extra around the island so the case drops in
// MagSafe puck, press fit. The near edge sits halfway from the old
// centre-of-phone edge (x = -23.9) to the camera island (x = -36.5).
PM_MS_X   = -2.3;
PM_MS_D   = 55.7;       // snug on the 55.5 puck
PM_MS_T   = 4.6;        // puck is 4.5, finishes just under the plate
// USB-C, right end. The opening is wider than the plug so a cable seats.
PM_USB_W  = 16;
PM_USB_H  = 8;
// Bare body corner is 15 mm. The case grows it, same as the Duo.
PM_EDGE   = 17;
PM_MS_LIP = 12.0;       // three times the 4 mm wall; phone edge is 10.9

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
// Pro Max lead exits the right end above the USB-C port. The port owns
// the centre; this is the centre of the groove, clear of the plug.
PM_CABLE_Y = PM_USB_W / 2 + 8 + MS_CABLE / 2;
PM_CABLE_R = 12;   // bend off the puck rim before the groove runs straight
MS_FLOOR = DUO_RIB_H;
// The countersink cone needs this much pad below the pocket floor to taper
// from the head diameter to the screw bore. It stays inside the base, so
// the bottom of the tray is still the one flat plane it prints on.
DUO_PAD  = 1.6;
// Opened flat, landscape, in the case. The hinge runs along Y, so the two
// halves sit left and right and the long edge is horizontal. Each cased
// half is 83.5 hinge-to-outer, and the hinge is bare, so the open width is
// two halves. 12° is the same aim as the Pro Max scene mount. The plate is
// tall enough that the puck recess, its cable groove, and the centre
// countersink all finish above the back face.
DUO_FLAT_X    = 167.0;
DUO_FLAT_Y    = 120.0;
DUO_FLAT_T    = 6.5;
DUO_FLAT_TILT = 12;
DUO_FLAT_Z    = 9.0;
DUO_FLAT_KEY_Y = -20;   // below centre, so the foot stays short
DUO_FLAT_MS   = [49.6, 0];  // under the camera island, not the half centre
// Main camera pill, on the back half. Read off a 1:1 model of that half
// (body 82.3 hinge-to-outer by 118.3 along the hinge): the raised footprint
// is 56.4 by 21.5, 4.5 in from the outer edge and 4.7 down from the top.
// Hinge at cradle x=0, top at +Y. The case lip adds 2 mm.
DUO_CAM   = [60.4, 25.5];
DUO_CAM_X = 49.6;
DUO_CAM_Y = 43.7;
// Bare body corner is 13 mm. The case grows it. The retainer follows
// that curve around the bottom corners, then slopes down the side.
DUO_EDGE  = 15;
DUO_LIP_H = 4.0;          // phone is 6.5 thick; the screen stays above this
DUO_USB_X = 41.2;         // centre of the camera half, bottom edge
DUO_USB_W = 16;           // wider than the plug, same as the Pro Max opening
DUO_FN    = 160;          // corner segments

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

// The part that slides in the shoe. Nothing else occupies this height.
module shoe_rail() {
    linear_extrude(FOOT_T)
        square([FOOT_W, FOOT_L], center = true);
    translate([0, 0, FOOT_T - 0.01])
        linear_extrude(NECK_H + 0.02)
            square([NECK_W, FOOT_L], center = true);
}

// Upright above the neck, only in the middle, so either end of the rail
// can enter the shoe.
module shoe_post() {
    hull() {
        translate([0, 0, plat_z0()])
            linear_extrude(0.01) square([NECK_W, POST_L], center = true);
        translate([0, 0, plat_z1() - 0.01])
            linear_extrude(0.01) square([plat_w(), POST_L], center = true);
    }
}

module shoe_foot() {
    shoe_rail();
    shoe_post();
}

// Behind the upright's back face. The pad's outer face is that plane;
// cutting to it lets the shoe print lying on its back.
module upright_back_clear() {
    translate([-200, -200, -400])
        cube([400, 400, 396]);
}

// On the projecting ends, remove everything the hotshoe lips would hit.
// The rail itself stays.
module shoe_end_clear() {
    reach = FOOT_L / 2 - POST_L / 2 + 0.4;
    for (s = [-1, 1])
        translate([0, s * (POST_L / 2 + reach / 2), FOOT_T])
            difference() {
                translate([0, 0, plat_z1() / 2])
                    cube([FOOT_W + 40, reach, plat_z1()], center = true);
                translate([0, 0, plat_z1() / 2])
                    cube([NECK_W - 0.4, reach + 2, plat_z1() + 2], center = true);
            }
}

// Inward lip on top of a grip wall, flat under the phone face, 45° on top so
// the phone pushes the wall out on the way in. Profile in (across, z); the
// wall's inner face is at across = 0, inward is negative.
module lip_2d(lip_z, tip = -LIP_IN - 0.15) {
    // Outer crest stays put when the tip reaches further in, so a longer
    // side lip meets the corner arc at the same top edge.
    crest = CLIP_WALL + LIP_IN + 0.15;
    polygon([
        [CLIP_WALL, 0], [0, 0], [0, lip_z], [tip, lip_z], [tip, lip_z + 0.5],
        [CLIP_WALL, lip_z + 0.5 + crest]
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

module grip_y(y0, y1, x_in, s, lip_z, tip = -LIP_IN - 0.15) {
    translate([x_in, y1, 0])
        mirror([s > 0 ? 0 : 1, 0, 0])
            rotate([90, 0, 0])
                linear_extrude(y1 - y0)
                    lip_2d(lip_z, tip);
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
// USB-C at +X. The low edge is the retainer, outside the phone.
function pm_ms_out() = PM_W / 2 + CLIP_WALL;
function pm_ms_p() = [0, (pm_pad_top() + PM_T / 2) * cos(PM_MS_TILT),
                      PM_LOW_Z + pm_ms_out() * cos(PM_MS_TILT)];

module pm17_ms_place() {
    translate(pm_ms_p()) rotate([90 - PM_MS_TILT, 0, 0]) children();
}

// Cased phone outline. High segment count so the corners read smooth.
module pm_ms_outline(grow = 0) {
    $fn = DUO_FN;
    rrect(PM_LEN + 2 * grow, PM_W + 2 * grow, PM_EDGE + grow);
}

// Bottom-right corner of the retainer, same centre and radius as the plate.
module pm_ms_lip_quadrant() {
    $fn = DUO_FN;
    cx = PM_LEN / 2 - PM_EDGE;
    cy = -(PM_W / 2 - PM_EDGE);
    h = pm_pad_top() + PM_MS_LIP;
    linear_extrude(h)
        difference() {
            translate([cx, cy]) circle(r = PM_EDGE + CLIP_WALL);
            translate([cx, cy]) circle(r = PM_EDGE);
            translate([cx - 300, cy - 300]) square([300, 600]);
            translate([cx - 300, cy]) square([600, 300]);
        }
    linear_extrude(pm_pad_top())
        difference() {
            translate([cx, cy]) circle(r = PM_EDGE);
            translate([cx, cy]) circle(r = PM_EDGE - 0.4);
            translate([cx - 300, cy - 300]) square([300, 600]);
            translate([cx - 300, cy]) square([600, 300]);
        }
}

// Past the corner the retainer slopes back into the plate. It stops
// short of the USB so a plug can seat on the right end.
module pm_ms_lip_side() {
    x0 = PM_LEN / 2;
    y0 = -(PM_W / 2 - PM_EDGE);
    y1 = -(PM_USB_W / 2 + 6);
    h = pm_pad_top() + PM_MS_LIP;
    hull() {
        translate([x0 - 0.4, y0 - 0.3, 0])
            cube([CLIP_WALL + 0.4, 0.4, h]);
        translate([x0 - 0.01, y1, 0])
            cube([0.2, 0.4, pm_pad_top()]);
    }
}

module pm_ms_lip() {
    y0 = -PM_W / 2;
    cx = PM_LEN / 2 - PM_EDGE;
    h = pm_pad_top() + PM_MS_LIP;
    translate([-cx - 0.4, y0 - CLIP_WALL, 0])
        cube([2 * cx + 0.8, CLIP_WALL + 0.4, h]);
    pm_ms_lip_quadrant();
    pm_ms_lip_side();
    mirror([1, 0, 0]) {
        pm_ms_lip_quadrant();
        pm_ms_lip_side();
    }
}

// Groove from the puck rim. Wider at the rim, then a bend into the
// straight run so the lead is not kinked as it leaves the puck.
module pm_ms_cable_cut() {
    dx = sqrt(pow(PM_MS_D / 2, 2) - pow(PM_CABLE_Y, 2));
    a = atan2(PM_CABLE_Y, dx);
    R = PM_CABLE_R;
    S = [PM_MS_X + dx, PM_CABLE_Y];
    C = S + R * [sin(a), -cos(a)];
    E = C + R * [0, 1];
    z = pm_pad_top() - PM_MS_T - MS_CABLE_D;
    h = PM_MS_T + MS_CABLE_D + 1;
    mouth = MS_CABLE + 4;
    n = 12;
    translate([0, 0, z])
        linear_extrude(h)
            union() {
                // Constant width around the bend, so the inside of the
                // turn stays a smooth radius. It narrows on the straight.
                for (i = [0:n - 1]) {
                    a0 = a * (1 - i / n);
                    a1 = a * (1 - (i + 1) / n);
                    hull() {
                        translate(i == 0 ? S - 3 * [cos(a), sin(a)]
                                         : C + R * [-sin(a0), cos(a0)])
                            circle(d = mouth, $fn = 24);
                        translate(C + R * [-sin(a1), cos(a1)])
                            circle(d = mouth, $fn = 24);
                    }
                }
                hull() {
                    translate(E) circle(d = mouth, $fn = 24);
                    translate([E[0] + 14, E[1] - MS_CABLE / 2])
                        square([0.2, MS_CABLE]);
                }
                translate([E[0] + 14, E[1] - MS_CABLE / 2])
                    square([PM_LEN / 2 + 2 - (E[0] + 14), MS_CABLE]);
            }
}

module pm17_ms_cradle() {
    difference() {
        union() {
            linear_extrude(pm_pad_top()) pm_ms_outline(0);
            pm_ms_lip();
        }
        // Camera plateau, open through the plate, grown so the cased
        // island sits down instead of hanging on the rim.
        translate([PM_CAM_X, PM_CAM_Y, -1])
            linear_extrude(pm_pad_top() + 2)
                rrect(PM_CAM[0] + 2 * PM_CAM_FIT, PM_CAM[1] + 2 * PM_CAM_FIT,
                      11 + PM_CAM_FIT);
        // MagSafe puck, pressed in from the phone side.
        translate([PM_MS_X, 0, pm_pad_top() - PM_MS_T])
            cylinder(h = PM_MS_T + 1, d = PM_MS_D, $fn = 96);
        // Cable groove, open through the top. A wide mouth and a bend
        // at the rim, then straight out the right end above the USB port.
        pm_ms_cable_cut();
        // USB-C on the right end, centred. Anything outside the phone
        // edge in this band is open so a cable seats.
        translate([PM_LEN / 2, -PM_USB_W / 2, -0.1])
            cube([12, PM_USB_W, pm_pad_top() + PM_MS_LIP + 2]);
        // Countersink opens at the puck recess floor, wide end up, so the
        // head sits flush under the puck. The cone stops above the spline.
        translate([0, PM_KEY_Y, 0])
            socket_cut(pm_pad_top() - PM_MS_T);
        translate([52, 4, pm_pad_top() - STAMP_DEPTH])
            part_stamp_cut("pm17_ms", size = 2.8);
    }
}

// Everything on the foot side of a socket face. A 12° arm hulled from the
// whole hotshoe crosses that plane and swallows the spline, so the arm is
// hulled only from this half-space.
module socket_halfspace() {
    translate([0, 0, -100.2])
        cube([400, 400, 200], center = true);
}

module pm_ms_back() {
    pm17_ms_place() socket_halfspace();
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
                    translate([0, 0, plat_z1() - 0.4])
                        cube([80, 80, 1], center = true);
                    shoe_post();
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
        shoe_end_clear();
        pm17_ms_place() upright_back_clear();
    }
}

module pm17_shoe() {
    difference() {
        union() {
            shoe_foot();
            hull() {
                translate([0, 0, plat_z1() - 0.01])
                    linear_extrude(0.01)
                        square([plat_w(), POST_L], center = true);
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
        shoe_end_clear();
        pm17_place() upright_back_clear();
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

function duo_flat_out() = DUO_FLAT_Y / 2 + CLIP_WALL;

// Phone outline, grown outward. High segment count so the corners read smooth.
module duo_outline(grow = 0) {
    $fn = DUO_FN;
    rrect(DUO_FLAT_X + 2 * grow, DUO_FLAT_Y + 2 * grow, DUO_EDGE + grow);
}
function duo_flat_p() = [0, (DUO_FLAT_Z + DUO_FLAT_T / 2) * cos(DUO_FLAT_TILT),
                         PM_LOW_Z + duo_flat_out() * cos(DUO_FLAT_TILT)];

module duo_flat_place() {
    translate(duo_flat_p()) rotate([90 - DUO_FLAT_TILT, 0, 0]) children();
}

module duo_flat_cradle() {
    xh = DUO_FLAT_X / 2;
    difference() {
        union() {
            linear_extrude(DUO_FLAT_Z) duo_outline(0);
            duo_bottom_lip();
        }
        // Hinge barrel, split so it does not eat the centre screw seat.
        translate([-5, -DUO_FLAT_Y / 2, DUO_FLAT_Z - 1.8])
            cube([10, DUO_FLAT_KEY_Y - 16 - (-DUO_FLAT_Y / 2), 4]);
        translate([-5, DUO_FLAT_KEY_Y + 16, DUO_FLAT_Z - 1.8])
            cube([10, DUO_FLAT_Y / 2 - (DUO_FLAT_KEY_Y + 16), 4]);
        // Main camera pill, right half, near the top. A stadium: the ends
        // are full semicircles, so the radius is half the height.
        translate([DUO_CAM_X, DUO_CAM_Y, -1])
            linear_extrude(DUO_FLAT_Z + 2)
                hull() {
                    translate([-DUO_CAM[0] / 2 + DUO_CAM[1] / 2, 0])
                        circle(d = DUO_CAM[1], $fn = 64);
                    translate([DUO_CAM[0] / 2 - DUO_CAM[1] / 2, 0])
                        circle(d = DUO_CAM[1], $fn = 64);
                };
        // MagSafe puck, pressed in from the phone side, on the right half.
        translate([DUO_FLAT_MS[0], DUO_FLAT_MS[1], DUO_FLAT_Z - MS_T])
            cylinder(h = MS_T + 1, d = MS_D, $fn = 96);
        // Cable groove, open through the top face, from the puck rim out
        // the right edge. Floor sits MS_CABLE_D below the pocket.
        translate([DUO_FLAT_MS[0] + MS_D / 2 - 4, -MS_CABLE / 2,
                   DUO_FLAT_Z - MS_T - MS_CABLE_D])
            cube([xh + 8 - (DUO_FLAT_MS[0] + MS_D / 2 - 4), MS_CABLE,
                  MS_T + MS_CABLE_D + 1]);
        // Shoe screw, countersunk flush with the pad. The head is under the
        // phone, clear of the hinge groove.
        translate([0, DUO_FLAT_KEY_Y, 0])
            socket_cut(DUO_FLAT_Z);
        translate([-DUO_FLAT_X / 4, 20, DUO_FLAT_Z - STAMP_DEPTH])
            part_stamp_cut("duo_flat", size = 2.6);
        // USB-C through the lip and the plate ledge in front of it.
        translate([DUO_USB_X - DUO_USB_W / 2, -90, -0.1])
            cube([DUO_USB_W, 90 - (DUO_FLAT_Y / 2 - 0.4),
                  DUO_FLAT_Z + DUO_LIP_H + 2]);
    }
}

// Bottom-right corner of the retainer, same centre and radius as the plate.
module duo_lip_quadrant() {
    $fn = DUO_FN;
    cx = DUO_FLAT_X / 2 - DUO_EDGE;
    cy = -(DUO_FLAT_Y / 2 - DUO_EDGE);
    h = DUO_FLAT_Z + DUO_LIP_H;
    linear_extrude(h)
        difference() {
            translate([cx, cy]) circle(r = DUO_EDGE + CLIP_WALL);
            translate([cx, cy]) circle(r = DUO_EDGE);
            translate([cx - 300, cy - 300]) square([300, 600]);
            translate([cx - 300, cy]) square([600, 300]);
        }
    linear_extrude(DUO_FLAT_Z)
        difference() {
            translate([cx, cy]) circle(r = DUO_EDGE);
            translate([cx, cy]) circle(r = DUO_EDGE - 0.4);
            translate([cx - 300, cy - 300]) square([300, 600]);
            translate([cx - 300, cy]) square([600, 300]);
        }
}

// Past the corner the retainer slopes back into the plate edge.
module duo_lip_side() {
    x0 = DUO_FLAT_X / 2;
    y0 = -(DUO_FLAT_Y / 2 - DUO_EDGE);
    h = DUO_FLAT_Z + DUO_LIP_H;
    hull() {
        translate([x0 - 0.4, y0 - 0.3, 0])
            cube([CLIP_WALL + 0.4, 0.4, h]);
        translate([x0 - 0.01, y0 + 16, 0])
            cube([0.2, 0.4, DUO_FLAT_Z]);
    }
}

// Retainer along the bottom, around both corners, then down into the plate.
module duo_bottom_lip() {
    y0 = -DUO_FLAT_Y / 2;
    cx = DUO_FLAT_X / 2 - DUO_EDGE;
    h = DUO_FLAT_Z + DUO_LIP_H;
    translate([-cx - 0.4, y0 - CLIP_WALL, 0])
        cube([2 * cx + 0.8, CLIP_WALL + 0.4, h]);
    duo_lip_quadrant();
    duo_lip_side();
    mirror([1, 0, 0]) {
        duo_lip_quadrant();
        duo_lip_side();
    }
}

module duo_flat_back() {
    duo_flat_place() socket_halfspace();
}

module duo_flat_shoe() {
    difference() {
        union() {
            shoe_foot();
            duo_flat_place()
                translate([0, DUO_FLAT_KEY_Y, -4])
                    linear_extrude(4)
                        square([KEY_W + 14, KEY_L + 10], center = true);
            hull() {
                intersection() {
                    translate([0, 0, plat_z1() - 0.4])
                        cube([80, 80, 1], center = true);
                    shoe_post();
                    duo_flat_back();
                }
                duo_flat_place()
                    translate([0, DUO_FLAT_KEY_Y, -4])
                        linear_extrude(0.01)
                            square([KEY_W + 14, KEY_L + 10], center = true);
            }
            duo_flat_place()
                translate([0, DUO_FLAT_KEY_Y, -0.01])
                    spline_key();
        }
        duo_flat_place()
            translate([0, DUO_FLAT_KEY_Y, 0]) {
                translate([0, 0, -40])
                    cylinder(h = 40 + KEY_H + 1, d = M3_D);
                translate([0, 0, -40])
                    rotate([0, 0, 90])
                        cylinder(h = 40 - 3, r = nut_r(), $fn = 6);
            }
        shoe_end_clear();
        duo_flat_place() upright_back_clear();
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
        shoe_end_clear();
    }
}

// -----------------------------------------------------------------------------
module assembly() {
    color("DimGray") pm17_shoe();
    color("SlateGray") pm17_place() pm17_cradle();
    if ($preview)
        color("Black", 0.4) pm17_place()
            translate([0, 0, pm_pad_top() + PM_T / 2])
                cube([PM_LEN, PM_W, PM_T], center = true);
    translate([0, -150, 0]) {
        color("DimGray") pm17_ms_shoe();
        color("SlateGray") pm17_ms_place() pm17_ms_cradle();
    }
    translate([0, 160, 0]) {
        color("DimGray") duo_shoe();
        translate([-duo_key_xy()[0], -duo_key_xy()[1], plat_z1() + DUO_PAD])
            color("SlateGray") duo_tray(DUO_CASED, "duo_tray_cased");
    }
    translate([220, 0, 0]) {
        color("DimGray") duo_flat_shoe();
        color("SlateGray") duo_flat_place() duo_flat_cradle();
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
else if (PART == "duo_flat_cradle") duo_flat_cradle();
else if (PART == "duo_flat_shoe") duo_flat_shoe();
