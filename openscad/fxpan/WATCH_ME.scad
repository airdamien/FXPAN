// =============================================================================
// fxpan/WATCH_ME.scad — FXPAN 65: clean-sheet FX panoramic body
// =============================================================================
// Two D800 behind one EL-Nikkor 180/5.6N and a 75×75×1 50/50 plate.
// 64.80 × 23.9 mm stitch, 2.711:1 (XPan is 2.708:1), 13248 × 4912 = 65.1 MP.
// The chamber is deliberately NOT a cube. BOX_Z carries BS_H. The flange
// register is 158.5 mm, not the 180 mm focal length: the lens nut is recessed
// into the wall and the camera cookies sit CAM_RECESS deeper. Read params.scad.
//
// Lens −Y. Plate at the origin, 45°, S1 (the 50/50 coating) toward the lens.
// Reflect leg → +X (camera R), transmit leg → +Y (camera T). Both bores are
// translated by sensor_shift() in opposite senses; no tube toe, no Scheimpflug.
// Three ports are blind rebates closed all round, so the chassis keeps an
// unbroken top rim and the lid sits flush on it.
//
// This body does not share parts with hybrid_shift. Every STL is stamped
// fxp_* and the bore is wider (TUBE_ID 46 / F_BORE 44.0 vs 52 / 40.3) so the
// 14.4 mm shift does not clip. Open this file and read the echo() lines.
// =============================================================================

/* [Part] */
PART = "assembly"; // [assembly:Assembly, isco:ISCO on the 180, isco_cut:ISCO section, chassis:Chassis, stem:Stem EL 180 helicoid, stem_el180_inf:Stem EL 180 infinity, arm_r:Arm R, arm_t:Arm T, arm_r_f:Arm R printed F, arm_t_f:Arm T printed F, arm_r_h:Arm R helicoid, arm_t_h:Arm T helicoid, fmount_h_r:F mount on helicoid R, fmount_h_t:F mount on helicoid T, cam_helicoid:Camera helicoid, lid:Lid, display_mount:Display mount, fxp_tray:Plate cartridge, base:Base, cradle_r:Cradle R, cradle_t:Cradle T, baffle:Baffles, ringgauge:M52 ring gauge, shims:Shims, el180_adapter:EL 180 adapter]

include <params.scad>
include <../lib/threads.scad>
include <../lib/part_stamp.scad>
include <fxp_f_mount.scad>
use <fxp_tray.scad>
use <shims.scad>
use <../camera_body.scad>
use <../monitor/display_mount.scad>
use <../monitor/monitor.scad>
include <../isco/el_nikkor_180n.scad>
include <../isco/isco_ultrastar_attachment.scad>
include <../isco/isco_mount.scad>

/* [View] */
SHOW_LID = 1; // [0:hide, 1:show]
SHOW_PANELS = 1; // [0:hide, 1:show]
SHOW_MONITOR = 0; // [0:hide, 1:show]
SHOW_PI = 0; // [0:hide, 1:show]
SHOW_BODIES = 0; // [0:hide, 1:D800]
SHOW_LENS = 0; // [0:hide, 1:show]
SHOW_LENS_MARKS = 0; // [0:hide, 1:pupils and focal plane]
SHOW_BASE = 1; // [0:hide, 1:show]
SHOW_AXES = 1; // [0:hide, 1:show]

/* [Camera] */
D800_AXIS_BASE    = 52.0; // mm, lens axis above the body's own baseplate
D800_TRIPOD_IN    = 44;   // mm, lens axis → tripod along the base
// How far the front of the body reaches past its own F flange. This sets
// the arm tube length and therefore the chassis size — see params.scad.
D800_PROUD        = 13.0; // [8:0.5:24]

/* [Body Alignment] */
// Ghost offsets in each arm's local frame, for eyeballing clearances.
BODY_R_X = 10; // [-20:0.5:20]
BODY_R_Y = 13; // [-20:0.5:20]
BODY_R_Z = -5; // [-20:0.5:20]
BODY_T_X = -13; // [-20:0.5:20]
BODY_T_Y = 10; // [-20:0.5:20]
BODY_T_Z = -5; // [-20:0.5:20]

/* [Shell] */
SHELL = "full"; // [full:Full (one material), inner:Inner PETG, outer:Outer PCTG, logo:Logo inlay]
// Fills the wall pockets in the preview. The chassis STL stays pocketed;
// each colour is still its own STL (chassis_logo_*).
LOGO_LAYER = "all"; // [all:All, fx:Gold FX, word:PAN, outline:Red outline, mp:65MP, rule:Hairline, spec:Native, ana_mp:130MP, ana_rule:Ana hairline, ana:Anamorphic, stripe:Red line]

/* [Mount] */
ARM_MOUNT = 0; // [0:reverse ring, 1:printed F, 2:helicoid F]
F_MOUNT_CLOCK = 0;
STEM = 1; // [0:EL 180 helicoid, 1:EL 180 infinity]
EL180_M62_PITCH = 1.0; // [0.75, 1.0]

/* [Optics check] */
// Drives the baffle apertures and the preview envelope. f/11 is the default
// because the 44 mm F throat only passes the frame corners from f/8.4, so
// baffles cut for f/5.6 would be no baffles at all. Set it to 5.6 to see how
// much the corners lose wide open.
FSTOP = 11; // [5.6, 8, 11, 16, 22]

screw_resolution = $preview ? 0.6 : 0.25;
ex = EXPLODED ? 55 : 0;

// -----------------------------------------------------------------------------
// tags — every part in this body is fxp_*
// -----------------------------------------------------------------------------
function fxp_tag(name) = str("fxp_", name);
function fxp_arm_tag(mark) =
    str("fxp_arm_", mark == "T" ? "t" : "r", printed_f() ? "f" : "");

function printed_f() =
    (ARM_MOUNT == 1) || PART == "arm_r_f" || PART == "arm_t_f";
function heli_cam() =
    ARM_MOUNT == 2 || PART == "arm_r_h" || PART == "arm_t_h"
    || PART == "fmount_h_r" || PART == "fmount_h_t";
// Infinity register in the arm's own frame (cookie back at z = 0). Same
// station as the fixed arms. T is shorter by the glass path.
function cam_heli_register_z(mark) =
    patch_t() + mount_standoff() + CAM_RECESS
    - (mark == "T" ? bs_t_comp() : 0);
// Shoulder the male bottoms on. The mesh register is F_FMOUNT_STACK
// further out.
function cam_heli_face_z() = patch_t() + cam_face_cap();
// Floor of the recess. The bought male bottoms here.
function cam_heli_seat_z() = cam_heli_face_z() - CAM_HELI_RECESS;
// Front face of the helicoid, collapsed. The printed mount's shoulder
// lands on it. T's mount is shorter; the helicoid itself is the same.
function cam_heli_front_z() = cam_heli_seat_z() + cam_heli_proud();
function cam_heli_shoulder(mark) =
    cam_heli_register_z(mark) - F_FMOUNT_STACK - cam_heli_front_z();
function inf_stem() =
    STEM || PART == "stem_el180_inf";
function show_isco() = PART == "isco" || PART == "isco_cut";
function mount_stack() = printed_f() ? F_FMOUNT_STACK : F_REV_STACK;
// Narrowest thing in the light path at the flange. The metal reverse ring
// keeps the real 44 mm F throat; the printed bayonet lip is F_STL_THROAT.
function mouth_clear() = printed_f() ? F_STL_THROAT : F_THROAT;
// Widest aperture that puts the whole frame, corners included, through that
// mouth. need_bore() falls as you stop down, so bisect for where it crosses.
// It does not fall to zero: at f/inf the field term alone remains, so a mouth
// narrower than that never passes the corners. The old 38 mm scan was one.
function bore_floor() = need_bore(1e6, FLANGE_F);
function mouth_ever_clean() = mouth_clear() > bore_floor();
function _mouth_fstop(lo, hi, i) =
    i <= 0 ? hi
    : let (m = (lo + hi) / 2)
        need_bore(m, FLANGE_F) > mouth_clear()
            ? _mouth_fstop(m, hi, i - 1)
            : _mouth_fstop(lo, m, i - 1);
function mouth_fstop() = _mouth_fstop(1, 64, 40);

// Arm tube past the cookie. Both mouths put their F register at the same
// station, so the printed F (a 3 mm stack) needs a longer tube than the
// reverse ring (8 mm). CAM_RECESS moves the whole arm in; it does not
// shorten the tube, because the tube is the M52 thread.
function reflect_tube_len()  =
    ARM_TUBE + F_REV_STACK - mount_stack();
// The transmit leg crosses 1 mm of glass at 45°, which pushes its focus
// back by bs_t_comp(). Shorten the tube by the same amount.
function transmit_tube_len() = reflect_tube_len() - bs_t_comp();
function patch_t()           = PORT_PATCH_T;

module mm_split() {
    if (SHELL == "inner")
        intersection() { children(0); children(1); }
    else if (SHELL == "outer")
        difference() { children(0); children(1); }
    else
        children(0);
}

// -----------------------------------------------------------------------------
// port frame — cookie drops into a blind rebate, held by four countersunk M3s
// -----------------------------------------------------------------------------
module round_rect(w, h, r) {
    offset(r)
        offset(-r)
            square([w, h], center = true);
}

// Skin is the 4 mm shell. Camera cookies are faced out to it. The infinity
// cookie's rim is too; the lens sits in a step down to the 158.5 seat.
function skin_z() = patch_t();
function cam_face_cap() = skin_z() - patch_t() + CAM_RECESS;
function chassis_shell_t() = skin_z();
function chassis_out()     = BOX_XY + 2 * chassis_shell_t();
// The chamber is only as tall as the plate; the skirt under it is what puts
// the optical axis where the cameras have to stand.
function chassis_out_z()   = BOX_Z + chassis_plinth();

// Cookie outline: a rectangle on camera-up, centred on the bore rather than
// on the face, sized by port_patch_u() and port_patch_v() off the features it
// actually has to carry.
// Square, and wide enough that the infinity step has a land outside the Ø76.
function stem_plate_w() =
    max(port_patch_u(), port_patch_v(""), EL180_LENS_OD + 4);

module port_plate_2d(mark = "", grow = 0) {
    ax = cam_axis(mark);
    w = mark == "" ? stem_plate_w() : port_patch_u();
    h = mark == "" ? stem_plate_w() : port_patch_v(mark);
    translate([ax.x, ax.y])
        rotate([0, 0, port_up_az(mark)])
            round_rect(w + 2 * grow, h + 2 * grow,
                       max(0.4, PORT_PLATE_R + grow));
}

// A cookie is a panel of the body, so it stops where the body's skin does.
// Past the flat part of a face the chassis curves away under it, and without
// this the plate carries straight on into the air over the corner. Clipping
// to the same profile the chassis is extruded from contours the outer face
// down onto it; the bed face is untouched, which is what the part is printed
// on. PORT_BOSS_R is chosen so the whole of this lands inside PORT_EDGE_CHAM.
module port_chassis_clip(mark = "") {
    u   = port_up(mark);
    out = chassis_out();
    // Camera-up is vertical on every face, so the chassis's rounding — which
    // is all in plan — is always across the plate, never along it.
    // The clip ends on the skin for a part that sits on the box face. Camera
    // cookies are placed CAM_RECESS inboard, and the face cap has to reach
    // back out to the skin from that frame — without the lift the cap is
    // trimmed off and the plate sits in the rebate.
    rot = abs(u.x) > 0.5 ? [0, 90, 0] : [-90, 0, 0];
    lift = mark == "" ? 0 : cam_face_cap();
    translate([0, 0, -BOX_XY / 2 + lift])
        rotate(rot)
            linear_extrude(height = 4 * out, center = true)
                round_rect(out, out, PORT_BOSS_R);
}

// Chamfered on the outer face only. The stem prints this face up, so the
// chamfer only narrows the last layers and the bed face stays the full plate.
module port_flange(mark = "") {
    c = min(PORT_EDGE_CHAM, patch_t() - 1.5);
    intersection() {
        hull() {
            linear_extrude(patch_t() - c)
                port_plate_2d(mark, 0);
            linear_extrude(patch_t())
                port_plate_2d(mark, -c);
        }
        port_chassis_clip(mark);
    }
}

// Camera cookie. Straight through, same outline on both faces, so the edge
// is a vertical wall and sits flat on the bed. Following the chassis corner
// back through the thickness left a slope there, and that slope is a ledge
// once the flange is the bed face.
module cam_cookie(mark) {
    // Straight wall, but the shifted edge runs past the chassis corner and
    // sits proud of it. Clip that edge to the skin; the other three stay.
    intersection() {
        linear_extrude(patch_t() + cam_face_cap())
            port_plate_2d(mark);
        port_chassis_clip(mark);
    }
}

// Camera-up chord at the F mouth so the pentaprism nose clears the OD. It
// rakes back to the full OD at the cookie's outer face and stops dead there:
// below that line the cookie IS the outside of the body. The taper used to be
// specified as a length from the mouth, TUBE_FLASH_L = 11 mm, which on an
// 8 mm tube ran straight past the cookie face and bit a 16 mm notch out of
// the plate — the L.
TUBE_FLASH_KEEP = 27.0;

module tube_flash_waste(mark, out_len) {
    n  = port_up(mark);
    ax = cam_axis(mark);
    z_face = patch_t() + (mark == "" ? 0 : cam_face_cap());
    z1 = z_face + out_len;
    w  = 80;
    if (mark == "R" || mark == "T")
        hull() {
            translate([ax.x + n.x * (TUBE_FLASH_KEEP + w / 2),
                       ax.y + n.y * (TUBE_FLASH_KEEP + w / 2), z1 + 8])
                cube([w, w, 16], center = true);
            translate([ax.x + n.x * (TUBE_OD / 2 + w / 2),
                       ax.y + n.y * (TUBE_OD / 2 + w / 2),
                       z_face + 0.5])
                cube([w, w, 1], center = true);
        }
}

// Four M3s, two each side of the bore, tracking cam_axis, so the cookie can
// be screwed down after it has dropped into its rebate.
module port_clamp_screws(mark = "") {
    for (up = [-1, 1], side = [-1, 1]) {
        p = clamp_xy(mark, side, up);
        translate([p.x, p.y, 0])
            children();
    }
}

// Flat-head M3, flush with the cookie face. Cut in the cookie, not the box.
module port_csk_cut() {
    translate([0, 0, -1])
        cylinder(h = patch_t() + 2, d = PORT_SCREW_D);
    translate([0, 0, patch_t() - PORT_CSK_H])
        cylinder(h = PORT_CSK_H, d1 = PORT_SCREW_D, d2 = PORT_CSK_D);
    translate([0, 0, patch_t() - 0.01])
        cylinder(h = 0.8, d = PORT_CSK_D);
}

// Tapped into the chamber wall behind the cookie, nut trapped on the inside.
module port_clamp_anchor_cut() {
    translate([0, 0, -WALL - 0.2])
        cylinder(h = WALL + 0.6, d = PORT_SCREW_D);
    translate([0, 0, -WALL - 0.05])
        hex_nut_cut();
}

// Cookie pocket. Closed on all four sides — this is the lid overhang.
//
// The pocket used to sweep open toward the lid, because a cookie used to slide
// in behind a retaining wall. That wall is gone, the plate's outer face is the
// outside of the body, and it goes in from outside; but the channel stayed,
// running the full 4.35 mm deep straight out through the top of the chassis.
// So the chassis's top rim was cut away over 90 of its 100 mm on both camera
// faces and the lid sat over the hole, proud of nothing, on two sides.
//
// Closing it also captures the cookie on four sides instead of three. The
// ceiling is a 4.35 mm ledge off the wall behind it, tied at both ends and
// facing into a pocket a plate then fills — droop there costs nothing.
module port_slide_slot(mark = "", extra = 0) {
    d = patch_t() + 0.35 + extra;
    // extra deepens the floor. The mouth stays at the skin.
    translate([0, 0, d / 2 - 0.2 - extra])
        linear_extrude(d, center = true)
            port_plate_2d(mark, PORT_SLOT_CLEAR / 2);
}

// 3 mm ring into the chassis top shelf. It used to be notched out over each
// port face to let a cookie slide past; nothing passes here now.
module lid_align_lip() {
    s = BOX_XY;
    difference() {
        cube([s - WALL - 2 * LID_GAP,
              s - WALL - 2 * LID_GAP,
              LID_LIP], center = true);
        cube([s - 2 * WALL - 0.6,
              s - 2 * WALL - 0.6,
              LID_LIP + 0.4], center = true);
    }
}

// -----------------------------------------------------------------------------
// port placement
// -----------------------------------------------------------------------------
module at_stem_face() {
    translate([0, -BOX_XY / 2, 0])
        rotate([90, 0, 0])
            children();
}
module at_reflect_face() {
    translate([BOX_XY / 2, 0, 0])
        rotate([0, 90, 0])
            children();
}
module at_transmit_face() {
    translate([0, BOX_XY / 2, 0])
        rotate([-90, 0, 0])
            children();
}
module at_stem()     { at_stem_face()     children(); }
module at_reflect()  { at_reflect_face()  children(); }
module at_transmit() { at_transmit_face() children(); }

module at_each_bore() {
    at_stem_face() children();
    at_reflect_face()
        translate([cam_axis("R").x, cam_axis("R").y, 0])
            children();
    at_transmit_face()
        translate([cam_axis("T").x, cam_axis("T").y, 0])
            children();
}

// -----------------------------------------------------------------------------
// chassis
// -----------------------------------------------------------------------------
module box_bore() {
    s = BOX_XY;
    h = BOX_Z;

    translate([0, 0, WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, h - WALL], center = true);

    translate([0, 0, h / 2 - WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, WALL + 0.2], center = true);

    translate([0, 0, h / 2 - LID_LIP / 2])
        cube([s - WALL, s - WALL, LID_LIP + 0.1], center = true);

    translate([0, 0, -h / 2 - chassis_plinth() - 0.05]) {
        cylinder(h = tripod_hole_h() + 0.1, d = TRIPOD_INSERT_D);
        cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
    }

    // Optical hole. The helicoid's M42 male (42 mm) passes this; the
    // cookie covers it. Fixed-arm tubes are smaller and still land.
    at_reflect_face()
        translate([cam_axis("R").x, cam_axis("R").y, -WALL / 2])
            cylinder(h = WALL + 2, d = TUBE_ID + 1, center = true);
    at_transmit_face()
        translate([cam_axis("T").x, cam_axis("T").y, -WALL / 2])
            cylinder(h = WALL + 2, d = TUBE_ID + 1, center = true);
    // Big enough for the helicoid nut. The infinity stem stops at this
    // hole; only the lens barrel passes into the chamber.
    at_stem_face()
        translate([0, 0, -WALL / 2])
            cylinder(h = WALL + 2, d = HELI_NUT_OD + 0.8, center = true);
}

// M3 hex in each top corner, fed from a side slot. Roof stays solid so the
// lid screw can clamp.
module lid_body_fastener_cuts() {
    s = BOX_XY;
    nut_z = BOX_Z / 2 - LID_NUT_DROP;
    module nut_hex() {
        rotate([0, 0, 30])
            cylinder(h = PORT_NUT_T + 0.25,
                     d = PORT_NUT_AF / cos(30), $fn = 6, center = true);
    }
    for (sx = [-1, 1], sy = [-1, 1]) {
        px = sx * (s / 2 - LID_SCREW);
        py = sy * (s / 2 - LID_SCREW);
        translate([px, py, nut_z - 4])
            cylinder(h = BOX_Z / 2 - nut_z + 5, d = PORT_SCREW_D);
        hull() {
            translate([px, py, nut_z])
                nut_hex();
            translate([sx * (s / 2 - WALL - 2.5),
                       sy * (s / 2 - WALL - 2.5), nut_z])
                nut_hex();
        }
    }
}

module hex_nut_cut() {
    cylinder(h = PORT_NUT_T + 0.2, d = PORT_NUT_AF / cos(30), $fn = 6);
}

module port_letter_2d(kind) {
    module stamp(letter) {
        translate([-4.6, 0])
            polygon([[0, 2.6], [-1.7, -1.4], [1.7, -1.4]]);
        translate([3.2, 0])
            text(letter, size = 5.2, font = "Liberation Sans:style=Bold",
                 halign = "center", valign = "center");
        translate([3.2, -5.6])
            text("FXP", size = 3.0, font = "Liberation Sans:style=Bold",
                 halign = "center", valign = "center");
    }
    if (kind == "R")
        rotate(90)  stamp("R");
    else
        rotate(180) stamp("T");
}

// Part tag, along the plate edge opposite the lid. That is the one edge with
// nothing on it: the tube fills the middle out to TUBE_OD/2, the clamp screws
// sit on the two edges across camera-up, flange_marks owns camera-up itself,
// and the lock lugs come down either side of this edge without reaching it.
module fxp_port_stamp(name, mark = "") {
    e = port_patch_u() / 2 - PORT_EDGE_CHAM - 2.8;
    a = port_up_az(mark) + 180;
    ax = cam_axis(mark);
    translate([ax.x + e * cos(a), ax.y + e * sin(a), patch_t() - STAMP_DEPTH])
        rotate([0, 0, a + 90])
            linear_extrude(STAMP_DEPTH + 0.15)
                part_stamp_2d(name, 3.4);
}

module flange_marks(kind) {
    t = 0.8;
    ax = cam_axis(kind);
    u  = port_up(kind);
    translate([ax.x + u.x * port_clamp_r(),
               ax.y + u.y * port_clamp_r(),
               patch_t() - t])
        linear_extrude(t + 0.15)
            port_letter_2d(kind);
}

module chassis_port_mark(kind) {
    t = 0.8;
    ax = cam_axis(kind);
    u  = port_up(kind);
    translate([ax.x + u.x * port_clamp_r(),
               ax.y + u.y * port_clamp_r(), -t])
        linear_extrude(t + 0.15)
            port_letter_2d(kind);
}

module box_fastener_cuts() {
    lid_body_fastener_cuts();
    at_stem_face() {
        port_slide_slot("", stem_drop());
        port_clamp_screws("") port_clamp_anchor_cut();
    }
    at_reflect_face() {
        port_slide_slot("R", CAM_RECESS);
        port_clamp_screws("R") port_clamp_anchor_cut();
        chassis_port_mark("R");
    }
    at_transmit_face() {
        port_slide_slot("T", CAM_RECESS);
        port_clamp_screws("T") port_clamp_anchor_cut();
        chassis_port_mark("T");
    }
}

module box_lining_mask() {
    s = BOX_XY;
    h = BOX_Z;
    L = INNER_LINING;
    difference() {
        translate([0, 0, (WALL - L) / 2])
            cube([s - 2 * (WALL - L),
                  s - 2 * (WALL - L),
                  h - (WALL - L)], center = true);
        translate([0, 0, WALL / 2])
            cube([s - 2 * WALL, s - 2 * WALL, h - WALL + 0.4], center = true);
    }
    translate([0, 0, -h / 2 + WALL - FLOOR_SKIN - (L - FLOOR_SKIN) / 2])
        cube([s - 2 * WALL + 2 * L,
              s - 2 * WALL + 2 * L,
              L - FLOOR_SKIN], center = true);
    module bore_liner(d) {
        translate([0, 0, -WALL / 2])
            difference() {
                cylinder(h = WALL + 0.4, d = d + 2 * L, center = true);
                cylinder(h = WALL + 0.8, d = d, center = true);
            }
    }
    at_reflect_face()
        translate([cam_axis("R").x, cam_axis("R").y, 0])
            bore_liner(TUBE_ID + 1);
    at_transmit_face()
        translate([cam_axis("T").x, cam_axis("T").y, 0])
            bore_liner(TUBE_ID + 1);
    at_stem_face()
        bore_liner(HELI_NUT_OD + 0.8);
}

// -----------------------------------------------------------------------------
// FXPAN wall badge — colour-separated STLs from logos/fxpan_gen.py (gold FX
// + sweep, white PAN, red outline) then 65MP over the native stitch and
// 130MP over the 2× anamorphic delivery. The mark is projected to 2D so the
// existing offset / extrude plug fit still applies. Spec type is Futura,
// which ships with macOS — re-exporting on Linux needs the same family.
// layer: all | fx | word | outline | mp | rule | spec | ana_mp | ana_rule |
//        ana | stripe.
// -----------------------------------------------------------------------------
// Native bounding box of logos/fxpan_outline_red.stl. Gold and PAN share
// that origin, so one translate keeps the three layers registered.
LOGO_ART_FILE = "../../logos";
LOGO_ART_X0   = -1.200;
LOGO_ART_Y0   = -3.963;
LOGO_ART_W    = 143.367;
LOGO_ART_H    = 74.771;

function fx_word_y()      = 9.05;   // mark centre on the wall
function logo_art_scale() = SPEC_W / LOGO_ART_W;
function logo_art_h()     = LOGO_ART_H * logo_art_scale();
function logo_art_bottom()= fx_word_y() - logo_art_h() / 2;
function fx_mp_y()        = logo_art_bottom() - 7.2;
function fx_rule_y()      = fx_mp_y() - 4.8;
function fx_spec_y()      = fx_mp_y() - 9.2;
function fx_ana_mp_y()    = fx_mp_y() - 19.1;
function fx_ana_rule_y()  = fx_mp_y() - 23.9;
function fx_ana_y()       = fx_mp_y() - 28.3;

module fxpan_art_stl(name) {
    translate([0, fx_word_y()])
        scale(logo_art_scale())
            translate([-LOGO_ART_X0 - LOGO_ART_W / 2,
                       -LOGO_ART_Y0 - LOGO_ART_H / 2])
                projection(cut = false)
                    import(str(LOGO_ART_FILE, "/", name), convexity = 12);
}

module fxpan_badge() {
    fxpan_art_stl("fxpan_fx_gold.stl");
}

module fxpan_pan() {
    fxpan_art_stl("fxpan_pan_white.stl");
}

module fxpan_outline() {
    fxpan_art_stl("fxpan_outline_red.stl");
}

// Spec lines share columns measured off the native string in Futura
// Condensed Medium 5 / spacing 1.08, so the middot and the aspect sit
// on the same x whether the label is NATIVE or ANA 2×. Advances are
// baked (textmetrics is still experimental in the GUI).
SPEC_SIZE   = 5.0;
SPEC_SP     = 1.08;
SPEC_W      = 71.9167;   // NATIVE  13248×4912  ·  2.71:1
SPEC_X_LAB  = 16.1316;   // NATIVE
SPEC_X_PIX  = 19.2371;   // NATIVE<two spaces>
SPEC_X_DOT  = 51.9106;   // …4912<two spaces>, left of ·
SPEC_X_AR   = 56.5687;   // …  ·<two spaces>

module fxpan_spec_line(label, pix, ar) {
    specf = "Futura:style=Condensed Medium";
    x0 = -SPEC_W / 2;
    translate([x0 + SPEC_X_LAB, 0])
        text(label, size = SPEC_SIZE, font = specf, spacing = SPEC_SP,
             halign = "right", valign = "center");
    translate([x0 + SPEC_X_PIX, 0])
        text(pix, size = SPEC_SIZE, font = specf, spacing = SPEC_SP,
             halign = "left", valign = "center");
    translate([x0 + SPEC_X_DOT, 0])
        text("·", size = SPEC_SIZE, font = specf, spacing = SPEC_SP,
             halign = "left", valign = "center");
    translate([x0 + SPEC_X_AR, 0])
        text(ar, size = SPEC_SIZE, font = specf, spacing = SPEC_SP,
             halign = "left", valign = "center");
}

module fxpan_mp_mark(s) {
    text(s, size = 6.2, font = "Futura:style=Bold", spacing = 1.12,
         halign = "center", valign = "center");
}

module fxpan_rule() {
    square([SPEC_W, 0.45], center = true);
}

module fxpan_wall_2d(layer = "all") {
    if (layer == "all" || layer == "fx")
        fxpan_badge();
    if (layer == "all" || layer == "word")
        fxpan_pan();
    if (layer == "all" || layer == "outline")
        fxpan_outline();
    if (layer == "all" || layer == "mp")
        translate([0, fx_mp_y()])
            fxpan_mp_mark("65MP");
    if (layer == "all" || layer == "rule")
        translate([0, fx_rule_y()])
            fxpan_rule();
    if (layer == "all" || layer == "spec")
        translate([0, fx_spec_y()])
            fxpan_spec_line("NATIVE", "13248×4912", "2.71:1");
    if (layer == "all" || layer == "ana_mp")
        translate([0, fx_ana_mp_y()])
            fxpan_mp_mark("130MP");
    if (layer == "all" || layer == "ana_rule")
        translate([0, fx_ana_rule_y()])
            fxpan_rule();
    if (layer == "all" || layer == "ana")
        translate([0, fx_ana_y()])
            fxpan_spec_line("ANA 2×", "26496×4912", "5.42:1");
}

// grow  — swell the footprint and deepen the floor (plug interference)
// proud — start this far outside the wall face
// deep  — depth below the wall face, so the pocket keeps its own depth
//         whatever the plugs do
module fxpan_inlay(layer = "all", grow = 0, proud = 0.05,
                   deep = MARK_DEPTH + 0.10) {
    out = chassis_out();
    translate([-out / 2 - proud, 0, 2])
        rotate([90, 0, -90])
            mirror([0, 0, 1])
                linear_extrude(proud + deep + grow)
                    offset(0.02 + grow)
                        scale(LOGO_SCALE)
                            fxpan_wall_2d(layer);
}

// Groove around the plinth, a few millimetres above the floor so the first
// layers stay solid and the cookies (centred on the axis) never reach it.
// proud is an outward offset — the ring has no single face-normal to
// translate along the way the −X badge does.
function stripe_z0() = -BOX_Z / 2 - chassis_plinth() + STRIPE_LIFT;

module fxpan_stripe(grow = 0, proud = 0.05, deep = MARK_DEPTH + 0.10) {
    out = chassis_out();
    translate([0, 0, stripe_z0() - grow])
        linear_extrude(STRIPE_H + 2 * grow)
            difference() {
                offset(0.02 + grow + proud)
                    round_rect(out, out, PORT_BOSS_R);
                offset(-(deep + grow))
                    round_rect(out, out, PORT_BOSS_R);
            }
}

module fxpan_colour(layer = "all", grow = 0, proud = 0.05,
                    deep = MARK_DEPTH + 0.10) {
    if (layer != "stripe")
        fxpan_inlay(layer, grow, proud, deep);
    if (layer == "all" || layer == "stripe")
        fxpan_stripe(grow, proud, deep);
}

module chassis_blank() {
    dz  = chassis_plinth();
    h   = BOX_Z + dz;
    out = chassis_out();
    translate([0, 0, -BOX_Z / 2 - dz])
        linear_extrude(h)
            round_rect(out, out, PORT_BOSS_R);
}

// One colour, clipped to the chassis so a glyph cannot cross a bore.
// The proud lip is the part that stands off the wall face.
module logo_plug(layer) {
    union() {
        intersection() {
            difference() {
                chassis_blank();
                box_bore();
                box_fastener_cuts();
            }
            fxpan_colour(layer, LOGO_FIT, 0);
        }
        fxpan_colour(layer, LOGO_FIT, LOGO_PROUD, 0.4);
    }
}

module logo_fills() {
    // Same plugs the colour STLs export, drawn into the pockets. No second
    // chassis boolean — the pocket cut already made the seat.
    module one(layer, c) {
        if (LOGO_LAYER == "all" || LOGO_LAYER == layer)
            color(c) {
                fxpan_colour(layer, LOGO_FIT, 0);
                fxpan_colour(layer, LOGO_FIT, LOGO_PROUD, 0.4);
            }
    }
    one("fx", "Gold");
    one("word", "White");
    one("outline", "Crimson");
    one("mp", "White");
    one("rule", "Crimson");
    one("spec", "White");
    one("ana_mp", "White");
    one("ana_rule", "Crimson");
    one("ana", "White");
    one("stripe", "Crimson");
}

module chassis_body() {
    color("SlateGray")
    mm_split() {
        difference() {
            chassis_blank();
            box_bore();
            box_fastener_cuts();
            // box_floor_stamp is written for a cube; feed it the XY size and
            // drop it to the real floor, which is BOX_Z deep.
            translate([0, 0, -(BOX_Z - BOX_XY) / 2])
                box_floor_stamp(fxp_tag("chassis"), BOX_XY, WALL);
            if (SHELL == "full" || SHELL == "logo")
                fxpan_colour("all");
        }
        union() {
            box_lining_mask();
            if (SHELL == "outer")
                fxpan_colour("all");
        }
    }
}

module part_chassis() {
    // Full / inner / outer always pocket every layer so the colour STLs seat.
    // SHELL=logo exports one LOGO_LAYER as a drop-in. The assembly preview
    // draws those plugs back into the pockets; see logo_fills().
    if (SHELL == "logo")
        color("SlateGray") logo_plug(LOGO_LAYER);
    else
        chassis_body();
}

// -----------------------------------------------------------------------------
// tubes
// -----------------------------------------------------------------------------
module along_tube(rx = 0, ry = 0) {
    translate([0, 0, patch_t()])
        rotate([rx, ry, 0])
            children();
}

module along_cam(rx = 0, ry = 0, mark = "") {
    ax = cam_axis(mark);
    translate([ax.x, ax.y, 0])
        along_tube(rx, ry)
            children();
}

// Ring baffle. ID follows need_bore() at this station so the tooth never
// shadows the shifted bundle at FSTOP.
function baffle_id(mark, out_len, z) =
    let (b = d_plate_to_mount() - (out_len - z))
        min(TUBE_ID - 1.0, max(F_BORE - 2, need_bore(FSTOP, b + FLANGE_F) + 1.0));

module tube_baffle_tooth(id) {
    rotate_extrude()
        polygon([
            [id / 2,           0],
            [TUBE_ID / 2 - 0.02, 0],
            [TUBE_ID / 2 - 0.02, BAFFLE_H],
            [id / 2,           BAFFLE_H]
        ]);
}

module tube_baffles(out_len, mark = "") {
    z0 = 8;
    z1 = out_len - (printed_f() ? F_PEG_H + MASK_T + 1.2 : F_REV_LEN + 1.2);
    if (z1 > z0 + BAFFLE_H)
        for (z = [z0 : BAFFLE_PITCH : z1 - BAFFLE_H])
            translate([0, 0, z])
                difference() {
                    cylinder(h = BAFFLE_H, d = TUBE_ID - 0.02);
                    translate([0, 0, -0.1])
                        cylinder(h = BAFFLE_H + 0.2,
                                 d1 = baffle_id(mark, out_len, z),
                                 d2 = TUBE_ID - 0.02);
                }
}

// Glare stop in the F throat. The window has to pass the whole shifted
// bundle, so it is set from the sensor plus MASK_CLEAR, not from F_BORE.
module f_glare_mask(out_len, mark) {
    roll = mark == "T" ? 180 : 90;
    z = printed_f() ? out_len - F_PEG_H - MASK_T : out_len - F_REV_LEN - MASK_T;
    od = TUBE_ID + 0.6;
    translate([0, 0, z])
        difference() {
            cylinder(h = MASK_T, d = od);
            translate([0, 0, -0.2])
                linear_extrude(MASK_T + 0.4)
                    rotate([0, 0, roll])
                        offset(r = 2)
                            offset(delta = -2)
                                square([SENSOR_W + 2 * MASK_CLEAR,
                                        SENSOR_H + 2 * MASK_CLEAR],
                                       center = true);
        }
}

module tube_lining_mask(out_len, rx = 0, ry = 0, mark = "", m62 = 0) {
    L = INNER_LINING;
    ax = cam_axis(mark);
    h = patch_t() + out_len + 0.2;
    translate([ax.x, ax.y, -0.2])
        rotate([rx, ry, 0])
            difference() {
                cylinder(h = h, d = TUBE_ID + 2 * L);
                translate([0, 0, -0.4])
                    cylinder(h = h + 0.8, d = TUBE_ID - 0.4);
            }
    // Inner PETG owns threaded zones; the PCTG outer is nut-seat meat only.
    if (m62 > 0)
        translate([ax.x, ax.y, patch_t() + out_len - 0.2])
            cylinder(h = m62 + 0.4, d = EL180_M62_MAJOR + 2 * L);
    if (!printed_f() && mark != "")
        translate([ax.x, ax.y, patch_t() + out_len - F_REV_LEN - 0.2])
            cylinder(h = F_REV_LEN + 0.6, d = F_REV_MAJOR + 2 * L + 0.4);
    // No liner in the F throat: it is the tightest aperture in the body,
    // 1.3 mm clear of the frame corners even at f/11, so anything in there
    // would vignette outright. Flocking handles glare instead.
    if (mark != "")
        along_cam(rx, ry, mark) {
            tube_baffles(out_len, mark);
            f_glare_mask(out_len, mark);
        }
}

module port_tube_solid(out_len, rx = 0, ry = 0, mark = "") {
    ax = cam_axis(mark);
    difference() {
        union() {
            if (mark != "")
                cam_cookie(mark);
            else
                port_flange(mark);
            if (out_len > 0.05)
                along_cam(rx, ry, mark)
                    cylinder(h = out_len, d = TUBE_OD);
        }
        along_cam(rx, ry, mark)
            translate([0, 0, -patch_t() - 2])
                cylinder(h = patch_t() + out_len + 4, d = TUBE_ID);
        tube_flash_waste(mark, out_len);
        // Printed-F cookies are cam_face_cap thicker, and the inner edge is
        // a 45° face. The old cut started above the back and left a web.
        if (printed_f())
            port_clamp_screws(mark) cam_csk_cut();
        else
            translate([0, 0, mark == "" ? 0 : cam_face_cap()])
                port_clamp_screws(mark) port_csk_cut();
    }
}

// 45° face along the inner long edge, on the chassis side of the cookie.
// The outer face keeps the full outline. Lay this face on the bed.
module cookie_print_flat(mark) {
    H = patch_t() + cam_face_cap();
    ax = cam_axis(mark);
    half_v = port_patch_v(mark) / 2;
    span = port_patch_u() + 30;
    if (mark == "R") {
        translate([ax.x, ax.y + half_v, H])
            rotate([45, 0, 0])
                translate([-span / 2, -40, -40])
                    cube([span, 40, 40]);
    } else {
        translate([ax.x - half_v, ax.y, H])
            rotate([0, 45, 0])
                translate([0, -span / 2, -40])
                    cube([40, span, 40]);
    }
}

module part_camera_tube(out_len, rx = 0, ry = 0, mark = "") {
    p = max(port_patch_u(), port_patch_v(mark)) + 2 * sensor_shift();
    color("SlateGray")
    mm_split() {
    intersection() {
    difference() {
        union() {
            port_tube_solid(out_len, rx, ry, mark);
            along_cam(rx, ry, mark) {
                tube_baffles(out_len, mark);
                f_glare_mask(out_len, mark);
                if (!printed_f() && rev_lock_ok(out_len))
                    rev_lock_bosses(out_len, port_up_az(mark));
            }
        }
        if (!printed_f())
            along_cam(rx, ry, mark) {
                translate([0, 0, max(out_len - F_REV_LEN, -patch_t())])
                    f_rev_thread_cut();
                // Lead-in, so the ring can find the first turn square.
                translate([0, 0, out_len - F_REV_LEAD])
                    cylinder(h = F_REV_LEAD + 0.1,
                             d1 = f_rev_minor(),
                             d2 = f_rev_minor() + 2 * F_REV_LEAD);
                if (rev_lock_ok(out_len))
                    rev_lock_cuts(out_len, port_up_az(mark));
                f_pin_line_cut(out_len, port_up_az(mark));
            }
        translate([0, 0, cam_face_cap()]) {
            flange_marks(mark);
            fxp_port_stamp(fxp_arm_tag(mark), mark);
        }
        tube_flash_waste(mark, out_len);
        if (printed_f())
            cookie_print_flat(mark);
    }
        translate([-p, -p, 0])
            cube([p * 2, p * 2,
                  patch_t() + out_len + (printed_f() ? 16 : 8)]);
    }
        tube_lining_mask(out_len, rx, ry, mark);
    }
    if (SHELL != "inner") {
    if (printed_f())
        color("Goldenrod")
            difference() {
                along_cam(rx, ry, mark)
                    translate([0, 0, out_len])
                        f_mount_on_tube((mark == "T" ? 0 : -90) + F_MOUNT_CLOCK,
                                        peg_face = 0,
                                        back_extra = FX_FMOUNT_EXTRA);
                tube_flash_waste(mark, out_len);
            }
    else if ($preview && SHOW_BODIES == 0)
        color("Goldenrod", 0.55)
            along_cam(rx, ry, mark)
                translate([0, 0, out_len])
                    difference() {
                        cylinder(h = F_REV_STACK, d = 62);
                        translate([0, 0, -0.1])
                            cylinder(h = F_REV_STACK + 0.2, d = F_BORE);
                    }
    }
}

// -----------------------------------------------------------------------------
// helicoid camera arms. The cookie takes the M42 male of a bought
// M52-female / M42-male 17–31 mm helicoid. The printed mount is an M52
// male into that helicoid's front female.
// Collapsed is infinity. Extending moves the camera out. The tripod screw
// locks it; there is no set screw.
// -----------------------------------------------------------------------------
module cam_csk_cut() {
    h = patch_t() + cam_face_cap();
    translate([0, 0, -1])
        cylinder(h = h + 2, d = PORT_SCREW_D);
    translate([0, 0, h - PORT_CSK_H])
        cylinder(h = PORT_CSK_H + 0.4, d1 = PORT_SCREW_D, d2 = PORT_CSK_D);
}

module part_cam_heli_arm(mark) {
    ax = cam_axis(mark);
    z_seat = cam_heli_seat_z();
    color("SlateGray")
    mm_split() {
        ScrewHole(CAM_HELI_REAR, z_seat + 0.2,
                  position = [ax.x, ax.y, 0],
                  pitch = CAM_HELI_PITCH,
                  tolerance = CAM_HELI_TOL,
                  tooth_height = CAM_HELI_TOOTH)
            difference() {
                cam_cookie(mark);
                // Pocket the helicoid body. The male bottoms on the floor.
                // The thread itself is the bore; a clearance cylinder here
                // would wipe it out.
                translate([ax.x, ax.y, z_seat])
                    cylinder(h = cam_heli_face_z() - z_seat + 0.02,
                             d = CAM_HELI_OD + 0.8);
                port_clamp_screws(mark) cam_csk_cut();
                translate([0, 0, cam_face_cap()]) {
                    flange_marks(mark);
                    fxp_port_stamp(str("fxp_arm_", mark == "T" ? "t" : "r", "h"),
                                   mark);
                }
            }
        translate([ax.x, ax.y, -0.2])
            cylinder(h = z_seat + 0.5,
                     d = CAM_HELI_REAR + 2 * INNER_LINING + 1.2);
    }
}

// Bought helicoid, collapsed plus `lift`. Sits on the recess floor.
module cam_helicoid_body(lift = 0) {
    h = cam_heli_proud() + lift;
    color("Silver")
        difference() {
            union() {
                translate([0, 0, -CAM_HELI_MALE])
                    cylinder(h = CAM_HELI_MALE + 0.2, d = CAM_HELI_REAR - 1);
                cylinder(h = h, d = CAM_HELI_OD);
                translate([0, 0, h * 0.55])
                    difference() {
                        cylinder(h = 0.8, d = CAM_HELI_OD + 1.2);
                        translate([0, 0, -0.1])
                            cylinder(h = 1.0, d = CAM_HELI_OD - 3);
                    }
            }
            translate([0, 0, -0.2])
                cylinder(h = h + 0.4, d = CAM_HELI_ID);
            translate([0, 0, -CAM_HELI_MALE - 0.2])
                cylinder(h = CAM_HELI_MALE + 0.4, d = CAM_HELI_NECK);
        }
}

// Printed male into the helicoid's front female, then the bayonet.
// z = 0 at the thread tip. The shoulder flares out to the flange so the
// 62 mm disk is not a shelf.
module part_cam_heli_mount(mark) {
    clock = (mark == "T" ? 0 : -90) + F_MOUNT_CLOCK;
    shoulder = cam_heli_shoulder(mark);
    z_mesh = CAM_HELI_FRONT + shoulder;
    color("Goldenrod")
        union() {
            difference() {
                union() {
                    ScrewThread(CAM_HELI_NOSE, CAM_HELI_FRONT + 0.2,
                                pitch = CAM_HELI_PITCH,
                                tolerance = CAM_HELI_TOL,
                                tooth_height = CAM_HELI_TOOTH,
                                tip_height = 1.2);
                    translate([0, 0, CAM_HELI_FRONT - 1.6])
                        cylinder(h = shoulder + 1.8,
                                 d1 = CAM_HELI_NOSE, d2 = F_STL_OD);
                }
                translate([0, 0, -1])
                    cylinder(h = CAM_HELI_FRONT + 1.2, d = CAM_HELI_ID);
                translate([0, 0, CAM_HELI_FRONT - 0.2])
                    cylinder(h = shoulder + 0.5, d = TUBE_ID);
            }
            translate([0, 0, z_mesh])
                rotate([0, 0, clock])
                    f_mount_stl_raw();
        }
}

// Printable stand-in for the bought unit, collapsed. Male tip at z = 0.
// M42 male into the cookie, M52 female for fmount_h_*. Not the real part.
module cam_helicoid_gauge() {
    proud = cam_heli_proud();
    male_h = CAM_HELI_MALE;
    nose_h = CAM_HELI_FRONT + 0.2;
    // Root of the M42 tooth. The bore stays 2 mm inside it so a 0.4 mm
    // nozzle has a shank to print, not a bare coil.
    male_root = CAM_HELI_REAR - CAM_HELI_TOOTH / tan(30);
    color("Silver")
        ScrewHole(CAM_HELI_NOSE, nose_h + 0.2,
                  position = [0, 0, male_h + proud - nose_h],
                  pitch = CAM_HELI_PITCH,
                  tolerance = CAM_HELI_TOL,
                  tooth_height = CAM_HELI_TOOTH)
            difference() {
                union() {
                    translate([0, 0, male_h])
                        rotate([180, 0, 0])
                            ScrewThread(CAM_HELI_REAR, male_h,
                                        pitch = CAM_HELI_PITCH,
                                        tolerance = CAM_HELI_TOL,
                                        tooth_height = CAM_HELI_TOOTH,
                                        tip_height = 1.2);
                    translate([0, 0, -0.1])
                        cylinder(h = male_h + 0.3, d = male_root - 0.3);
                    translate([0, 0, male_h - 1.8])
                        cylinder(h = proud + 1.8, d = CAM_HELI_OD);
                    translate([0, 0, male_h + proud * 0.55])
                        difference() {
                            cylinder(h = 0.8, d = CAM_HELI_OD + 1.2);
                            translate([0, 0, -0.1])
                                cylinder(h = 1.0, d = CAM_HELI_OD - 3);
                        }
                }
                translate([0, 0, -0.2])
                    cylinder(h = male_h + proud + 0.4, d = male_root - 4);
            }
}

// lift > 0 is the helicoid extended, camera on the far side of infinity.
module cam_heli_mount_at(mark, lift = 0) {
    ax = cam_axis(mark);
    translate([ax.x, ax.y, cam_heli_seat_z()]) {
        if ($preview)
            cam_helicoid_body(lift);
        translate([0, 0, cam_heli_proud() + lift - CAM_HELI_FRONT])
            part_cam_heli_mount(mark);
    }
}

// -----------------------------------------------------------------------------
// stems — one cookie rebate. Helicoid nut is 9 mm deeper than the infinity
// seat, because the collapsed helicoid stays in the path.
// -----------------------------------------------------------------------------
// Shared rebate floor. The helicoid cookie's face is the collapsed flange.
// The infinity cookie's rim is the skin; its seat is HELI_SHORT above that
// flange, down inside the step.
function stem_drop() = patch_t() - heli_flange_z(EL180_HELI_MIN);

module stem_cookie() {
    translate([0, 0, -stem_drop()])
        port_flange("");
}

module stem_cookie_cuts(tag) {
    translate([0, 0, -stem_drop()]) {
        port_clamp_screws("") port_csk_cut();
        fxp_port_stamp(tag, "");
    }
}

module stem_thread_liner(z0) {
    translate([0, 0, z0 - 0.2])
        cylinder(h = EL180_M62_LEN + 0.4, d = EL180_M62_MAJOR + 8);
}

// Bought M62 helicoid. Female is heli_bottom_z() .. heli_boss_z(). The body
// has to pass through heli_pass_d(). Collapsed, the lens flange is flush
// with the cookie face.
module part_stem() {
    od = HELI_NUT_OD;
    z_bot = heli_bottom_z();
    z_top = heli_boss_z();
    z_cookie = heli_flange_z(EL180_HELI_MIN) - patch_t();
    color("SlateGray")
    mm_split() {
        difference() {
            ScrewHole(EL180_M62_MAJOR, EL180_M62_LEN,
                      pitch = EL180_M62_PITCH, tolerance = EL180_M62_TOL,
                      position = [0, 0, z_bot])
                union() {
                    stem_cookie();
                    translate([0, 0, z_bot - 1])
                        cylinder(h = z_cookie - (z_bot - 1), d = od);
                }
            stem_cookie_cuts(fxp_tag("stem"));
            translate([0, 0, z_top - 0.05])
                cylinder(h = heli_flange_z(EL180_HELI_MIN) - z_top + 4,
                         d = heli_pass_d());
            translate([0, 0, z_bot - 1.2])
                cylinder(h = 1.3, d = EL180_BARREL);
        }
        stem_thread_liner(z_bot);
    }
}

// Lens screws into the cookie. The rim is the chassis skin. Inside the Ø76
// the face steps down to the 158.5 seat. The M62 is the 8 mm under that
// seat and it stops at the inner face of the wall — the Ø60 barrel goes
// on through the chassis hole, so there is no printed tube in the chamber.
module part_stem_el180_inf() {
    od = el180_stem_od();
    seat = inf_seat_z();
    z_thread = seat - EL180_M62_LEN;
    color("SlateGray")
    mm_split() {
        difference() {
            ScrewHole(EL180_M62_MAJOR, EL180_M62_LEN,
                      pitch = EL180_M62_PITCH, tolerance = EL180_M62_TOL,
                      position = [0, 0, z_thread])
                union() {
                    port_flange("");
                    translate([0, 0, -stem_drop()])
                        linear_extrude(stem_drop())
                            port_plate_2d("");
                    translate([0, 0, z_thread])
                        cylinder(h = seat + 0.2 - z_thread, d = od);
                }
            // Step down to the flange. The rim outside this stays at the skin.
            translate([0, 0, seat])
                cylinder(h = patch_t() - seat + 2, d = EL180_LENS_OD + 0.6);
            port_clamp_screws("") {
                port_csk_cut();
                translate([0, 0, -stem_drop() - 0.2])
                    cylinder(h = stem_drop() + 0.4, d = PORT_SCREW_D);
            }
            // The step eats the rim, so the tag sits on the seat.
            translate([0, 0, seat - patch_t()])
                fxp_port_stamp(fxp_tag("stem_inf"), "");
        }
        stem_thread_liner(z_thread);
    }
}

// Printed stand-in for the bought M62 helicoid: a fixed spacer whose length
// is solved for infinity, so it has no travel at all. el180_spacer_add() is
// derived from the chassis, so it tracks any change to BOX_XY or the plate.
// Print a second at +0.5 mm if the first lands long; the shims only add.
function el180_adapter_h() = EL180_HELI_MALE + el180_spacer_add();

module part_el180_adapter() {
    hm = EL180_HELI_MALE;               // male into the stem boss
    hb = el180_spacer_add();            // what it adds past the boss face
    hf = EL180_M62_LEN;                 // female for the lens
    overlap = 3;
    hex_od = heli_pass_d() - 0.8;       // has to pass the recessed nut
    shank_d = EL180_M62_MAJOR - 1.6;
    hex_h = hb + overlap;
    color("SlateGray")
    difference() {
        union() {
            ScrewThread(EL180_M62_MAJOR, hm, pitch = EL180_M62_PITCH,
                        tolerance = EL180_M62_TOL);
            cylinder(h = hm + overlap, d = shank_d);
            translate([0, 0, hm - overlap])
                rotate([0, 0, 30])
                    ScrewHole(EL180_M62_MAJOR, hf, pitch = EL180_M62_PITCH,
                              tolerance = EL180_M62_TOL,
                              position = [0, 0, hex_h - hf])
                        cylinder(h = hex_h, d = hex_od, $fn = 6);
        }
        // Through-bore at the M62 minor; the hex behind the female stays
        // EL180_BARREL so the 60 mm lens barrel drops in.
        translate([0, 0, hm - overlap])
            cylinder(h = hex_h - hf + 0.4, d = EL180_BARREL);
        translate([0, 0, -0.2])
            cylinder(h = hm + hex_h + 0.4, d = EL180_BORE);
        translate([0, -hex_od / 2 * cos(30) - 0.05,
                   hm + hb * 0.5])
            rotate([90, 0, 0])
                part_stamp_stack_cut(fxp_tag("el180"), size = 2.2);
    }
    if ($preview && !SHOW_LENS)
        color("DimGray", 0.45)
            translate([0, 0, hm + hb])
                el180_ghost();
}

module el180_ghost() {
    // Flange face on the stem face. +Z is the front of the lens, so the
    // Ø60 barrel runs back through the M62 into the boss.
    el180n(show_glass = SHOW_LENS_MARKS);
}

// Clamp on the external M62, ISCO on the collar, stand under the Ø90.
module isco_on_body() {
    seat = inf_stem()
        ? inf_seat_z()
        : heli_flange_z(heli_at_infinity());
    lift = EXPLODED ? ex * 1.4 : 0;
    at_stem()
        translate([0, 0, seat + lift]) {
            color("DimGray", 0.92)
                el180n(show_glass = SHOW_LENS_MARKS);
            translate([0, 0, front_z - M62_LEN])
                isco_clamp("DarkOrange");
            translate([0, 0, front_z - M62_LEN + shoulder_z()])
                color("Goldenrod")
                    isco_ultrastar(show_glass = SHOW_LENS_MARKS);
        }
    saddle_y = -BOX_XY / 2
        - (seat + lift + front_z - M62_LEN + shoulder_z()
           + z_nose() + L_NOSE / 2);
    translate([50, saddle_y - 65, base_z()])
        rotate([0, 0, 90])
            isco_stand();
}

// -----------------------------------------------------------------------------
// lid
// -----------------------------------------------------------------------------
module lid_lining_mask() {
    s = BOX_XY;
    L = INNER_LINING;
    translate([0, 0, BOX_Z / 2 + ex * 0.4])
        translate([0, 0, (-40 + L) / 2])
            cube([s + 4, s + 4, 40 + L], center = true);
}

module part_lid() {
    s   = BOX_XY;
    out = chassis_out();
    color("DarkSlateGray")
    mm_split() {
    difference() {
        translate([0, 0, BOX_Z / 2 + ex * 0.4]) {
            linear_extrude(LID_T)
                round_rect(out, out, PORT_BOSS_R);
            translate([0, 0, -LID_LIP / 2 + 0.01])
                lid_align_lip();
            lid_retain_tabs(lip = LID_LIP);
            display_lid_nut_pads(LID_LIP);
            display_lid_bosses(LID_T);
        }
        translate([0, 0, BOX_Z / 2 + ex * 0.4]) {
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW),
                           -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
            display_lid_cuts(LID_T, LID_LIP);
            plate_stamp(fxp_tag("lid"), s, LID_T, STAMP_DEPTH, 5.0);
            difference() {
                lid_inner_ribs();
                lid_retain_keepout();
                display_lid_pad_keepout();
            }
        }
    }
        lid_lining_mask();
    }
}

// -----------------------------------------------------------------------------
// base and cradles — the bayonet locates, the base carries
// -----------------------------------------------------------------------------
function base_z()      = -BOX_Z / 2 - chassis_plinth() - BASE_T;
function base_cam_d()  = d_plate_to_mount() + d800_tripod_in();
function base_r_xy()   = [base_cam_d(), -sensor_shift()];
function base_t_xy()   = [sensor_shift(), base_cam_d()];
function base_q_xy() =
    let (r = base_r_xy(), t = base_t_xy(),
         u = (t - r) / norm(t - r),
         p = r + u * BASE_RT_ALONG)
        p * (1 - BASE_RT_INSET / norm(p));
function base_web_pts() = [[0, 0], base_r_xy(), base_q_xy(), base_t_xy()];
// Tripod socket under the combined centre of mass: chassis plus lens at the
// origin, one D800 at each camera pad. Masses in kg.
function base_tripod_xy() =
    let (m_box = 1.4, m_cam = 1.0,
         r = base_r_xy(), t = base_t_xy(),
         tot = m_box + 2 * m_cam)
        [(m_cam * (r.x + t.x)) / tot, (m_cam * (r.y + t.y)) / tot];
function base_stamp_xy() =
    let (r = base_r_xy(), t = base_t_xy(),
         m = [(r.x + t.x) / 2, (r.y + t.y) / 2],
         n = m / norm(m))
        [m.x - n.x * 10, m.y - n.y * 10];
function base_pad_xy(mark) = mark == "T" ? base_t_xy() : base_r_xy();
// Camera pads are stadiums along the optical axis, not circles: the cradle
// footprint and its four bolts are longer than they are wide, and a round
// BASE_PAD_D pad put the bolts 0.4 mm inside the rim.
module base_cam_pad_2d(p, grow = 0) {
    a = atan2(p.y, p.x);
    translate(p)
        rotate(a)
            hull() {
                translate([-BASE_SLOT_L / 2, 0])
                    circle(d = BASE_PAD_D + grow);
                translate([ BASE_SLOT_L / 2, 0])
                    circle(d = BASE_PAD_D + grow);
            }
}

module base_hex_grid_2d() {
    cell = BASE_HEX_CELL;
    for (j = [-2:24], i = [-2:24])
        translate([(i + (j % 2) * 0.5) * cell, j * cell * sin(60)])
            rotate(30)
                circle(d = BASE_HEX_D, $fn = 6);
}

module base_hex_cuts_2d() {
    r = base_r_xy();
    t = base_t_xy();
    q = base_tripod_xy();
    s = base_stamp_xy();
    intersection() {
        difference() {
            offset(-1.8)
                offset(BASE_WEB / 2)
                    polygon(base_web_pts());
            circle(d = BASE_PAD_D + 4);
            base_cam_pad_2d(r, 4);
            base_cam_pad_2d(t, 4);
            translate(q) circle(d = BASE_PAD_D + 4);
            translate(s)
                rotate(135)
                    square([84, 10], center = true);
        }
        base_hex_grid_2d();
    }
}

// 1/4-20 slot, pointing along the optical axis so the body can slide to
// meet the register.
module base_slot_2d(p) {
    a = atan2(p.y, p.x);
    translate(p)
        rotate(a)
            hull() {
                translate([-BASE_SLOT_L / 2, 0]) circle(d = BASE_SLOT_W);
                translate([ BASE_SLOT_L / 2, 0]) circle(d = BASE_SLOT_W);
            }
}

// Thumbscrew head pocket from the print bed; clipped to the pad.
module base_relief_2d(p) {
    a = atan2(p.y, p.x);
    intersection() {
        base_cam_pad_2d(p);
        translate(p)
            rotate(a)
                hull() {
                    translate([-BASE_SLOT_L / 2, 0]) circle(d = BASE_HEAD_D);
                    translate([ BASE_SLOT_L / 2, 0]) circle(d = BASE_HEAD_D);
                }
    }
}

// Four M3s per camera pad hold the cradle down. du runs along the optical
// axis, dv across it; both stay inside the stadium pad.
function cradle_bolt_du(i) = (i % 2 ? 1 : -1) * (BASE_SLOT_L / 2 + 13);
function cradle_bolt_dv(i) = (i < 2 ? -1 : 1) * 15;
function cradle_bolt_xy(mark, i) =
    let (p = base_pad_xy(mark), a = atan2(p.y, p.x),
         u = [cos(a), sin(a)], v = [-u.y, u.x],
         du = cradle_bolt_du(i), dv = cradle_bolt_dv(i))
        [p.x + u.x * du + v.x * dv, p.y + u.y * du + v.y * dv];

module base_blank() {
    linear_extrude(BASE_T)
        union() {
            offset(BASE_WEB / 2)
                polygon(base_web_pts());
            circle(d = BASE_PAD_D);
            base_cam_pad_2d(base_r_xy());
            base_cam_pad_2d(base_t_xy());
            translate(base_tripod_xy()) circle(d = BASE_PAD_D);
        }
}

module part_base() {
    q = base_tripod_xy();
    color("SlateGray")
    difference() {
        base_blank();
        // Chassis 1/4-20 through the origin pad.
        translate([0, 0, -0.2])
            cylinder(h = BASE_T + 0.4, d = BASE_SCREW_D);
        translate([0, 0, -0.2])
            cylinder(h = BASE_HEAD_COUNTER_H + 0.2, d = BASE_HEAD_D);
        // Camera 1/4-20 slots + head pockets.
        translate([0, 0, -0.2])
            linear_extrude(BASE_T + 0.4)
                union() {
                    base_slot_2d(base_r_xy());
                    base_slot_2d(base_t_xy());
                }
        translate([0, 0, -0.2])
            linear_extrude(BASE_T - 2.0)
                union() {
                    base_relief_2d(base_r_xy());
                    base_relief_2d(base_t_xy());
                }
        // Cradle bolts, M3 through with a nut trap underneath.
        for (mark = ["R", "T"], i = [0:3]) {
            p = cradle_bolt_xy(mark, i);
            translate([p.x, p.y, -0.2])
                cylinder(h = BASE_T + 0.4, d = PORT_SCREW_D);
            translate([p.x, p.y, -0.05])
                rotate([0, 0, 30])
                    cylinder(h = PORT_NUT_T + 0.15,
                             d = PORT_NUT_AF / cos(30), $fn = 6);
        }
        // Tripod insert, from the underside.
        translate([q.x, q.y, -0.05]) {
            cylinder(h = min(BASE_T - TRIPOD_KEEP, TRIPOD_INSERT_L + 1.0) + 0.15,
                     d = TRIPOD_INSERT_D);
            cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
        }
        translate([0, 0, -0.2])
            linear_extrude(BASE_T + 0.4)
                base_hex_cuts_2d();
        translate([base_stamp_xy().x, base_stamp_xy().y, BASE_T - STAMP_DEPTH])
            rotate(135)
                part_stamp_cut(fxp_tag("base"));
    }
}

// Plinth that lifts the body's tripod socket onto the optical axis. Nothing
// else: footprint and bolt pattern match base_cam_pad_2d() and the top is
// bare.
//
// It carried an anti-twist flange up the back of the body and that is gone.
// The bayonet already fixes yaw far better than a 46 mm-wide flange could,
// and mounting the camera means bringing it in along the axis and twisting,
// so anything standing up off the plinth is in the way of the one motion
// the build depends on. A camera plate's job is to take the weight; this
// one takes the weight.
function cradle_lift() = CRADLE_T;
function cradle_len()  = BASE_SLOT_L + BASE_PAD_D;   // along the axis
function cradle_wid()  = BASE_PAD_D;                 // across it

module cradle_foot_2d() {
    hull() {
        translate([-BASE_SLOT_L / 2, 0]) circle(d = BASE_PAD_D);
        translate([ BASE_SLOT_L / 2, 0]) circle(d = BASE_PAD_D);
    }
}

module part_cradle(mark = "R") {
    lift = cradle_lift();
    color("DimGray")
    difference() {
        translate([0, 0, lift / 2])
            linear_extrude(lift, center = true)
                cradle_foot_2d();
        // 1/4-20 slot along the axis: sets how far the body sits from the
        // register, so the bayonet can seat without the screw fighting it.
        translate([0, 0, -0.2])
            linear_extrude(lift + 0.4)
                hull() {
                    translate([-BASE_SLOT_L / 2, 0]) circle(d = BASE_SLOT_W);
                    translate([ BASE_SLOT_L / 2, 0]) circle(d = BASE_SLOT_W);
                }
        // Cradle bolts: M3 clearance, heads sunk into the plinth top.
        for (i = [0:3]) {
            sx = cradle_bolt_du(i);
            sy = cradle_bolt_dv(i);
            translate([sx, sy, -0.2])
                cylinder(h = lift + 0.4, d = PORT_SCREW_D);
            translate([sx, sy, lift - PORT_HEAD_H])
                cylinder(h = PORT_HEAD_H + 0.4, d = PORT_HEAD_D);
        }
        translate([-BASE_SLOT_L / 2 - 11, 0, lift - STAMP_DEPTH])
            rotate(90)
                part_stamp_cut(fxp_tag(mark == "T" ? "cradle_t" : "cradle_r"),
                               STAMP_DEPTH, 3.0);
    }
}

module base_at() {
    if (SHOW_BASE) {
        translate([0, 0, base_z()])
            part_base();
        for (mark = ["R", "T"]) {
            p = base_pad_xy(mark);
            translate([p.x, p.y, base_z() + BASE_T])
                rotate([0, 0, atan2(p.y, p.x)])
                    part_cradle(mark);   // local +X runs away from the plate
        }
    }
}

// -----------------------------------------------------------------------------
// drop-in baffle stack — printed flat, pushed down the arm bore
// -----------------------------------------------------------------------------
BAFFLE_RING_T = 1.2;
BAFFLE_RINGS  = 5;

// Station of ring i, measured from the sensor.
function baffle_station(i) =
    FLANGE_F + 6 + i * (d_plate_to_mount() - 12) / (BAFFLE_RINGS - 1);
// A ring is only worth printing if the bundle leaves an annulus behind. At
// f/5.6 the frame corners fill the bore, so there is nothing to print and
// this returns 0 rather than an inside-out ring.
function baffle_ring_id(i) = need_bore(FSTOP, baffle_station(i)) + 1.2;
function baffle_ring_od() = TUBE_ID - 0.4;
function baffle_ring_fits(i) = baffle_ring_id(i) <= baffle_ring_od() - 1.6;
function baffle_ring_count() =
    len([for (i = [0 : BAFFLE_RINGS - 1]) if (baffle_ring_fits(i)) i]);

module part_baffle() {
    od = baffle_ring_od();
    keep = [for (i = [0 : BAFFLE_RINGS - 1]) if (baffle_ring_fits(i)) i];
    color("DimGray")
    for (n = [0 : max(len(keep), 1) - 1]) {
        if (n < len(keep)) {
            i  = keep[n];
            id = baffle_ring_id(i);
            translate([n * (od + 6), 0, 0])
                difference() {
                    cylinder(h = BAFFLE_RING_T, d = od);
                    translate([0, 0, -0.1])
                        cylinder(h = BAFFLE_RING_T + 0.2, d = id);
                    translate([0, -(od + id) / 4, BAFFLE_RING_T - STAMP_DEPTH])
                        part_stamp_stack_cut(str("fxp_bf", i + 1), size = 1.8);
                }
        }
    }
}

// -----------------------------------------------------------------------------
// M52 ring gauge — print this before you print an arm
// -----------------------------------------------------------------------------
// One ring per F_REV_GAUGE step, same wall and same orientation as the arm
// mouth so it prints the way the real thread will. Each is stamped with its
// clearance in hundredths of a millimetre. Thread the Fotodiox ring into all
// four, keep the tightest one that still runs down by hand without rocking,
// and put its number into F_REV_CLEAR.
GAUGE_H = 7;

module part_ringgauge() {
    n = len(F_REV_GAUGE);
    color("DimGray")
    for (i = [0 : n - 1]) {
        c = F_REV_CLEAR + F_REV_GAUGE[i];
        translate([i * (TUBE_OD + 6), 0, 0])
            difference() {
                cylinder(h = GAUGE_H, d = TUBE_OD);
                translate([0, 0, -0.1])
                    cylinder(h = GAUGE_H + 0.2, d = f_rev_minor() - 1.2);
                f_rev_thread_cut(GAUGE_H + 0.4, c);
                translate([0, 0, GAUGE_H - F_REV_LEAD])
                    cylinder(h = F_REV_LEAD + 0.1,
                             d1 = F_REV_MAJOR + c - F_REV_TOOTH / tan(30),
                             d2 = F_REV_MAJOR + c - F_REV_TOOTH / tan(30)
                                  + 2 * F_REV_LEAD);
                translate([0, -(TUBE_OD + f_rev_minor()) / 4,
                           GAUGE_H - STAMP_DEPTH])
                    part_stamp_stack_cut(str("fxp_m52_", round(c * 100)),
                                         size = 2.0);
            }
    }
}

// -----------------------------------------------------------------------------
// ghosts and guides
// -----------------------------------------------------------------------------
function body_shift_x(mark) = mark == "T" ? BODY_T_X : BODY_R_X;
function body_shift_y(mark) = mark == "T" ? BODY_T_Y : BODY_R_Y;
function body_shift_z(mark) = mark == "T" ? BODY_T_Z : BODY_R_Z;
// Both bodies upright, world +Z = camera top, both landscape.
function body_roll_r() = 90;
function body_roll_t() = 180;

module camera_body_at(out_len, rx = 0, ry = 0, roll = 0, mark = "") {
    if (SHOW_BODIES > 0)
        color("DimGray", 0.92)
            along_cam(rx, ry, mark)
                translate([0, 0, out_len + mount_stack() - CAM_RECESS + ex])
                    translate([body_shift_x(mark), body_shift_y(mark),
                               body_shift_z(mark)])
                        camera_body(roll, which = 2);
}

// Drawn from the front panel back, not from the register back: the whole
// point of this ghost is that a D800 reaches D800_PROUD past its own flange,
// so if it is going to foul the chassis face this is where you see it.
module ghost_body_at(mark = "") {
    if ($preview && SHOW_GHOSTS)
        color("black", 0.12)
            along_cam(0, 0, mark)
                translate([0, 0, mount_standoff() - d800_proud()
                                 + BODY_D / 2 + ex])
                    cube([BODY_W, BODY_H, BODY_D], center = true);
}

module taking_lens_at() {
    if (show_isco())
        isco_on_body();
    else if (SHOW_LENS)
        color("DimGray", 0.92)
            at_stem()
                translate([0, 0, (inf_stem()
                                    ? inf_seat_z()
                                    : heli_flange_z(heli_at_infinity()))
                                 + (EXPLODED ? ex * 1.4 : 0)])
                    el180_ghost();
}

// Gold hairlines down each leg, plus the plate's clear-aperture footprint at
// FSTOP so you can see the margin rather than trust the echo.
module optical_axis_guides() {
    if ($preview && SHOW_AXES) {
        color("gold", 0.45) {
            rotate([90, 0, 0])
                cylinder(h = d_plate_to_flange(EL180_HELI_MIN), d = 1.0);
            translate([0, -sensor_shift(), 0])
                rotate([0, 90, 0])
                    cylinder(h = d_plate_to_mount() + 2, d = 1.0);
            translate([sensor_shift(), 0, 0])
                rotate([-90, 0, 0])
                    cylinder(h = d_plate_to_mount() + 2, d = 1.0);
        }
        color("red", 0.30)
            rotate([0, 0, -45])
                translate([0, 0, 0])
                    cube([0.4,
                          need_clear(FSTOP, path_after_plate()) * sqrt(2),
                          need_clear(FSTOP, path_after_plate())], center = true);
    }
}

// -----------------------------------------------------------------------------
module assembly() {
    if (SHELL == "logo")
        chassis_body();
    else
        part_chassis();
    // Pockets stay empty in the chassis STL. Here the plugs sit back in
    // them so the wall reads as printed. LOGO_LAYER picks one colour.
    if (SHELL != "inner" && SHELL != "outer")
        logo_fills();

    if (SHOW_PANELS) {
        at_stem()
            translate([0, 0, EXPLODED ? ex : 0])
                if (inf_stem())
                    part_stem_el180_inf();
                else
                    part_stem();
        if (!inf_stem())
            at_stem()
                translate([0, 0, heli_bottom_z()
                                 + (EXPLODED ? ex * 1.4 : 0)])
                    part_el180_adapter();
        at_reflect()
            translate([0, 0, (EXPLODED ? ex : 0) - CAM_RECESS])
                if (heli_cam()) {
                    part_cam_heli_arm("R");
                    cam_heli_mount_at("R", CAM_HELI_SHOW);
                } else
                    part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");
        at_transmit()
            translate([0, 0, (EXPLODED ? ex : 0) - CAM_RECESS])
                if (heli_cam()) {
                    part_cam_heli_arm("T");
                    cam_heli_mount_at("T", CAM_HELI_SHOW);
                } else
                    part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    }

    fxp_pair(show_glass = $preview,
             explode_z = EXPLODED ? (BOX_Z / 2 + 40) : 0,
             sh = sensor_shift(),
             tag = fxp_tag("tray"));

    if (SHOW_LID)
        part_lid();
    if (SHOW_MONITOR || SHOW_PI)
        translate([0, 0, BOX_Z / 2 + LID_T + (EXPLODED ? ex * 0.4 : 0)]) {
            if (SHOW_MONITOR)
                display_mount();
            monitor_easel() {
                if (SHOW_MONITOR)
                    monitor_ghost();
                if (SHOW_PI)
                    monitor_pi();
            }
        }

    base_at();

    at_reflect() {
        ghost_body_at("R");
        camera_body_at(reflect_tube_len(), rx = -field_toe(),
                       roll = body_roll_r(), mark = "R");
    }
    at_transmit() {
        ghost_body_at("T");
        camera_body_at(transmit_tube_len(), ry = -field_toe(),
                       roll = body_roll_t(), mark = "T");
    }
    taking_lens_at();
    optical_axis_guides();
    diagnostics();
}

module diagnostics() {
    d = path_after_plate();
    need = need_clear(FSTOP, d);
    have = bs_in_plane();
    echo(str("FXPAN 65  |  ", BS_H, "×", BS_W, "×", BS_THICK,
             " 50/50 at 45°, S1 toward the lens, ", BS_W,
             " across the fold  |  ARM_MOUNT=", ARM_MOUNT,
             " (", printed_f() ? "printed F" : "reverse ring", ")",
             "  SHELL=", SHELL));
    echo(str("path: plate→flange ", d_plate_to_flange(EL180_HELI_MIN), "..",
             d_plate_to_flange(EL180_HELI_MAX),
             " + plate→mount ", d_plate_to_mount(),
             " + flange ", FLANGE_F,
             "  =  PATH ", path_min(), "..", path_max(), " mm",
             "  |  infinity stem ", path_inf(), " mm"));
    echo(str("infinity: register ", EL_FFD, " mm (focal length ", EL_FOCAL,
             ") lands at helicoid ",
             round(heli_at_infinity() * 10) / 10, " mm of ",
             EL180_HELI_MIN, "..", EL180_HELI_MAX,
             (path_min() <= EL_FFD && EL_FFD <= path_max())
               ? "  → in range"
               : "  *** OUT OF RANGE ***",
             "  |  seat z ", inf_seat_z(),
             "  helicoid nut ", heli_bottom_z(), "..", heli_boss_z(),
             "  passage ", heli_pass_d()));
    echo(str("infinity cookie: rim at the skin z ", skin_z(),
             ", step ", EL180_LENS_OD + 0.6, " down ",
             round((skin_z() - inf_seat_z()) * 10) / 10,
             " mm to the seat at z ", inf_seat_z(),
             "  |  thread ", inf_seat_z() - EL180_M62_LEN, "..", inf_seat_z(),
             " (wall inner face ", -WALL, ")"));
    echo(str("body fit: F register stands ",
             round((patch_t() + mount_standoff() - skin_z()) * 10) / 10,
             " mm off the chassis skin (skin ", skin_z(),
             " mm; arm tube ", ARM_TUBE,
             " + ring ", F_REV_STACK, ", cookies recessed ", CAM_RECESS, ")",
             "  vs a D800 front panel ", d800_proud(), " mm proud of its flange",
             patch_t() + mount_standoff() - skin_z() >= d800_proud()
               ? str("  → ",
                     round((patch_t() + mount_standoff() - skin_z()
                            - d800_proud()) * 10) / 10,
                     " mm to twist it on")
               : "  *** THE BODY CANNOT GO ON ***"));
    echo(str("stitch: overlap ", overlap_frac(), "  sensor_shift ",
             sensor_shift(), " mm  stitch_w ", stitch_w(), " mm  ",
             stitch_px(), "×", SENSOR_PX_H, " px  ",
             round(stitch_aspect() * 1000) / 1000, ":1  (XPan 2.708:1)  ",
             round(stitch_px() * SENSOR_PX_H / 1e5) / 10, " MP"));
    need_v = need_clear_v(FSTOP, d);
    echo(str("plate at f/", FSTOP, ": across the fold need ",
             round(need * 10) / 10, " mm, have ", round(have * 100) / 100,
             " (", BS_W, "/√2)  →  ", round((have / need - 1) * 1000) / 10, "%",
             need > have ? " *** CLIPS ***" : "",
             "  |  along it need ", round(need_v * 10) / 10,
             " mm, have ", BS_H, "  →  ",
             round((BS_H / need_v - 1) * 1000) / 10, "%",
             need_v > BS_H ? " *** CLIPS ***" : ""));
    // Worked at the frame corner, not along the stitch axis — see need_bore().
    b_wall = path_after_plate() - BOX_XY / 2;
    echo(str("arm bore at f/", FSTOP, " (frame corner): need ",
             round(need_bore(FSTOP, b_wall) * 10) / 10,
             " mm at the box wall (TUBE_ID ", TUBE_ID,
             need_bore(FSTOP, b_wall) > TUBE_ID ? " — CLIPS" : "", ") and ",
             round(need_bore(FSTOP, FLANGE_F) * 10) / 10,
             " mm at the flange (F_BORE ", F_BORE,
             need_bore(FSTOP, FLANGE_F) > F_BORE ? " — CLIPS" : "", ")",
             "  [stitch axis alone would say ",
             round(need_bore_u(FSTOP, FLANGE_F) * 10) / 10, "]"));
    echo(str("mouth: ", printed_f() ? "printed F bayonet" : "metal reverse ring",
             ", clear ", mouth_clear(), " mm  →  ",
             mouth_ever_clean()
               ? str("whole frame corner-to-corner from f/",
                     round(mouth_fstop() * 10) / 10)
               : "NEVER passes the frame corners at any aperture",
             printed_f()
               ? "   (Archive-663 lip is 40 mm; metal reverse ring is 44 mm / f/8.4)"
               : "   (44 mm is the real F throat — this is the hard ceiling, not a print limit)"));
    echo(str("camera helicoid: bought M", CAM_HELI_NOSE, " female / M",
             CAM_HELI_REAR, " male ×", CAM_HELI_PITCH,
             " ", CAM_HELI_MIN, "–", CAM_HELI_MAX,
             "  body ", CAM_HELI_OD, "  neck ", CAM_HELI_NECK,
             "  recess ", CAM_HELI_RECESS,
             "  |  collapsed is infinity, register R ",
             cam_heli_register_z("R"), " T ", cam_heli_register_z("T"),
             "  |  ", cam_heli_travel(), " mm outward",
             "  |  shown ", CAM_HELI_SHOW, " mm out"));
    echo(str("baffle rings that fit at f/", FSTOP, ": ", baffle_ring_count(),
             " of ", BAFFLE_RINGS,
             baffle_ring_count() == 0
               ? "  (the bundle fills the bore — nothing to print)" : ""));
    echo(str("ring lock: 2 M3 grubs at ", REV_LOCK_HOME - REV_LOCK_SPREAD / 2,
             "° and ", REV_LOCK_HOME + REV_LOCK_SPREAD / 2,
             "° off camera-up, nuts outboard of the thread at r ",
             rev_lock_r_in(), "..", rev_lock_r_in() + REV_LOCK_NUT_T,
             " in a lug to r ", rev_lock_r_out(), " (ring OD/2)",
             "  |  wall left over the thread ",
             round(rev_lock_thread_wall() * 100) / 100, " mm",
             rev_lock_thread_wall() < 0.8
               ? "  *** thin — drop REV_LOCK_WALL or F_REV_CLEAR ***" : "",
             rev_lock_ok(transmit_tube_len())
               ? "" : "  *** T arm too short for the nut slot ***"));
    echo(str("transmit leg crosses ", BS_THICK,
             " mm of n=", BS_N, " glass at 45°: tube shortened by ",
             round(bs_t_comp() * 1000) / 1000, " mm"));
    head_r = norm(clamp_xy("", 1, 1)) - PORT_CSK_D / 2;
    echo(str("cookie ", round(port_patch_u() * 10) / 10, "×",
             round(port_patch_v("R") * 10) / 10, " arm, ",
             round(stem_plate_w() * 10) / 10, " square stem, ",
             "centred on the bore, rebate closed all round",
             "  |  clamp M3 at r ", round(port_clamp_r() * 10) / 10,
             " ± ", PORT_CLAMP_SEP,
             "  |  M62 boss ", el180_stem_od(), " inside heads at ",
             round(head_r * 100) / 100,
             el180_stem_od() / 2 >= head_r
               ? "  *** the boss is over the screws again ***" : "",
             "  |  ", round((1 - (port_patch_u() * (port_patch_v("R") * 2
                            + port_patch_v(""))) / (3 * 8100)) * 1000) / 10,
             "% less plate than three 90 squares"));
    echo(str("cookie vs chassis skin: outboard edge at ",
             round((sensor_shift() + port_patch_v("R") / 2) * 10) / 10,
             " of a face flat to ", chassis_out() / 2 - PORT_BOSS_R,
             " (PORT_BOSS_R ", PORT_BOSS_R, ")  →  stands ",
             round(port_edge_proud() * 100) / 100, " mm proud",
             port_edge_proud() > PORT_EDGE_CHAM
               ? "  *** past the chamfer — drop PORT_BOSS_R ***"
               : ", inside the chamfer, so port_chassis_clip takes it off"));
    echo(str("under the chassis: lens axis ", d800_axis_base(),
             " above a D800's baseplate, chamber floor at ", BOX_Z / 2,
             "  →  plinth ", chassis_plinth(), " + cradle ", CRADLE_T,
             " + base ", BASE_T,
             chassis_plinth() > PORT_SLOT_LIP
               ? str(" (the plinth is making up ",
                     round((chassis_plinth() - PORT_SLOT_LIP) * 10) / 10,
                     " mm the short chamber does not have)") : ""));
    echo(str("pro line: ", STRIPE_H, " mm groove ", STRIPE_LIFT,
             " mm above the floor, depth ", MARK_DEPTH,
             "  →  chassis_logo_stripe"));
    echo(str("wall mark: ", round(SPEC_W * LOGO_SCALE * 10) / 10,
             " × ", round(logo_art_h() * LOGO_SCALE * 10) / 10,
             " mm from logos/fxpan_*.stl  →  chassis_logo_fx / _word / _outline"));
    echo(str("chassis ", BOX_XY, "×", BOX_XY, "×", BOX_Z,
             " chamber (outer ", chassis_out(), "×", chassis_out(), "×",
             chassis_out_z(), ")  |  arm tube R ",
             round(reflect_tube_len() * 100) / 100, " T ",
             round(transmit_tube_len() * 100) / 100,
             " mm  |  chamber half ", BOX_XY / 2 - WALL,
             " vs port reach ", sensor_shift() + (TUBE_ID + 0.6) / 2));
    echo("export: ./export_fxpan.sh  →  stls/fxpan/");
}

module export_part() {
    if (PART == "chassis")
        part_chassis();
    else if (PART == "stem")
        part_stem();
    else if (PART == "stem_el180_inf")
        part_stem_el180_inf();
    else if (PART == "arm_r" || PART == "arm_r_f")
        part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");
    else if (PART == "arm_t" || PART == "arm_t_f")
        part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    else if (PART == "arm_r_h")
        part_cam_heli_arm("R");
    else if (PART == "arm_t_h")
        part_cam_heli_arm("T");
    else if (PART == "fmount_h_r")
        part_cam_heli_mount("R");
    else if (PART == "fmount_h_t")
        part_cam_heli_mount("T");
    else if (PART == "cam_helicoid")
        cam_helicoid_gauge();
    else if (PART == "lid")
        part_lid();
    else if (PART == "display_mount")
        display_mount_print();
    else if (PART == "fxp_tray" || PART == "tray")
        fxp_cartridge(show_glass = false, sh = sensor_shift(),
                      tag = fxp_tag("tray"));
    else if (PART == "base")
        part_base();
    else if (PART == "cradle_r")
        part_cradle("R");
    else if (PART == "cradle_t")
        part_cradle("T");
    else if (PART == "baffle")
        part_baffle();
    else if (PART == "ringgauge")
        part_ringgauge();
    else if (PART == "shims")
        shim_set();
    else if (PART == "el180_adapter")
        part_el180_adapter();
    else if (PART == "isco_cut")
        difference() {
            assembly();
            translate([0.02, -600, -200])
                cube([700, 1200, 600]);
        }
    else
        assembly();
}

export_part();
