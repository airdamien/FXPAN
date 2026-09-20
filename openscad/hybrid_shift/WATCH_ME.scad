// =============================================================================
// hybrid_shift/WATCH_ME.scad  — pano L: shifted DX or FX, no tube toe
// =============================================================================
// Same stitch as hybrid. Rounded shell; three ports are C-channels
// (open at the lid, retained on three sides). The lid matches the
// shell and plugs the slot tops. Two M3s per port follow the tube
// (R/T shifted). No tube toe.
// SHELL inner = PETG lining, outer = PCTG.
// Lens −Y. Plate at origin: R → +X, T → +Y. Open this file.
// ARM_MOUNT 0 = female 52×0.75 + nut pocket; 1 = printed F-bayonet (clocked).
// F_MOUNT_CLOCK: add if the first F-print locks 90° off.
// STEM 0 = helicoid + L39 (EL-Nikkor 135). STEM 1 = female F (50 mm test).
// STEM 2 = M62 stem + bought M62 helicoid for EL-Nikkor 180/5.6N.
// STEM 3 = one-piece M62 stem, 180 seated at infinity (no helicoid, no adapter).
// F 50 uses the 54 mm camera tubes + 2 mm cookies (ARMS=1). 135/180 keep 72 / 4.
// Brace: triangle under the box + both body 1/4-20s. Tripod insert in the brace.
// F_STEM_CLOCK: add if the first F50 stem locks off the index.
// FX_MODE=1 (Customizer or ./export_hybrid_shift_fx.sh): D800 FX bores at
// sensor_shift ~11.5 mm, stitch ~59.0 mm (36% overlap). Ghost uses
// openscad/d800_body.stl (Thingiverse #4815092). Print FX tray, FX arms
// (truncated M52 mouth), and stem_el180_inf until the M62 helicoid
// lands. FX parts stamp FX + the part name (not hs_).
// =============================================================================

/* [Part] */
PART = "assembly"; // [assembly:Assembly, chassis:Chassis, stem:Stem 135, stem_f50:Stem F 50, stem_el180:Stem EL 180, stem_el180_inf:Stem EL 180 infinity, arm_r:Arm R 72 mm, arm_t:Arm T 72 mm, arm_r_s:Arm R F50, arm_t_s:Arm T F50, arm_r_sf:Arm R F50 printed F, arm_t_sf:Arm T F50 printed F, lid:Lid, display_mount:Display mount, hybrid_tray:Tray, brace:Tripod brace, shims:Shims, elnikkor_adapter:EL 135 adapter, el180_adapter:EL 180 adapter]

/* [Camera] */
FX_MODE = 0; // [0:DX D7000, 1:FX D800]
// FX_MODE=1: bores shift to 11.5 mm, ghost = ../d800_body.stl, print STLs
// from ./export_hybrid_shift_fx.sh → stls/hybrid_shift_fx/ (not hybrid_shift/).
D800_TRIPOD_ABOVE = 10.0; // mm, 1/4-20 above chassis bottom (measure yours)
D800_TRIPOD_IN    = 44;   // mm, lens axis → tripod along base (measure yours)
FX_FMOUNT_EXTRA   = 5.0;  // extra rear support behind the printed FX F-mount

/* [Stem] */
STEM = 0; // [0:EL-Nikkor 135, 1:F-mount 50, 2:EL-Nikkor 180 helicoid, 3:EL-Nikkor 180 infinity]
ARMS = 0; // [0:72 mm 135/180, 1:54 mm F 50]

include <params.scad>
include <../lib/threads.scad>
include <../lib/part_stamp.scad>
use <hybrid_tray.scad>
use <shims.scad>
use <../camera_body.scad>
use <../taking_lens.scad>
use <../f_mount_male.scad>
use <../f_mount_female.scad>
use <../pi4_body.scad>
use <../monitor/display_mount.scad>
use <../monitor/monitor.scad>

/* [View] */
SHOW_LID = 1; // [0:hide, 1:show]
SHOW_PANELS = 1; // [0:hide, 1:show]
SHOW_MONITOR = 0; // [0:hide, 1:show]
SHOW_PI = 0; // [0:hide, 1:show]
SHOW_BODIES = 0; // [0:hide, 1:D7000, 2:D800]  — use 2 for the D800 mesh
SHOW_LENS = 0; // [0:hide, 1:show]
SHOW_BRACE = 1; // [0:hide, 1:show]

/* [Body Alignment] */
// Ghost offsets in each arm's local frame. Set these while fitting the bodies;
// the final values can be copied into the body calibration afterward.
BODY_R_X = 10; // [-20:0.5:20]
BODY_R_Y = 13; // [-20:0.5:20]
BODY_R_Z = -5; // [-20:0.5:20]
BODY_T_X = -13; // [-20:0.5:20]
BODY_T_Y = 10; // [-20:0.5:20]
BODY_T_Z = -5; // [-20:0.5:20]

/* [Shell] */
SHELL = "full"; // [full:Full (one material), inner:Inner PETG, outer:Outer PCTG]
// FX wall type, one STL per color. Chassis pocket is always every layer.
LOGO_LAYER = "all"; // [all:All, fx:Nikon FX badge, word:Pan, mp:59MP, rule:Hairline, spec:Pixels]

/* [Mount] */
ARM_MOUNT = 0; // [0:reverse ring, 1:integrated F]
F_MOUNT_CLOCK = 0;

F_STEM_CLOCK = 0;
EL180_M62_PITCH = 1.0; // [0.75, 1.0]

screw_resolution = $preview ? 0.6 : 0.25;

ex = EXPLODED ? 55 : 0;
LID_T     = 6;
LID_LIP   = 3;
LID_GAP   = 0.5;   // lip ↔ chassis seat; FDM needs >0.3 on the port faces
LID_CAP   = 5;
// In from the outer corner of the 90 mm inner cube.
LID_SCREW = 5;
// Nut center below the box top. M3×20: 4 lid + 12 to nut + nut + a bit past.
LID_NUT_DROP = 12;

function printed_f()         =
    ARM_MOUNT
    || PART == "arm_r_f" || PART == "arm_t_f"
    || PART == "arm_r_sf" || PART == "arm_t_sf";
function mount_stack()       = printed_f() ? F_FMOUNT_STACK : F_REV_STACK;
function fx_mount_extra()    = FX_MODE ? FX_FMOUNT_EXTRA : 0;
function f50_kit()           =
    ARMS || STEM == 1 || PART == "stem_f50"
    || PART == "arm_r_s" || PART == "arm_t_s"
    || PART == "arm_r_sf" || PART == "arm_t_sf";
function el180_kit()         = STEM == 2 || PART == "stem_el180";
function el180_inf_kit()     = STEM == 3 || PART == "stem_el180_inf";
function el180_inf_h()       = EL180_NUT_H + EL180_HELI_MIN;
// 45° so cookie-on-bed prints without support. Starts above the U/cookie.
function el180_flare_h()     = (EL180_STEM_OD - TUBE_OD) / 2;
function el180_flare_z0()    = patch_t() + port_u_fill_t();
function patch_t()           = f50_kit() ? PORT_PATCH_T_SHORT : PORT_PATCH_T;
function stem_tube_len()     =
    ((STEM == 1 || PART == "stem_f50") ? D_LENS_TO_PLATE_F50 : D_LENS_TO_PLATE_LONG)
    - JUNCTION_BOX / 2;
function reflect_tube_len()  = D_PLATE_TO_MOUNT - mount_stack() - JUNCTION_BOX / 2;
function transmit_tube_len() = reflect_tube_len() - bs_t_comp();

module helicoid_nut(h = HELICOID_LEN) {
    ScrewHole(HELICOID_MAJOR, h, pitch = HELICOID_PITCH, tolerance = HELICOID_TOL)
        cylinder(h = h, d = HELICOID_MAJOR + 14);
}

module port_screws() {
    for (a = [45, 135, 225, 315])
        rotate([0, 0, a])
            translate([PORT_SCREW_R, 0, 0])
                children();
}

function cam_patch() = PORT_PATCH;
// Outboard cookie edge in the shift direction. FX tubes stick past the
// 90 mm plate; chord-cut that OD so the chassis can wrap the flat.
function tube_flat_n(mark) =
    mark == "R" ? [0, -1] :
    mark == "T" ? [1, 0] : [0, 0];
TUBE_FLAT_CLEAR = 0.4;
// Camera-up chord at the F-mouth so the pentaprism / flash nose clears
// the 68 mm OD. Angled back to full OD. Keep is ~flush with TUBE_ID.
TUBE_FLASH_KEEP = 31.0;
TUBE_FLASH_L    = 11;

module tube_flat_waste(mark, z0, h, inset = 0) {
    n = tube_flat_n(mark);
    if (mark == "R" || mark == "T")
        // Long along the face so the lid-side C-channel is wrapped too.
        translate([n.x * (PORT_PATCH / 2 - inset + 12),
                   n.y * (PORT_PATCH / 2 - inset + 12),
                   z0 + h / 2])
            cube([abs(n.x) > 0.5 ? 24 : 160,
                  abs(n.y) > 0.5 ? 24 : 160,
                  h], center = true);
}

// Angled chord on camera-up (port_up) at the F-mouth. Cookie-frame XY.
// Inner face of each slab sits on `dist` so the hull cannot cross the bore.
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

// Two M3s on the lid side of the tube, tracking cam_axis, so the
// plate can be screwed after it is in the slot.
module port_clamp_screws(mark = "") {
    for (side = [-1, 1]) {
        p = clamp_xy(mark, side);
        translate([p.x, p.y, 0])
            children();
    }
}

module port_flange(patch = PORT_PATCH, mark = "") {
    translate([0, 0, patch_t() / 2])
        cube([patch, patch, patch_t()], center = true);
}

module round_rect(w, h, r) {
    offset(r)
        offset(-r)
            square([w, h], center = true);
}

function chassis_shell_t() = patch_t() + PORT_RETAIN;
function chassis_out()     = JUNCTION_BOX + 2 * chassis_shell_t();
function port_u_fill_t()   = PORT_RETAIN - 0.25;

// Fills the chassis U so the cookie is flush with the cube wall.
// Stops short of LID_CAP so the lid plug still seats.
module port_u_fill(mark = "") {
    ax = cam_axis(mark);
    u  = port_up(mark);
    t  = port_u_fill_t();
    d  = TUBE_OD + 0.2;
    along = PORT_PATCH / 2 - LID_CAP - 0.6;
    translate([0, 0, patch_t() + t / 2])
        intersection() {
            cube([PORT_PATCH - 0.6, PORT_PATCH - 0.6, t], center = true);
            hull() {
                translate([ax.x, ax.y, 0])
                    cylinder(h = t, d = d, center = true);
                translate([ax.x + u.x * along, ax.y + u.y * along, 0])
                    cylinder(h = t, d = d, center = true);
            }
        }
}

// 3 mm ring into the chassis top shelf (82 mm OD, 74 mm ID). Notched at
// the three port faces where the ledge is open — corners + blank −X only.
module lid_align_lip() {
    s = JUNCTION_BOX;
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

// Outer wall keeps the plate in; tube slides down the U.
module port_retain_cut(mark = "") {
    ax = cam_axis(mark);
    u  = port_up(mark);
    d  = TUBE_OD + 1.0;
    h  = PORT_RETAIN + 2.4;
    difference() {
        translate([ax.x, ax.y, patch_t() + PORT_RETAIN / 2])
            hull() {
                cylinder(h = h, d = d, center = true);
                translate([u.x * (PORT_PATCH / 2 + 24),
                           u.y * (PORT_PATCH / 2 + 24), 0])
                    cylinder(h = h, d = d, center = true);
            }
        // Leave chassis meat past the cookie edge so it wraps the flat.
        tube_flat_waste(mark, patch_t() - 1, h + 4);
    }
}
function hs_tag(name) = str("hs_", name);
// FX reprints (chassis, arms, lid, brace, tray, stem_el180_inf). DX 135 stem stays hs_.
function kit_tag(dx, fx) = fx_mode() ? fx : str("hs_", dx);
function hs_arm_tag(mark) =
    fx_mode()
        ? str("FX ARM ", mark)
        : str("hs_arm_", mark == "T" ? "t" : "r",
              f50_kit() ? "s" : "",
              printed_f() ? "f" : "");

module mm_split() {
    if (SHELL == "inner")
        intersection() { children(0); children(1); }
    else if (SHELL == "outer")
        difference() { children(0); children(1); }
    else
        children(0);
}

// Engraved on the camera-side face (print flange on the bed),
// between the two lid-side clamp screws.
// kind "R": local −X is world +Z. kind "T": local −Y is world +Z.
module port_letter_2d(kind) {
    module stamp(letter) {
        translate([-4.6, 0])
            polygon([[0, 2.6], [-1.7, -1.4], [1.7, -1.4]]);
        translate([3.2, 0])
            text(letter, size = 5.2, font = "Liberation Sans:style=Bold",
                 halign = "center", valign = "center");
        if (fx_mode())
            translate([3.2, -5.6])
                text("FX", size = 3.4, font = "Liberation Sans:style=Bold",
                     halign = "center", valign = "center");
    }
    if (kind == "R")
        rotate(90)
            stamp("R");
    else
        rotate(180)
            stamp("T");
}

// Engraved on the camera-side face (print flange on the bed),
// between the two lid-side clamp screws.
module flange_marks(kind, patch = PORT_PATCH) {
    t = 0.8;
    ax = cam_axis(kind);
    u  = port_up(kind);
    translate([ax.x + u.x * PORT_CLAMP_R,
               ax.y + u.y * PORT_CLAMP_R,
               patch_t() + port_u_fill_t() - t])
        linear_extrude(t + 0.15)
            port_letter_2d(kind);
}

// Same marks on the chassis pocket, between the clamp holes.
module chassis_port_mark(kind) {
    t = 0.8;
    ax = cam_axis(kind);
    u  = port_up(kind);
    translate([ax.x + u.x * PORT_CLAMP_R,
               ax.y + u.y * PORT_CLAMP_R,
               -t])
        linear_extrude(t + 0.15)
            port_letter_2d(kind);
}

module hex_nut_cut() {
    cylinder(h = PORT_NUT_T + 0.2, d = PORT_NUT_AF / cos(30), $fn = 6);
}

module at_stem_face() {
    translate([0, -JUNCTION_BOX / 2, 0])
        rotate([90, 0, 0])
            children();
}

module at_reflect_face() {
    translate([JUNCTION_BOX / 2, 0, 0])
        rotate([0, 90, 0])
            children();
}

module at_transmit_face() {
    translate([0, JUNCTION_BOX / 2, 0])
        rotate([-90, 0, 0])
            children();
}

// Parts: cookie sits in the U-frame on the cube face.
module at_stem() {
    at_stem_face()
        children();
}

module at_reflect() {
    at_reflect_face()
        children();
}

module at_transmit() {
    at_transmit_face()
        children();
}

module at_each_port() {
    at_stem() children();
    at_reflect() children();
    at_transmit() children();
}

module at_each_bore() {
    at_stem_face() children();
    at_reflect_face()
        translate([cam_axis("R").x, cam_axis("R").y, 0])
            children();
    at_transmit_face()
        translate([cam_axis("T").x, cam_axis("T").y, 0])
            children();
}

module box_bore() {
    s = JUNCTION_BOX;

    translate([0, 0, WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, s - WALL], center = true);

    translate([0, 0, s / 2 - WALL / 2])
        cube([s - 2 * WALL, s - 2 * WALL, WALL + 0.2], center = true);

    translate([0, 0, s / 2 - LID_LIP / 2])
        cube([s - WALL, s - WALL, LID_LIP + 0.1], center = true);

    mirror_groove_cutouts();

    translate([0, 0, -s / 2 - PORT_SLOT_LIP - 0.05]) {
        cylinder(h = tripod_hole_h() + 0.1, d = TRIPOD_INSERT_D);
        cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
    }

    at_each_bore()
        translate([0, 0, -WALL / 2])
            cylinder(h = WALL + 2, d = TUBE_ID + 1, center = true);
}

// M3 hex in each top corner. Side slot into the chamber; roof stays
// solid so the lid screw can clamp.
module lid_body_fastener_cuts() {
    s = JUNCTION_BOX;
    nut_z = s / 2 - LID_NUT_DROP;
    module nut_hex() {
        rotate([0, 0, 30])
            cylinder(h = PORT_NUT_T + 0.25,
                     d = PORT_NUT_AF / cos(30), $fn = 6, center = true);
    }
    for (sx = [-1, 1], sy = [-1, 1]) {
        px = sx * (s / 2 - LID_SCREW);
        py = sy * (s / 2 - LID_SCREW);
        translate([px, py, nut_z - 4])
            cylinder(h = s / 2 - nut_z + 5, d = PORT_SCREW_D);
        hull() {
            translate([px, py, nut_z])
                nut_hex();
            translate([sx * (s / 2 - WALL - 2.5),
                       sy * (s / 2 - WALL - 2.5), nut_z])
                nut_hex();
        }
    }
}

module box_fastener_cuts() {
    lid_body_fastener_cuts();
    at_stem_face() {
        port_slide_slot("");
        port_retain_cut("");
        port_clamp_screws("") {
            translate([0, 0, -WALL - 0.2])
                cylinder(h = WALL + 0.6, d = PORT_SCREW_D);
            translate([0, 0, -WALL - 0.05])
                hex_nut_cut();
        }
    }
    at_reflect_face() {
        port_slide_slot("R");
        port_retain_cut("R");
        port_clamp_screws("R") {
            translate([0, 0, -WALL - 0.2])
                cylinder(h = WALL + 0.6, d = PORT_SCREW_D);
            translate([0, 0, -WALL - 0.05])
                hex_nut_cut();
        }
        chassis_port_mark("R");
    }
    at_transmit_face() {
        port_slide_slot("T");
        port_retain_cut("T");
        port_clamp_screws("T") {
            translate([0, 0, -WALL - 0.2])
                cylinder(h = WALL + 0.6, d = PORT_SCREW_D);
            translate([0, 0, -WALL - 0.05])
                hex_nut_cut();
        }
        chassis_port_mark("T");
    }
}

module box_lining_mask() {
    s = JUNCTION_BOX;
    L = INNER_LINING;
    difference() {
        translate([0, 0, (WALL - L) / 2])
            cube([s - 2 * (WALL - L),
                  s - 2 * (WALL - L),
                  s - (WALL - L)], center = true);
        translate([0, 0, WALL / 2])
            cube([s - 2 * WALL, s - 2 * WALL, s - WALL + 0.4], center = true);
    }
    // Floor lining sits below the cavity so the boolean keeps it as inner.
    // Top FLOOR_SKIN of the chamber floor stays outer (PCTG).
    translate([0, 0, -s / 2 + WALL - FLOOR_SKIN - (L - FLOOR_SKIN) / 2])
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

// Name on the blank −X wall. DX D12600 (7000×1.8); FX is the D3-era
// Nikon FX badge (gold ring + geometric FX) standing in for the X of
// the XPan wordmark, then PAN + its underline, then 59MP over the
// 12070×4912 / 2.46:1 stitch. Badge and PAN are drawn geometry; 59MP
// and the spec line are Futura, which ships with macOS — re-exporting
// on Linux needs the same family installed.
// layer: all | fx | word | mp | rule | spec — separate STLs for colors.
function fx_badge_s()   = 20.0;
// XPan sets PAN at 0.61 of the X; the badge stands in for the X here.
function fx_pan_cap()   = 12.4;
// Monoline weight. XPan draws 0.076 cap, which lands under 1 mm and will
// not survive as an inlay, so this carries the badge ring weight instead.
function fx_pan_t()     = 1.15;
function fx_pan_gap()   = 2.4;  // badge → P
function fx_rule_gap()  = 1.0;  // badge → underline
function fx_word_y()    = 9.05; // badge centre on the wall
function fx_pan_w()     = XP_N_STEM_R * fx_pan_cap() + fx_pan_t() / 2;
function fxpan_w()      = fx_badge_s() + fx_pan_gap() + fx_pan_w();
// Drop the rule onto the badge foot, then hang the cap line off it.
function fx_pan_cap_y() = fx_word_y() - fx_badge_s() / 2 + fx_pan_t() / 2
                          + XP_RULE_W * fx_pan_cap();

module fx_round_sq(w, r) {
    offset(r)
        offset(-r)
            square([w, w], center = true);
}

// D3 body-badge geometry, traced off the pin photo by rectifying the
// badge to a unit square. Every constant is a fraction of the side s;
// v runs 0 at the top edge to 1 at the bottom, u left to right.
// Letters are wide and squat: 71% of the side across, 49% tall.
FXB_RING_T  = 0.057;  // ring stroke
FXB_RING_R  = 0.098;  // outer corner radius
FXB_CAP     = 0.250;  // cap line
FXB_BASE    = 0.736;  // baseline
FXB_STROKE  = 0.097;  // letter stroke
FXB_F_LEFT  = 0.150;  // F stem, left edge
FXB_BAR1_T  = 0.251;  // F top bar
FXB_BAR1_B  = 0.346;
FXB_BAR2_T  = 0.439;  // F middle bar
FXB_BAR2_B  = 0.534;
FXB_X_SLOPE = 0.655;  // du per unit v — both X strokes, ~56.8° off level
FXB_X_LEFT  = 0.4445; // backslash, left edge at the cap line
FXB_X_RIGHT = 0.8535; // forward slash, right edge at the cap line
FXB_X_W     = 0.104;  // horizontal width of one X stroke
FXB_F_CUT   = 0.3725; // both F bars die on this one line, parallel to
                      // the backslash — that is the F↔X channel
FXB_SLOT_T  = 0.457;  // level break straight through the X crossing
FXB_SLOT_B  = 0.518;

function fxb_at(s, u, v)  = [(u - 0.5) * s, (0.5 - v) * s];
function fxb_cut(v)       = FXB_F_CUT   + FXB_X_SLOPE * (v - FXB_CAP);
function fxb_back(v)      = FXB_X_LEFT  + FXB_X_SLOPE * (v - FXB_CAP);
function fxb_fwd(v)       = FXB_X_RIGHT - FXB_X_SLOPE * (v - FXB_CAP);

// One F bar: square on the stem, mitred where the channel starts.
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

// Gold of the D3 FX body badge: ring + letters. Black field is chassis.
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

// XPAN wordmark, traced off the Hasselblad badge the same way as the FX
// pin. Fractions of the cap height: u runs right from the left edge, w
// runs down from the cap line. Monoline skeleton, so the weight is a
// free parameter (fx_pan_t) rather than part of the trace.
XP_P_STEM     = 0.033; // P stem, centreline
XP_P_BOWL_R   = 0.880; // P bowl, right centreline
XP_P_BOWL_B   = 0.478; // P bowl, bottom centreline
XP_P_BOWL_RAD = 0.087; // squarish bowl corner, on the centreline
XP_A_FOOT_L   = 0.815;
XP_A_APEX     = 1.283;
XP_A_FOOT_R   = 1.761;
XP_A_BAR      = 0.674; // A crossbar, sits low
XP_N_STEM_L   = 1.913;
XP_N_STEM_R   = 2.826;
XP_RULE_W     = 1.196; // underline centreline, below the cap line

// Monoline stroke with butt ends; the cap band squares them off.
module xp_bar(p, q, t) {
    d = q - p;
    translate(p)
        rotate(atan2(d.y, d.x))
            translate([0, -t / 2])
                square([norm(d), t]);
}

function xp_unit(p, q) = (q - p) / norm(q - p);

// Bowl path runs off to the left so its left corners fall outside the
// cap band — that squares the bars where they meet the stem.
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

// PAN: cap line at y = 0, baseline at y = -hc, left edge at x = 0.
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

module d12600_2d(layer = "all") {
    if (fx_mode()) {
        word = "Futura:style=Bold";
        specf = "Futura:style=Condensed Medium";
        if (layer == "all" || layer == "fx")
            fxpan_badge();
        if (layer == "all" || layer == "word")
            fxpan_pan();
        if (layer == "all" || layer == "mp")
            translate([0, -8.15])
                text("59MP", size = 6.2, font = word, spacing = 1.12,
                     halign = "center", valign = "center");
        if (layer == "all" || layer == "rule")
            translate([0, -12.95])
                square([max(46, fxpan_w()), 0.45], center = true);
        if (layer == "all" || layer == "spec")
            translate([0, -16.65])
                text("12070×4912  ·  2.46:1", size = 3.45, font = specf,
                     spacing = 1.20, halign = "center", valign = "center");
    } else if (layer == "all" || layer == "word") {
        text("D12600", size = 12, font = "Liberation Sans:style=Bold",
             halign = "center", valign = "center");
    }
}

// grow  — swell the footprint and deepen the floor (plug interference)
// proud — start this far outside the wall face
// deep  — depth below the wall face, so the pocket keeps its own depth
//         whatever the plugs do
module d12600_inlay(layer = "all", grow = 0, proud = 0.05,
                    deep = MARK_DEPTH + 0.10) {
    out = chassis_out();
    translate([-out / 2 - proud, 0, 2])
        rotate([90, 0, -90])
            mirror([0, 0, 1])
                linear_extrude(proud + deep + grow)
                    offset(0.02 + grow)
                        d12600_2d(layer);
}

module tube_baffle_tooth() {
    rotate_extrude()
        polygon([
            [TUBE_ID / 2 - 0.02, 0],
            [TUBE_ID / 2 - BAFFLE_H, BAFFLE_H],
            [TUBE_ID / 2 - 0.02, BAFFLE_H]
        ]);
}

module tube_baffles(out_len) {
    z0 = 8;
    z1 = out_len - (printed_f() ? F_PEG_H + MASK_T + 1.2 : F_REV_LEN + 1.2);
    if (z1 > z0 + BAFFLE_H)
        for (z = [z0 : BAFFLE_PITCH : z1 - BAFFLE_H])
            translate([0, 0, z])
                tube_baffle_tooth();
}

module f_glare_mask(out_len, mark) {
    roll = mark == "T" ? 180 : 90;
    z = printed_f() ? out_len - F_PEG_H - MASK_T : out_len - F_REV_LEN - MASK_T;
    // Span the 52 mm bore so the plate is fused to the wall (FX window
    // is wider than F_BORE, so a F_BORE disk was two loose slivers).
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

module tube_lining_mask(out_len, rx = 0, ry = 0, mark = "", hel = 0) {
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
    // Inner PETG owns threaded zones; PCTG outer is nut-seat meat only.
    if (hel > 0) {
        z0 = patch_t() + out_len - 0.2;
        translate([ax.x, ax.y, z0]) {
            cylinder(h = hel + 0.4, d = HELICOID_MAJOR + 2 * L);
            difference() {
                cylinder(h = 2.4, d = TUBE_ID + 2 * L);
                translate([0, 0, -0.4])
                    cylinder(h = 3.2, d = HELICOID_MAJOR - 0.4);
            }
        }
    }
    if (!printed_f() && mark != "") {
        z0 = patch_t() + out_len - F_REV_LEN - 0.2;
        translate([ax.x, ax.y, z0])
            cylinder(h = F_REV_LEN + 0.6, d = F_REV_MAJOR + 2 * L + 0.4);
    }
    if (printed_f())
        along_cam(rx, ry, mark)
            translate([0, 0, out_len])
                f_mount_path_liner(L);
    if (hel == 0 && mark != "")
        along_cam(rx, ry, mark) {
            tube_baffles(out_len);
            f_glare_mask(out_len, mark);
        }
}

module lid_lining_mask() {
    s = JUNCTION_BOX;
    L = INNER_LINING;
    translate([0, 0, s / 2 + ex * 0.4])
        translate([0, 0, (-40 + L) / 2])
            cube([s + 4, s + 4, 40 + L], center = true);
}

module chassis_blank() {
    s   = JUNCTION_BOX;
    dz  = PORT_SLOT_LIP;
    h   = s + dz;
    out = chassis_out();
    r   = PORT_BOSS_R;
    translate([0, 0, -s / 2 - dz])
        linear_extrude(h)
            round_rect(out, out, r);
}

module part_junction() {
    // Full / inner / outer always pocket every layer so the color STLs seat.
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
                d12600_inlay(layer, LOGO_FIT, 0);
            }
            // Lip standing outside the wall, so the plug face is not
            // coplanar with it either. Nothing out here to clip against.
            d12600_inlay(layer, LOGO_FIT, LOGO_PROUD, 0.4);
        }
    else
    mm_split() {
        difference() {
            chassis_blank();
            box_bore();
            box_fastener_cuts();
            box_floor_stamp(kit_tag("chassis", "FX CHASSIS"), JUNCTION_BOX, WALL);
            if (SHELL == "full")
                d12600_inlay("all");
        }
        union() {
            box_lining_mask();
            if (SHELL == "outer")
                d12600_inlay("all");
        }
    }
}

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

module port_tube_solid(out_len, rx = 0, ry = 0, patch = PORT_PATCH, mark = "") {
    ax = cam_axis(mark);
    difference() {
        union() {
            port_flange(patch, mark);
            port_u_fill(mark);
            if (out_len > 0.05)
                along_cam(rx, ry, mark)
                    cylinder(h = out_len, d = TUBE_OD);
            if (out_len > 0.05 && (rx != 0 || ry != 0))
                translate([ax.x, ax.y, patch_t()])
                    hull() {
                        cylinder(h = 0.2, d = TUBE_OD);
                        rotate([rx, ry, 0])
                            cylinder(h = 0.2, d = TUBE_OD);
                    }
        }
        along_cam(rx, ry, mark)
            translate([0, 0, -patch_t() - 2])
                cylinder(h = patch_t() + out_len + 4, d = TUBE_ID);
        tube_flat_waste(mark, -2, patch_t() + out_len + 8, TUBE_FLAT_CLEAR);
        tube_flash_waste(mark, out_len);
        port_clamp_screws(mark) {
            translate([0, 0, -1])
                cylinder(h = patch_t() + port_u_fill_t() + 2, d = PORT_SCREW_D);
            translate([0, 0, patch_t() + port_u_fill_t() - PORT_HEAD_H])
                cylinder(h = PORT_HEAD_H + 0.4, d = PORT_HEAD_D);
        }
    }
}

module m62_nut(h = EL180_NUT_H) {
    ScrewHole(EL180_M62_MAJOR, h, pitch = EL180_M62_PITCH,
              tolerance = EL180_M62_TOL)
        cylinder(h = h, d = EL180_STEM_OD);
}

module part_stem() {
    color("SlateGray")
    mm_split() {
        difference() {
            union() {
                port_tube_solid(stem_tube_len());
                translate([0, 0, patch_t() + stem_tube_len()])
                    helicoid_nut();
            }
            flange_stamp(hs_tag("stem"), "", PORT_PATCH, patch_t());
        }
        tube_lining_mask(stem_tube_len(), hel = HELICOID_LEN);
    }
}

// Female M62×1 nut on the 135-style cookie. Bought M62 helicoid (17–31 mm)
// screws in; until it arrives, print el180_adapter at the collapsed length.
module part_stem_el180() {
    z0 = patch_t() + stem_tube_len();
    color("SlateGray")
    mm_split() {
        difference() {
            union() {
                port_tube_solid(stem_tube_len());
                translate([0, 0, z0]) {
                    hull() {
                        cylinder(h = 0.2, d = TUBE_OD);
                        translate([0, 0, 4])
                            cylinder(h = 0.2, d = EL180_STEM_OD);
                    }
                    m62_nut();
                }
            }
            translate([0, 0, -2])
                cylinder(h = z0 + EL180_NUT_H + 4, d = TUBE_ID);
            flange_stamp(hs_tag("stem_el180"), "", PORT_PATCH, patch_t());
        }
        union() {
            tube_lining_mask(stem_tube_len());
            translate([0, 0, z0 - 0.2])
                cylinder(h = EL180_NUT_H + 0.4, d = EL180_M62_MAJOR + 8);
        }
    }
}

// One piece, 180 flange where the collapsed helicoid would put it. No printed
// male, no adapter. Swap for stem_el180 when the M62 helicoid lands.
// 45° flare from the 68 mm tube once it has cleared the cookie/U — cookie
// stays 90 mm, chassis U still sees 68 mm, boss prints without support.
module part_stem_el180_inf() {
    z0 = patch_t() + stem_tube_len();
    bh = el180_inf_h();
    hf = EL180_M62_LEN;
    fz = el180_flare_z0();
    fh = el180_flare_h();
    h82 = z0 + bh - fz - fh;
    color("SlateGray")
    mm_split() {
        difference() {
            union() {
                port_tube_solid(stem_tube_len());
                translate([0, 0, fz]) {
                    hull() {
                        cylinder(h = 0.2, d = TUBE_OD);
                        translate([0, 0, fh])
                            cylinder(h = 0.2, d = EL180_STEM_OD);
                    }
                    translate([0, 0, fh])
                        ScrewHole(EL180_M62_MAJOR, hf, pitch = EL180_M62_PITCH,
                                  tolerance = EL180_M62_TOL,
                                  position = [0, 0, h82 - hf])
                            cylinder(h = h82, d = EL180_STEM_OD);
                }
            }
            translate([0, 0, -2])
                cylinder(h = z0 + 2.2, d = TUBE_ID);
            translate([0, 0, z0 - 0.2])
                cylinder(h = bh - hf + 0.4, d = EL180_BARREL);
            flange_stamp(kit_tag("el180_inf", "FX STEM 180 INF"),
                         "", PORT_PATCH, patch_t());
        }
        union() {
            tube_lining_mask(stem_tube_len());
            translate([0, 0, z0 - 0.2])
                cylinder(h = bh + 0.4, d = EL180_M62_MAJOR + 8);
        }
    }
}

module part_stem_f50() {
    t = STEM_F50_PATCH;
    color("SlateGray")
    difference() {
        union() {
            translate([0, 0, t / 2])
                cube([PORT_PATCH, PORT_PATCH, t], center = true);
            translate([0, 0, t])
                f_mount_female(clock = F_STEM_CLOCK, od = TUBE_OD, back = 0);
        }
        translate([0, 0, -1])
            cylinder(h = t + f_fem_h(0) + 2, d = TUBE_ID);
        port_clamp_screws("")
            translate([0, 0, -1])
                cylinder(h = t + 2, d = PORT_SCREW_D);
        flange_stamp(hs_tag("stem_f50"), "", PORT_PATCH, t);
    }
}

module stem_chosen() {
    if (STEM == 1)
        part_stem_f50();
    else if (el180_inf_kit())
        part_stem_el180_inf();
    else if (el180_kit())
        part_stem_el180();
    else
        part_stem();
}

function stem_label() =
    STEM == 1 ? "F 50" : STEM == 2 ? "EL 180 helicoid"
    : STEM == 3 ? "EL 180 infinity" : "EL 135";

function el180_adapter_h() = EL180_ADAPTER_MALE + EL180_HELI_MIN;

module part_elnikkor_adapter() {
    h1 = EL_M42_LEN;
    h2 = EL_ADAPTER_HEX;
    h3 = EL_M39_LEN;
    color("SlateGray")
    difference() {
        union() {
            ScrewThread(HELICOID_MAJOR, h1, pitch = HELICOID_PITCH,
                        tolerance = HELICOID_TOL);
            translate([0, 0, h1])
                cylinder(h = h2, d = EL_ADAPTER_OD, $fn = 6);
            translate([0, 0, h1 + h2])
                ScrewHole(EL_M39_MAJOR, h3, pitch = EL_M39_PITCH,
                          tolerance = EL_M39_TOL)
                    cylinder(h = h3, d = EL_ADAPTER_OD);
        }
        translate([0, 0, -0.2])
            cylinder(h = h1 + h2 + h3 + 0.4, d = EL_BORE);
        translate([0, -(EL_ADAPTER_OD + EL_BORE) / 4 - 0.8,
                   h1 + h2 + h3 - STAMP_DEPTH])
            part_stamp_stack_cut(hs_tag("elnikkor"), size = 2.2);
    }
    if ($preview && !SHOW_LENS)
        color("DimGray", 0.45)
            translate([0, 0, h1 + h2 + h3])
                cylinder(h = 28, d = 47.5);
}

module part_el180_adapter() {
    hm = EL180_ADAPTER_MALE;
    hb = EL180_HELI_MIN;
    hf = EL180_M62_LEN;
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
        // Through-bore matches the M62 minor so the male is not a 52 mm stop.
        // Hex behind the female stays EL180_BARREL for the 60 mm lens barrel.
        translate([0, 0, hm - overlap])
            cylinder(h = hex_h - hf + 0.4, d = EL180_BARREL);
        translate([0, 0, -0.2])
            cylinder(h = hm + hex_h + 0.4, d = EL180_BORE);
        translate([0, -EL180_ADAPTER_OD / 2 * cos(30) - 0.05,
                   hm + hb * 0.55])
            rotate([90, 0, 0])
                part_stamp_stack_cut(hs_tag("el180"), size = 2.2);
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

// DX: full-height V from f_mount_male.scad (unchanged). FX: truncated tooth
// plus clearance on the major so the reverse ring sits on its flanks.
module hs_f_rev_thread_cut(h = undef) {
    _h = is_undef(h) ? F_REV_LEN + 0.3 : h;
    if (fx_mode())
        ScrewThread(F_REV_MAJOR + F_REV_CLEAR, _h,
                    pitch = F_REV_PITCH,
                    tolerance = 0,
                    tooth_height = F_REV_TOOTH,
                    tooth_angle = 30);
    else
        f_rev_thread_cut(h);
}

module part_camera_tube(out_len, rx = 0, ry = 0, mark = "") {
    p = cam_patch();
    color("SlateGray")
    mm_split() {
    intersection() {
    difference() {
        union() {
            port_tube_solid(out_len, rx, ry, p, mark);
            along_cam(rx, ry, mark) {
                tube_baffles(out_len);
                f_glare_mask(out_len, mark);
            }
            if (printed_f() && SHELL != "full")
                along_cam(rx, ry, mark)
                    translate([0, 0, out_len])
                        f_mount_path_liner(INNER_LINING);
        }
        if (!printed_f())
            along_cam(rx, ry, mark) {
                translate([0, 0, max(out_len - F_REV_LEN, -patch_t())])
                    hs_f_rev_thread_cut();
                if (fx_mode())
                    translate([0, 0, out_len - F_REV_LEAD])
                        cylinder(h = F_REV_LEAD + 0.1,
                                 d1 = f_rev_minor(),
                                 d2 = f_rev_minor() + 2 * F_REV_LEAD);
                if (out_len >= F_REV_LEN) {
                    rev_lock_cuts(out_len, mark == "T" ? -90 : 180);
                    f_pin_line_cut(out_len, mark == "T" ? -90 : 180);
                } else
                    f_pin_line_cut(out_len, mark == "T" ? -90 : 180);
            }
        if (mark != "")
            flange_marks(mark, p);
        if (mark != "")
            flange_stamp(hs_arm_tag(mark), mark, p, patch_t(),
                         STAMP_DEPTH, fx_mode() ? 3.4 : 2.8);
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
                                        peg_face = (SHELL == "full" ? 0
                                                    : INNER_LINING),
                                        back_extra = fx_mount_extra());
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

module part_lid() {
    s   = JUNCTION_BOX;
    out = chassis_out();
    r   = PORT_BOSS_R;
    color("DarkSlateGray")
    mm_split() {
    difference() {
        union() {
            translate([0, 0, s / 2 + ex * 0.4]) {
                // Flat cap; align_lip seats in the chassis 3 mm shelf.
                linear_extrude(LID_T)
                    round_rect(out, out, r);
                translate([0, 0, -LID_LIP / 2 + 0.01])
                    lid_align_lip();
                lid_retain_tabs(lip = LID_LIP);
                display_lid_bosses(LID_T);
            }
        }
        translate([0, 0, s / 2 + ex * 0.4]) {
            for (x = [-1, 1], y = [-1, 1])
                translate([x * (s / 2 - LID_SCREW), y * (s / 2 - LID_SCREW), -LID_LIP - 1])
                    cylinder(h = LID_T + LID_LIP + 2, d = 3.2);
            display_lid_cuts(LID_T, LID_LIP);
            plate_stamp(kit_tag("lid", "FX LID"), s, LID_T,
                         STAMP_DEPTH, fx_mode() ? 5.0 : STAMP_SIZE);
            difference() {
                lid_inner_ribs();
                display_lid_pad_keepout();
                lid_retain_keepout();
            }
        }
    }
        lid_lining_mask();
    }
}

module ghost_body_at(mark = "") {
    if ($preview && SHOW_GHOSTS)
        color("black", 0.12)
            along_cam(0, 0, mark)
                translate([0, 0, D_PLATE_TO_MOUNT - JUNCTION_BOX / 2
                                 + 15 + BODY_D / 2 + ex])
                    cube([BODY_W * 0.8, BODY_H * 0.7, BODY_D], center = true);
}

module taking_lens_at() {
    if (SHOW_LENS)
        color("DimGray", 0.92)
            at_stem()
                if (STEM == 1)
                    translate([0, 0, STEM_F50_PATCH + stem_tube_len() + f_fem_h(0)
                                     + (EXPLODED ? ex * 1.4 : 0)])
                        f50_ghost();
                else if (el180_kit() || el180_inf_kit())
                    translate([0, 0, patch_t() + stem_tube_len()
                                     + EL180_NUT_H + EL180_HELI_MIN
                                     + (EXPLODED ? ex * 1.4 : 0)])
                        el180_ghost();
                else
                    translate([0, 0, patch_t() + stem_tube_len() + HELICOID_LEN
                                     + EL_M42_LEN + EL_ADAPTER_HEX + EL_M39_LEN
                                     + (EXPLODED ? ex * 1.4 : 0)])
                        taking_lens();
}

function show_bodies() = SHOW_BODIES > 0;
// which: 1 D7000, 2 D800. SHOW_BODIES=1 → D7000, =2 → D800.
// FX_MODE=1 with SHOW_BODIES=1 also gets D800 (FX preview).
function body_which() =
    SHOW_BODIES >= 2 ? 2
    : (SHOW_BODIES == 1 && fx_mode()) ? 2
    : 1;

function body_shift_x(mark) = mark == "T" ? BODY_T_X : BODY_R_X;
function body_shift_y(mark) = mark == "T" ? BODY_T_Y : BODY_R_Y;
function body_shift_z(mark) = mark == "T" ? BODY_T_Z : BODY_R_Z;

module camera_body_at(out_len, rx = 0, ry = 0, roll = 0, mark = "") {
    if (show_bodies())
        color("DimGray", 0.92)
            along_cam(rx, ry, mark)
                translate([0, 0, out_len + mount_stack() + ex])
                    translate([body_shift_x(mark),
                               body_shift_y(mark),
                               body_shift_z(mark)])
                        camera_body(roll, which = body_which());
}

// Both bodies upright (world +Z = camera top). R was −90 (upside down).
function body_roll_r() = 90;
function body_roll_t() = 180;

function brace_cam_d() = D_PLATE_TO_MOUNT + cam_tripod_in();
function brace_q_xy() =
    let (r = brace_r_xy(), t = brace_t_xy(),
         u = (t - r) / norm(t - r),
         p = r + u * BRACE_RT_ALONG)
        p * (1 - BRACE_RT_INSET / norm(p));
function brace_web_pts() =
    [[0, 0], brace_r_xy(), brace_q_xy(), brace_t_xy()];
function brace_r_xy() = [brace_cam_d(), -sensor_shift()];
function brace_t_xy() = [sensor_shift(), brace_cam_d()];
function brace_tripod_xy() =
    let (r = brace_r_xy(), t = brace_t_xy())
        [(r.x + t.x) / 3, (r.y + t.y) / 3];
function brace_cam_lift() = BRACE_CAM_LIFT;
function brace_stamp_xy() =
    let (r = brace_r_xy(), t = brace_t_xy(),
         m = [(r.x + t.x) / 2, (r.y + t.y) / 2],
         n = m / norm(m))
        [m.x - n.x * 10, m.y - n.y * 10];

module brace_hex_grid_2d() {
    cell = BRACE_HEX_CELL;
    for (j = [-2:22], i = [-2:22])
        translate([(i + (j % 2) * 0.5) * cell, j * cell * sin(60)])
            rotate(30)
                circle(d = BRACE_HEX_D, $fn = 6);
}

module brace_hex_cuts_2d() {
    r = brace_r_xy();
    t = brace_t_xy();
    q = brace_tripod_xy();
    s = brace_stamp_xy();
    intersection() {
        difference() {
            offset(-1.8)
                offset(BRACE_WEB / 2)
                    polygon(brace_web_pts());
            translate([0, 0])
                circle(d = BRACE_PAD_D + 4);
            translate(r)
                circle(d = BRACE_PAD_D + 4);
            translate(t)
                circle(d = BRACE_PAD_D + 4);
            translate(q)
                circle(d = BRACE_PAD_D + 4);
            translate(s)
                rotate(135)
                    square([78, 10], center = true);
        }
        brace_hex_grid_2d();
    }
}

module brace_slot_2d(p) {
    a = atan2(p.y, p.x);
    translate(p)
        rotate(a)
            hull() {
                translate([-BRACE_SLOT_L / 2, 0])
                    circle(d = BRACE_SLOT_W);
                translate([BRACE_SLOT_L / 2, 0])
                    circle(d = BRACE_SLOT_W);
            }
}

// Head pocket from the print bed; clipped to the round pad so OD stays intact.
module brace_bottom_relief_2d(p) {
    a = atan2(p.y, p.x);
    intersection() {
        translate(p)
            circle(d = BRACE_PAD_D);
        translate(p)
            rotate(a)
                hull() {
                    translate([-BRACE_SLOT_L / 2, 0])
                        circle(d = BRACE_HEAD_D);
                    translate([BRACE_SLOT_L / 2, 0])
                        circle(d = BRACE_HEAD_D);
                }
    }
}

module brace_blank() {
    r = brace_r_xy();
    t = brace_t_xy();
    lift = brace_cam_lift();
    union() {
        linear_extrude(BRACE_T)
            union() {
                offset(BRACE_WEB / 2)
                    polygon(brace_web_pts());
                translate([0, 0])
                    circle(d = BRACE_PAD_D);
                translate(r)
                    circle(d = BRACE_PAD_D);
                translate(t)
                    circle(d = BRACE_PAD_D);
                translate(brace_tripod_xy())
                    circle(d = BRACE_PAD_D);
            }
        translate([r.x, r.y, BRACE_T])
            cylinder(h = lift, d = BRACE_PAD_D);
        translate([t.x, t.y, BRACE_T])
            cylinder(h = lift, d = BRACE_PAD_D);
    }
}

module part_brace() {
    r = brace_r_xy();
    t = brace_t_xy();
    q = brace_tripod_xy();
    h = BRACE_T + brace_cam_lift();
    color("SlateGray")
    difference() {
        brace_blank();
        translate([0, 0, -0.2])
            cylinder(h = BRACE_T + 0.4, d = BRACE_SCREW_D);
        translate([0, 0, -0.2])
            cylinder(h = BRACE_HEAD_COUNTER_H + 0.2, d = BRACE_HEAD_D);
        translate([0, 0, -0.2])
            linear_extrude(h + 0.4)
                union() {
                    brace_slot_2d(r);
                    brace_slot_2d(t);
                }
        translate([0, 0, -0.2])
            linear_extrude(BRACE_BOTTOM_RELIEF_H + 0.2)
                union() {
                    brace_bottom_relief_2d(r);
                    brace_bottom_relief_2d(t);
                }
        translate([q.x, q.y, -0.05]) {
            cylinder(h = tripod_hole_h() + 0.15, d = TRIPOD_INSERT_D);
            cylinder(h = 0.7, d1 = TRIPOD_INSERT_D + 0.6, d2 = TRIPOD_INSERT_D);
        }
        translate([0, 0, -0.2])
            linear_extrude(BRACE_T + 0.4)
                brace_hex_cuts_2d();
        translate([brace_stamp_xy().x, brace_stamp_xy().y, BRACE_T - STAMP_DEPTH])
            rotate(135)
                part_stamp_cut(kit_tag("brace", "FX BRACE"));
    }
}

module brace_at() {
    translate([0, 0, -JUNCTION_BOX / 2 - PORT_SLOT_LIP - BRACE_T])
        part_brace();
}

module optical_axis_guides() {
    if ($preview)
        color("gold", 0.45) {
            rotate([90, 0, 0])
                cylinder(h = D_LENS_TO_PLATE + 2, d = 1.0);
            translate([0, -sensor_shift(), 0])
                rotate([0, 90, 0])
                    cylinder(h = D_PLATE_TO_MOUNT + 2, d = 1.0);
            translate([sensor_shift(), 0, 0])
                rotate([-90, 0, 0])
                    cylinder(h = D_PLATE_TO_MOUNT + 2, d = 1.0);
        }
}

module assembly() {
    part_junction();

    if (SHOW_PANELS) {
        at_stem()
            translate([0, 0, EXPLODED ? ex : 0])
                stem_chosen();

        if (STEM == 0)
            at_stem()
                translate([0, 0, patch_t() + stem_tube_len() + HELICOID_LEN
                                 + (EXPLODED ? ex * 1.4 : 0)])
                    part_elnikkor_adapter();
        if (el180_kit())
            at_stem()
                translate([0, 0, patch_t() + stem_tube_len()
                                 + EL180_NUT_H - EL180_ADAPTER_MALE
                                 + (EXPLODED ? ex * 1.4 : 0)])
                    part_el180_adapter();

        at_reflect()
            translate([0, 0, EXPLODED ? ex : 0])
                part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");

        at_transmit()
            translate([0, 0, EXPLODED ? ex : 0])
                part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    }

    hybrid_pair(show_glass = $preview,
                explode_z = EXPLODED ? (JUNCTION_BOX / 2 + 40) : 0,
                sh = sensor_shift(),
                tag = kit_tag("tray", "FX TRAY"));

    if (SHOW_LID)
        part_lid();
    if (SHOW_MONITOR || SHOW_PI)
        translate([0, 0, JUNCTION_BOX / 2 + LID_T + (EXPLODED ? ex * 0.4 : 0)]) {
            if (SHOW_MONITOR)
                display_mount();
            monitor_easel() {
                if (SHOW_MONITOR) {
                    monitor_ghost();
                    sunshade();
                }
                if (SHOW_PI) {
                    monitor_pi();
                }
            }
        }

    if (SHOW_BRACE)
        brace_at();

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
    echo(str("hybrid_shift L: ", fx_mode() ? "D800 FX" : "D7000 DX",
             "; 50x50x1 S1 toward lens; ARM_MOUNT=", ARM_MOUNT,
             " (", ARM_MOUNT ? "integrated F" : "reverse ring", ")",
             " STEM=", STEM, " (", stem_label(), ")",
             " ARMS=", ARMS, " (", ARMS ? "54 mm F 50" : "72 mm 135/180", ")",
             " SHELL=", SHELL));
    echo(str("PATH_TOTAL=", PATH_TOTAL, " mm  stitch_w=", stitch_w(),
             " mm  overlap=", overlap_frac(), "  sensor_shift=", sensor_shift(),
             " mm  field_toe=", field_toe(), " deg"));
    if (fx_mode())
        echo(str("FX print STLs: ./export_hybrid_shift_fx.sh → stls/hybrid_shift_fx/ ",
                 "(chassis, arms, lid, brace, tray, stem_el180_inf)"));
}

module export_part() {
    if (PART == "chassis" || PART == "junction")
        part_junction();
    else if (PART == "stem")
        stem_chosen();
    else if (PART == "stem_f50")
        part_stem_f50();
    else if (PART == "stem_el180")
        part_stem_el180();
    else if (PART == "stem_el180_inf")
        part_stem_el180_inf();
    else if (PART == "arm_r" || PART == "arm_r_s"
          || PART == "arm_r_f" || PART == "arm_r_sf")
        part_camera_tube(reflect_tube_len(), rx = -field_toe(), mark = "R");
    else if (PART == "arm_t" || PART == "arm_t_s"
          || PART == "arm_t_f" || PART == "arm_t_sf")
        part_camera_tube(transmit_tube_len(), ry = -field_toe(), mark = "T");
    else if (PART == "shims")
        shim_set();
    else if (PART == "elnikkor_adapter")
        part_elnikkor_adapter();
    else if (PART == "el180_adapter")
        part_el180_adapter();
    else if (PART == "lid")
        part_lid();
    else if (PART == "display_mount")
        display_mount_print();
    else if (PART == "hybrid_tray")
        hybrid_cartridge(show_glass = false, sh = sensor_shift(),
                          tag = kit_tag("tray", "FX TRAY"));
    else if (PART == "brace")
        part_brace();
    else
        assembly();
}

export_part();
