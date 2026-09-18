// =============================================================================
// fxpan/WATCH_ME.scad — FXPAN 65: clean-sheet FX panoramic body
// =============================================================================
// Two D800 behind one EL-Nikkor 180/5.6N and a 75×75×1 50/50 plate.
// 64.80 × 23.9 mm stitch, 2.711:1 (XPan is 2.708:1), 13248 × 4912 = 65.1 MP.
// The chamber is deliberately NOT a cube. BOX_Z carries the 75 mm plate on
// its diagonal; BOX_XY is whatever the path budget leaves, because every mm
// of chassis costs two mm of the 180 mm flange-to-sensor distance. A cube
// tall enough for the plate would put the shortest path at 207 mm and put
// infinity out of reach entirely — read the derivation in params.scad.
//
// Lens −Y. Plate at the origin, 45°, S1 (the 50/50 coating) toward the lens.
// Reflect leg → +X (camera R), transmit leg → +Y (camera T). Both bores are
// translated by sensor_shift() in opposite senses; no tube toe, no Scheimpflug.
// Three ports are C-channels open at the lid; the lid plugs the slot tops.
//
// This body does not share parts with hybrid_shift. Every STL is stamped
// fxp_* and the bore is wider (TUBE_ID 46 / F_BORE 44.0 vs 52 / 40.3) so the
// 14.4 mm shift does not clip. Open this file and read the echo() lines.
// =============================================================================

/* [Part] */
PART = "assembly"; // [assembly:Assembly, chassis:Chassis, stem:Stem EL 180, arm_r:Arm R, arm_t:Arm T, arm_r_f:Arm R printed F, arm_t_f:Arm T printed F, lid:Lid, fxp_tray:Plate cartridge, base:Base, cradle_r:Cradle R, cradle_t:Cradle T, baffle:Baffles, ringgauge:M52 ring gauge, shims:Shims, el180_adapter:EL 180 adapter]

include <params.scad>
include <../lib/threads.scad>
include <../lib/part_stamp.scad>
include <fxp_f_mount.scad>
use <fxp_tray.scad>
use <shims.scad>
use <../camera_body.scad>

/* [View] */
SHOW_LID = 1; // [0:hide, 1:show]
SHOW_PANELS = 1; // [0:hide, 1:show]
SHOW_BODIES = 0; // [0:hide, 1:D800]
SHOW_LENS = 0; // [0:hide, 1:show]
SHOW_BASE = 1; // [0:hide, 1:show]
SHOW_AXES = 1; // [0:hide, 1:show]

/* [Camera] */
D800_TRIPOD_ABOVE = 10.0; // mm, 1/4-20 above chassis bottom (measure yours)
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
// Wall badge, one STL per colour. The chassis pocket is always every layer.
LOGO_LAYER = "all"; // [all:All, fx:Nikon FX badge, word:PAN, mp:65MP, rule:Hairline, spec:Pixels]

/* [Mount] */
ARM_MOUNT = 0; // [0:reverse ring, 1:printed F]
F_MOUNT_CLOCK = 0;
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
    ARM_MOUNT || PART == "arm_r_f" || PART == "arm_t_f";
function mount_stack() = printed_f() ? F_FMOUNT_STACK : F_REV_STACK;
// Narrowest thing in the light path at the flange. The metal reverse ring
// keeps the real 44 mm F throat; the printed bayonet mesh is only 38 mm.
function mouth_clear() = printed_f() ? F_STL_THROAT : F_THROAT;
// Widest aperture that puts the whole frame, corners included, through that
// mouth. need_bore() falls as you stop down, so bisect for where it crosses.
// It does not fall to zero: at f/inf the field term alone remains, so a mouth
// narrower than that never passes the corners. The printed bayonet is one.
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
// d_plate_to_mount(), so the printed F (a 1.75 mm stack) needs a longer tube
// than the reverse ring (8 mm) to land in the same place.
function reflect_tube_len()  =
    d_plate_to_mount() - BOX_XY / 2 - patch_t() - mount_stack();
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
// port frame — cookie drops down a C-channel, retained on three sides
// -----------------------------------------------------------------------------
module round_rect(w, h, r) {
    offset(r)
        offset(-r)
            square([w, h], center = true);
}

// The shell stops at the cookie face. There used to be a 4 mm retaining wall
// outboard of it, and on the two camera faces that wall is precisely what a
// D800's front panel lands on — the body is wider than the chassis, so there
// is no relieving it locally. The cookie is stopped inboard by the chamber
// wall it sits against, on three sides by its rebate, and outboard by four
// countersunk M3s, which is a better joint than the wall was.
function chassis_shell_t() = patch_t();
function chassis_out()     = BOX_XY + 2 * chassis_shell_t();
function chassis_out_z()   = BOX_Z + 2 * chassis_shell_t();

module port_flange(patch = PORT_PATCH) {
    translate([0, 0, patch_t() / 2])
        cube([patch, patch, patch_t()], center = true);
}

// Outboard cookie edge in the shift direction. The shifted tubes reach past
// the cookie, so chord-cut that OD and let the chassis wrap the flat.
function tube_flat_n(mark) =
    mark == "R" ? [0, -1] :
    mark == "T" ? [1, 0] : [0, 0];
TUBE_FLAT_CLEAR = 0.4;
// Camera-up chord at the F mouth so the pentaprism nose clears the OD.
TUBE_FLASH_KEEP = 27.0;
TUBE_FLASH_L    = 11;

module tube_flat_waste(mark, z0, h, inset = 0) {
    n = tube_flat_n(mark);
    if (mark == "R" || mark == "T")
        translate([n.x * (PORT_PATCH / 2 - inset + 12),
                   n.y * (PORT_PATCH / 2 - inset + 12),
                   z0 + h / 2])
            cube([abs(n.x) > 0.5 ? 24 : 160,
                  abs(n.y) > 0.5 ? 24 : 160,
                  h], center = true);
}

module tube_flash_waste(mark, out_len) {
    n = port_up(mark);
    ax = cam_axis(mark);
    z1 = patch_t() + out_len;
    wn = 80;
    wt = 80;
    if (mark == "R" || mark == "T")
        hull() {
            translate([ax.x + n.x * (TUBE_FLASH_KEEP + wn / 2),
                       ax.y + n.y * (TUBE_FLASH_KEEP + wn / 2), z1 + 8])
                cube([abs(n.x) > 0.5 ? wn : wt,
                      abs(n.y) > 0.5 ? wn : wt, 16], center = true);
            translate([ax.x + n.x * (TUBE_OD / 2 + wn / 2),
                       ax.y + n.y * (TUBE_OD / 2 + wn / 2),
                       z1 - TUBE_FLASH_L])
                cube([abs(n.x) > 0.5 ? wn : wt,
                      abs(n.y) > 0.5 ? wn : wt, 2], center = true);
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

// Cookie pocket, open at the lid, stopped on the floor lip.
module port_slide_slot(mark = "") {
    u = port_up(mark);
    w = PORT_PATCH + PORT_SLOT_CLEAR;
    d = patch_t() + 0.35;
    slot_h = PORT_PATCH + PORT_FRAME + 28;
    along  = -(PORT_PATCH / 2 - PORT_SLOT_CLEAR / 2) + slot_h / 2;
    translate([u.x * along, u.y * along, d / 2 - 0.2])
        cube([abs(u.x) > 0.5 ? slot_h : w,
              abs(u.y) > 0.5 ? slot_h : w,
              d], center = true);
}

// 3 mm ring into the chassis top shelf, notched where the port faces are open.
module lid_align_lip() {
    s = BOX_XY;
    sh = sensor_shift();
    half = s / 2;
    span = PORT_PATCH + PORT_FRAME + 6;
    bite = WALL + LID_GAP + 2.5;
    difference() {
        cube([s - WALL - 2 * LID_GAP,
              s - WALL - 2 * LID_GAP,
              LID_LIP], center = true);
        cube([s - 2 * WALL - 0.6,
              s - 2 * WALL - 0.6,
              LID_LIP + 0.4], center = true);
        translate([0, -half + bite / 2, 0])
            cube([span, bite, LID_LIP + 0.6], center = true);
        translate([half - bite / 2, -sh, 0])
            cube([bite, span, LID_LIP + 0.6], center = true);
        translate([sh, half - bite / 2, 0])
            cube([span, bite, LID_LIP + 0.6], center = true);
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

    translate([0, 0, -h / 2 - PORT_SLOT_LIP - 0.05]) {
        cylinder(h = tripod_hole_h() + 0.1, d = TRIPOD_INSERT_D);
        cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
    }

    at_each_bore()
        translate([0, 0, -WALL / 2])
            cylinder(h = WALL + 2, d = TUBE_ID + 1, center = true);
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

module flange_marks(kind, patch = PORT_PATCH) {
    t = 0.8;
    ax = cam_axis(kind);
    u  = port_up(kind);
    translate([ax.x + u.x * PORT_CLAMP_R,
               ax.y + u.y * PORT_CLAMP_R,
               patch_t() - t])
        linear_extrude(t + 0.15)
            port_letter_2d(kind);
}

module chassis_port_mark(kind) {
    t = 0.8;
    ax = cam_axis(kind);
    u  = port_up(kind);
    translate([ax.x + u.x * PORT_CLAMP_R,
               ax.y + u.y * PORT_CLAMP_R, -t])
        linear_extrude(t + 0.15)
            port_letter_2d(kind);
}

module box_fastener_cuts() {
    lid_body_fastener_cuts();
    at_stem_face() {
        port_slide_slot("");
        port_clamp_screws("") port_clamp_anchor_cut();
    }
    at_reflect_face() {
        port_slide_slot("R");
        port_clamp_screws("R") port_clamp_anchor_cut();
        chassis_port_mark("R");
    }
    at_transmit_face() {
        port_slide_slot("T");
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
    at_each_bore()
        translate([0, 0, -WALL / 2])
            difference() {
                cylinder(h = WALL + 0.4, d = TUBE_ID + 1 + 2 * L, center = true);
                cylinder(h = WALL + 0.8, d = TUBE_ID + 1, center = true);
            }
}

// -----------------------------------------------------------------------------
// FXPAN wall badge — the D3-era Nikon FX body badge standing in for the X of
// the XPan wordmark, then PAN and its underline, then 65MP over the
// 13248×4912 / 2.71:1 stitch. Badge and PAN are drawn geometry traced off the
// originals; 65MP and the spec line are Futura, which ships with macOS —
// re-exporting on Linux needs the same family installed.
// layer: all | fx | word | mp | rule | spec — one STL per filament.
// -----------------------------------------------------------------------------
function fx_badge_s()   = 20.0;
function fx_pan_cap()   = 12.4;
function fx_pan_t()     = 1.15;   // monoline weight; the trace is thinner
                                  // than an inlay can survive
function fx_pan_gap()   = 2.4;    // badge → P
function fx_rule_gap()  = 1.0;    // badge → underline
function fx_word_y()    = 9.05;   // badge centre on the wall
function fx_pan_w()     = XP_N_STEM_R * fx_pan_cap() + fx_pan_t() / 2;
function fxpan_w()      = fx_badge_s() + fx_pan_gap() + fx_pan_w();
function fx_pan_cap_y() = fx_word_y() - fx_badge_s() / 2 + fx_pan_t() / 2
                          + XP_RULE_W * fx_pan_cap();

module fx_round_sq(w, r) {
    offset(r)
        offset(-r)
            square([w, w], center = true);
}

// D3 body-badge geometry, traced by rectifying the badge to a unit square.
// Every constant is a fraction of the side s; v runs 0 at the top edge to 1
// at the bottom, u left to right. Letters are wide and squat.
FXB_RING_T  = 0.057;
FXB_RING_R  = 0.098;
FXB_CAP     = 0.250;
FXB_BASE    = 0.736;
FXB_STROKE  = 0.097;
FXB_F_LEFT  = 0.150;
FXB_BAR1_T  = 0.251;
FXB_BAR1_B  = 0.346;
FXB_BAR2_T  = 0.439;
FXB_BAR2_B  = 0.534;
FXB_X_SLOPE = 0.655;   // du per unit v — both X strokes
FXB_X_LEFT  = 0.4445;
FXB_X_RIGHT = 0.8535;
FXB_X_W     = 0.104;
FXB_F_CUT   = 0.3725;  // both F bars die on this line, parallel to the
                       // backslash — that is the F↔X channel
FXB_SLOT_T  = 0.457;   // level break straight through the X crossing
FXB_SLOT_B  = 0.518;

function fxb_at(s, u, v)  = [(u - 0.5) * s, (0.5 - v) * s];
function fxb_cut(v)       = FXB_F_CUT   + FXB_X_SLOPE * (v - FXB_CAP);
function fxb_back(v)      = FXB_X_LEFT  + FXB_X_SLOPE * (v - FXB_CAP);
function fxb_fwd(v)       = FXB_X_RIGHT - FXB_X_SLOPE * (v - FXB_CAP);

module fxb_bar(s, vt, vb) {
    polygon([
        fxb_at(s, FXB_F_LEFT,  vt),
        fxb_at(s, fxb_cut(vt), vt),
        fxb_at(s, fxb_cut(vb), vb),
        fxb_at(s, FXB_F_LEFT,  vb)
    ]);
}

module fxb_f(s) {
    polygon([
        fxb_at(s, FXB_F_LEFT,              FXB_CAP),
        fxb_at(s, FXB_F_LEFT + FXB_STROKE, FXB_CAP),
        fxb_at(s, FXB_F_LEFT + FXB_STROKE, FXB_BASE),
        fxb_at(s, FXB_F_LEFT,              FXB_BASE)
    ]);
    fxb_bar(s, FXB_BAR1_T, FXB_BAR1_B);
    fxb_bar(s, FXB_BAR2_T, FXB_BAR2_B);
}

// Two shear-cut parallelograms, flat top and bottom, crossing sliced out.
module fxb_x(s) {
    difference() {
        union() {
            polygon([
                fxb_at(s, fxb_back(FXB_CAP),                FXB_CAP),
                fxb_at(s, fxb_back(FXB_CAP)  + FXB_X_W,     FXB_CAP),
                fxb_at(s, fxb_back(FXB_BASE) + FXB_X_W,     FXB_BASE),
                fxb_at(s, fxb_back(FXB_BASE),               FXB_BASE)
            ]);
            polygon([
                fxb_at(s, fxb_fwd(FXB_CAP)   - FXB_X_W,     FXB_CAP),
                fxb_at(s, fxb_fwd(FXB_CAP),                 FXB_CAP),
                fxb_at(s, fxb_fwd(FXB_BASE),                FXB_BASE),
                fxb_at(s, fxb_fwd(FXB_BASE)  - FXB_X_W,     FXB_BASE)
            ]);
        }
        polygon([
            fxb_at(s, 0.30, FXB_SLOT_T),
            fxb_at(s, 1.00, FXB_SLOT_T),
            fxb_at(s, 1.00, FXB_SLOT_B),
            fxb_at(s, 0.30, FXB_SLOT_B)
        ]);
    }
}

module nikon_fx_gold(s) {
    difference() {
        fx_round_sq(s, FXB_RING_R * s);
        fx_round_sq(s * (1 - 2 * FXB_RING_T),
                    (FXB_RING_R - FXB_RING_T) * s);
    }
    fxb_f(s);
    fxb_x(s);
}

module fxpan_badge() {
    translate([-fxpan_w() / 2 + fx_badge_s() / 2, fx_word_y()])
        nikon_fx_gold(fx_badge_s());
}

// XPAN wordmark, traced off the Hasselblad badge the same way. Fractions of
// the cap height: u runs right from the left edge, w runs down from the cap
// line. Monoline skeleton, so the weight is a free parameter.
XP_P_STEM     = 0.033;
XP_P_BOWL_R   = 0.880;
XP_P_BOWL_B   = 0.478;
XP_P_BOWL_RAD = 0.087;
XP_A_FOOT_L   = 0.815;
XP_A_APEX     = 1.283;
XP_A_FOOT_R   = 1.761;
XP_A_BAR      = 0.674;
XP_N_STEM_L   = 1.913;
XP_N_STEM_R   = 2.826;
XP_RULE_W     = 1.196;

module xp_bar(p, q, t) {
    d = q - p;
    translate(p)
        rotate(atan2(d.y, d.x))
            translate([0, -t / 2])
                square([norm(d), t]);
}

function xp_unit(p, q) = (q - p) / norm(q - p);

// Bowl path runs off to the left so its left corners fall outside the cap
// band — that squares the bars where they meet the stem.
module xp_bowl_path(hc, t) {
    r = XP_P_BOWL_RAD * hc;
    offset(r)
        offset(-r)
            polygon([[-hc,               -XP_P_BOWL_B * hc],
                     [XP_P_BOWL_R * hc,  -XP_P_BOWL_B * hc],
                     [XP_P_BOWL_R * hc,  -t / 2],
                     [-hc,               -t / 2]]);
}

module xp_diag(hc, t, u0, w0, u1, w1) {
    over = 2 * t;
    a = [u0 * hc, -w0 * hc];
    b = [u1 * hc, -w1 * hc];
    d = xp_unit(a, b);
    xp_bar(a - d * over, b + d * over, t);
}

module xpan_pan_2d(hc, t) {
    over = 2 * t;
    xl = XP_A_APEX + (XP_A_FOOT_L - XP_A_APEX) * XP_A_BAR;
    xr = XP_A_APEX + (XP_A_FOOT_R - XP_A_APEX) * XP_A_BAR;
    intersection() {
        union() {
            xp_bar([XP_P_STEM * hc, over],
                   [XP_P_STEM * hc, -hc - over], t);
            difference() {
                offset(t / 2)  xp_bowl_path(hc, t);
                offset(-t / 2) xp_bowl_path(hc, t);
            }
            xp_diag(hc, t, XP_A_APEX, 0, XP_A_FOOT_L, 1);
            xp_diag(hc, t, XP_A_APEX, 0, XP_A_FOOT_R, 1);
            xp_bar([xl * hc - t / 2, -XP_A_BAR * hc],
                   [xr * hc + t / 2, -XP_A_BAR * hc], t);
            xp_bar([XP_N_STEM_L * hc, over],
                   [XP_N_STEM_L * hc, -hc - over], t);
            xp_bar([XP_N_STEM_R * hc, over],
                   [XP_N_STEM_R * hc, -hc - over], t);
            xp_diag(hc, t, XP_N_STEM_L, 0, XP_N_STEM_R, 1);
        }
        translate([0, -hc])
            square([XP_N_STEM_R * hc + t / 2, hc]);
    }
}

module fxpan_pan() {
    hc = fx_pan_cap();
    t  = fx_pan_t();
    x0 = -fxpan_w() / 2 + fx_badge_s() + fx_pan_gap();
    translate([x0, fx_pan_cap_y()])
        xpan_pan_2d(hc, t);
    // The rule runs out from under the badge and stops flush with the N.
    rx = -fxpan_w() / 2 + fx_badge_s() + fx_rule_gap();
    translate([rx, fx_pan_cap_y() - XP_RULE_W * hc - t / 2])
        square([x0 + fx_pan_w() - rx, t]);
}

module fxpan_wall_2d(layer = "all") {
    word  = "Futura:style=Bold";
    specf = "Futura:style=Condensed Medium";
    if (layer == "all" || layer == "fx")
        fxpan_badge();
    if (layer == "all" || layer == "word")
        fxpan_pan();
    if (layer == "all" || layer == "mp")
        translate([0, -8.15])
            text("65MP", size = 6.2, font = word, spacing = 1.12,
                 halign = "center", valign = "center");
    if (layer == "all" || layer == "rule")
        translate([0, -12.95])
            square([max(46, fxpan_w()), 0.45], center = true);
    if (layer == "all" || layer == "spec")
        translate([0, -16.65])
            text("13248×4912  ·  2.71:1", size = 3.45, font = specf,
                 spacing = 1.20, halign = "center", valign = "center");
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

module chassis_blank() {
    dz  = PORT_SLOT_LIP;
    h   = BOX_Z + dz;
    out = chassis_out();
    translate([0, 0, -BOX_Z / 2 - dz])
        linear_extrude(h)
            round_rect(out, out, PORT_BOSS_R);
}

module part_chassis() {
    // Full / inner / outer always pocket every layer so the colour STLs seat.
    // SHELL=logo exports one LOGO_LAYER as a drop-in.
    layer = (SHELL == "logo") ? LOGO_LAYER : "all";
    color("SlateGray")
    if (SHELL == "logo")
        union() {
            // Body, clipped to the chassis in case a glyph ever reaches a
            // bore or a fastener. LOGO_FIT keeps it off the pocket faces.
            intersection() {
                difference() {
                    chassis_blank();
                    box_bore();
                    box_fastener_cuts();
                }
                fxpan_inlay(layer, LOGO_FIT, 0);
            }
            // Lip standing outside the wall, so the plug face is not
            // coplanar with it either. Nothing out here to clip against.
            fxpan_inlay(layer, LOGO_FIT, LOGO_PROUD, 0.4);
        }
    else
    mm_split() {
        difference() {
            chassis_blank();
            box_bore();
            box_fastener_cuts();
            // box_floor_stamp is written for a cube; feed it the XY size and
            // drop it to the real floor, which is BOX_Z deep.
            translate([0, 0, -(BOX_Z - BOX_XY) / 2])
                box_floor_stamp(fxp_tag("chassis"), BOX_XY, WALL);
            if (SHELL == "full")
                fxpan_inlay("all");
        }
        union() {
            box_lining_mask();
            if (SHELL == "outer")
                fxpan_inlay("all");
        }
    }
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

module port_tube_solid(out_len, rx = 0, ry = 0, patch = PORT_PATCH, mark = "") {
    ax = cam_axis(mark);
    difference() {
        union() {
            port_flange(patch);
            if (out_len > 0.05)
                along_cam(rx, ry, mark)
                    cylinder(h = out_len, d = TUBE_OD);
        }
        along_cam(rx, ry, mark)
            translate([0, 0, -patch_t() - 2])
                cylinder(h = patch_t() + out_len + 4, d = TUBE_ID);
        tube_flat_waste(mark, -2, patch_t() + out_len + 8, TUBE_FLAT_CLEAR);
        tube_flash_waste(mark, out_len);
        port_clamp_screws(mark) port_csk_cut();
    }
}

module part_camera_tube(out_len, rx = 0, ry = 0, mark = "") {
    p = PORT_PATCH;
    color("SlateGray")
    mm_split() {
    intersection() {
    difference() {
        union() {
            port_tube_solid(out_len, rx, ry, p, mark);
            along_cam(rx, ry, mark) {
                tube_baffles(out_len, mark);
                f_glare_mask(out_len, mark);
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
                if (out_len >= F_REV_LEN)
                    rev_lock_cuts(out_len, mark == "T" ? -90 : 180);
                f_pin_line_cut(out_len, mark == "T" ? -90 : 180);
            }
        flange_marks(mark, p);
        flange_stamp(fxp_arm_tag(mark), mark, p, patch_t(), STAMP_DEPTH, 3.4);
        tube_flash_waste(mark, out_len);
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
// stem — EL-Nikkor 180/5.6N on an M62×1 helicoid
// -----------------------------------------------------------------------------
module m62_nut(h = EL180_M62_LEN) {
    ScrewHole(EL180_M62_MAJOR, h, pitch = EL180_M62_PITCH,
              tolerance = EL180_M62_TOL)
        cylinder(h = h, d = EL180_STEM_OD);
}

// The whole stem is the cookie plus an EL180_M62_LEN female boss. There is
// no tube and no deep nut: hybrid_shift's 20 mm nut plus a 17 mm helicoid
// would put the shortest path at 207 mm and infinity out of reach. The
// bought helicoid's male bottoms on the cookie's outer face, so the lens
// flange sits at d_plate_to_flange() and the helicoid racks from there.
// Bore tapers STEM_BORE → TUBE_ID toward the plate so the lens's own cone
// is never the stop.
module part_stem() {
    z0 = patch_t();
    color("SlateGray")
    mm_split() {
        difference() {
            union() {
                port_flange(PORT_PATCH);
                translate([0, 0, z0]) {
                    hull() {
                        cylinder(h = 0.2, d = TUBE_OD);
                        translate([0, 0, 3])
                            cylinder(h = 0.2, d = EL180_STEM_OD);
                    }
                    m62_nut();
                }
            }
            translate([0, 0, -2])
                cylinder(h = patch_t() + 2.2, d1 = TUBE_ID, d2 = STEM_BORE);
            translate([0, 0, z0 - 0.1])
                cylinder(h = EL180_M62_LEN + 4, d = STEM_BORE);
            port_clamp_screws("") port_csk_cut();
            flange_stamp(fxp_tag("stem"), "", PORT_PATCH, patch_t());
        }
        union() {
            tube_lining_mask(0, m62 = EL180_M62_LEN);
            translate([0, 0, z0 - 0.2])
                cylinder(h = EL180_M62_LEN + 0.4, d = EL180_M62_MAJOR + 8);
        }
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
                        cylinder(h = hex_h, d = EL180_ADAPTER_OD, $fn = 6);
        }
        // Through-bore at the M62 minor; the hex behind the female stays
        // EL180_BARREL so the 60 mm lens barrel drops in.
        translate([0, 0, hm - overlap])
            cylinder(h = hex_h - hf + 0.4, d = EL180_BARREL);
        translate([0, 0, -0.2])
            cylinder(h = hm + hex_h + 0.4, d = EL180_BORE);
        translate([0, -EL180_ADAPTER_OD / 2 * cos(30) - 0.05,
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
    translate([0, 0, -6])
        cylinder(h = 6, d = EL180_SNOUT_D);
    cylinder(h = EL180_LENS_L, d = EL180_LENS_OD);
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
        }
        translate([0, 0, BOX_Z / 2 + ex * 0.4]) {
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW),
                           -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
            plate_stamp(fxp_tag("lid"), s, LID_T, STAMP_DEPTH, 5.0);
            difference() {
                lid_inner_ribs();
                lid_retain_keepout();
            }
        }
    }
        lid_lining_mask();
    }
}

// -----------------------------------------------------------------------------
// base and cradles — the bayonet locates, the base carries
// -----------------------------------------------------------------------------
function base_z()      = -BOX_Z / 2 - PORT_SLOT_LIP - BASE_T;
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
function cradle_lift() = d800_tripod_above();
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
                translate([0, 0, out_len + mount_stack() + ex])
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
    if (SHOW_LENS)
        color("DimGray", 0.92)
            at_stem()
                translate([0, 0, patch_t() + EL180_M62_LEN
                                 + el180_spacer_add()
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
    part_chassis();

    if (SHOW_PANELS) {
        at_stem()
            translate([0, 0, EXPLODED ? ex : 0])
                part_stem();
        at_stem()
            translate([0, 0, patch_t() + EL180_M62_LEN - EL180_HELI_MALE
                             + (EXPLODED ? ex * 1.4 : 0)])
                part_el180_adapter();
        at_reflect()
            translate([0, 0, EXPLODED ? ex : 0])
                part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");
        at_transmit()
            translate([0, 0, EXPLODED ? ex : 0])
                part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    }

    fxp_pair(show_glass = $preview,
             explode_z = EXPLODED ? (BOX_Z / 2 + 40) : 0,
             sh = sensor_shift(),
             tag = fxp_tag("tray"));

    if (SHOW_LID)
        part_lid();

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
    echo(str("FXPAN 65  |  ", BS_SIZE, "×", BS_SIZE, "×", BS_THICK,
             " 50/50 at 45°, S1 toward the lens  |  ARM_MOUNT=", ARM_MOUNT,
             " (", printed_f() ? "printed F" : "reverse ring", ")",
             "  SHELL=", SHELL));
    echo(str("path: plate→flange ", d_plate_to_flange(EL180_HELI_MIN), "..",
             d_plate_to_flange(EL180_HELI_MAX),
             " + plate→mount ", d_plate_to_mount(),
             " + flange ", FLANGE_F,
             "  =  PATH ", path_min(), "..", path_max(), " mm"));
    echo(str("infinity: EL-Nikkor f = ", EL_FOCAL, " mm lands at helicoid ",
             round(heli_at_infinity() * 10) / 10, " mm of ",
             EL180_HELI_MIN, "..", EL180_HELI_MAX,
             (path_min() <= EL_FOCAL && EL_FOCAL <= path_max())
               ? "  → in range" 
               : "  *** OUT OF RANGE — resize BOX_XY ***",
             ";  printed spacer adds ", round(el180_spacer_add() * 10) / 10,
             " mm (fixed, infinity only)"));
    echo(str("body fit: F register stands ", mount_standoff(),
             " mm off the chassis face (arm tube ", ARM_TUBE,
             " + ring ", F_REV_STACK, ", no retaining wall)",
             "  vs a D800 front panel ", d800_proud(), " mm proud of its flange",
             mount_standoff() >= d800_proud() + MOUNT_CLEAR
               ? str("  → ", round((mount_standoff() - d800_proud()) * 10) / 10,
                     " mm to twist it on")
             : mount_standoff() >= d800_proud()
               ? "  → fits, but tight; raise MOUNT_CLEAR"
               : "  *** THE BODY CANNOT GO ON — raise ARM_TUBE ***"));
    echo(str("stitch: overlap ", overlap_frac(), "  sensor_shift ",
             sensor_shift(), " mm  stitch_w ", stitch_w(), " mm  ",
             stitch_px(), "×", SENSOR_PX_H, " px  ",
             round(stitch_aspect() * 1000) / 1000, ":1  (XPan 2.708:1)  ",
             round(stitch_px() * SENSOR_PX_H / 1e5) / 10, " MP"));
    echo(str("plate clear aperture at f/", FSTOP, ": need ",
             round(need * 10) / 10, " mm, have ", round(have * 100) / 100,
             " mm in plane (", BS_SIZE, "/√2)  →  margin ",
             round((have / need - 1) * 1000) / 10, "%",
             need > have ? "   *** CLIPS — stop down or fit a bigger plate ***"
                         : ""));
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
               ? "   *** the printed mesh is 38 mm and clips the corners at every stop; fit the metal reverse ring ***"
               : "   (44 mm is the real F throat — this is the hard ceiling, not a print limit)"));
    echo(str("baffle rings that fit at f/", FSTOP, ": ", baffle_ring_count(),
             " of ", BAFFLE_RINGS,
             baffle_ring_count() == 0
               ? "  (the bundle fills the bore — nothing to print)" : ""));
    echo(str("transmit leg crosses ", BS_THICK,
             " mm of n=", BS_N, " glass at 45°: tube shortened by ",
             round(bs_t_comp() * 1000) / 1000, " mm"));
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
    else if (PART == "arm_r" || PART == "arm_r_f")
        part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");
    else if (PART == "arm_t" || PART == "arm_t_f")
        part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    else if (PART == "lid")
        part_lid();
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
    else
        assembly();
}

export_part();
