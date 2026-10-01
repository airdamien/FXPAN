// FXPAN 65 plate cartridge. 50×75×1 50/50 at 45° on the origin; drop it in
// from +Z with S1 toward the lens (Edmund marks the coated side with a black
// dot). The 75 lies across the fold — that is the direction √2 eats and the
// stitch has to cross — and the 50 stands up, so it is BS_H that sets how
// tall this cup and the chassis around it have to be. Thick frame holds the
// glass, open-top walls reach the lid shelf, three port windows. Inner faces,
// plate window and beams are sawtoothed. No roof.

include <params.scad>
include <../lib/part_stamp.scad>

POST_W         = 8.0;
POST_D         = 3.2;
// Upside-down plate retention. Plate-local: X across the slot, Y along the
// 75 mm glass. Each bore starts on a cheek top and crosses the open slot
// just above the glass, so a 1.75 mm scrap blocks the plate from lifting.
PLATE_PIN_D    = 2.05;
PLATE_PIN_Y    = 18;     // along the glass, clear of both ends
PLATE_PIN_DROP = 1.6;    // after the vertical lead-in, still above the glass
// Centring ribs. One per cheek at each end of the slot, outside the beam
// window, full height. Opposite pairs pinch the glass from both faces, so it
// sits on the slot centre the arms are cut for and cannot lean. The gap is
// a hair over the glass: printed slots close up, and the ribs are thin
// enough to scrape to a fit.
PLATE_RIB_GAP  = 1.10;
PLATE_RIB_R    = 0.6;
PLATE_RIB_LEAD = 4.0;    // taper at the top so the glass finds the gap
// Just past the glass. 8 mm was the 50 mm-plate value and on a 75 mm plate
// it drove both pegs into the cup walls; the −X−Y one also sat on a
// monitor-rail screw.
POST_OUT       = 4.5;
FORK_CLEAR     = 0.4;
FORK_LEN       = 10.0;
SLIP           = 0.4;
SKIRT_T        = 3.4;
SKIRT_H        = 8.0;
FLOOR_T        = 2.0;
RIB_PITCH      = 2.8;
RIB_DEPTH      = 0.9;
// Chassis M3 nuts / screw tips can sit a hair proud of the inner wall.
FASTENER_RELIEF_D = 9.0;
FASTENER_RELIEF_H = 1.4;
LID_NUT_Z         = BOX_Z / 2 - LID_NUT_DROP;

function chamber_xy() = BOX_XY - 2 * WALL;
function inner()      = chamber_xy() - 2 * SLIP;
function half()       = inner() / 2;
function floor_z()    = -BOX_Z / 2 + WALL;
function wall_top()   = BOX_Z / 2 - LID_LIP_SEAT;
function slot_t()     = BS_THICK + BS_CLEAR * 2;
function plate_w()    = BS_W + BS_CLEAR * 2;   // along the plate, across the fold
function plate_h()    = BS_H + BS_CLEAR * 2;   // standing up
function frame_top()  = frame_top_z();
function corner_y()   = half() * sqrt(2);
function shelf_z()    = -BS_H / 2 - 0.15;
// Rear tip of the seated lens, in cup Y. The window stops 1.5 mm past it.
function lens_tip_y() = -BOX_XY / 2 - (inf_seat_z() - (8 + 9.2));
function lens_window_h() = lens_tip_y() + 1.5 - (-half() - 1);

// +X+Y sits on the plate frame (dead corner between the cameras). −X+Y sits
// on the inactive beam so the lid fork is not in the cup wall and not on
// the rail screws at (−32, −32).
function retain_r() = (plate_w() / 2 + POST_OUT) * sqrt(2) / 2;
function retain_xy(side) =
    let (r = retain_r())
        side > 0 ? [r, r] : [-r, r];
function retain_az(side) = side > 0 ? -45 : 45;

module retain_at(side) {
    p = retain_xy(side);
    translate([p[0], p[1], 0])
        rotate([0, 0, retain_az(side)])
            children();
}

// side +1 enters the +X cheek; −1 the −X cheek. Coords are plate-local.
function plate_pin_entry(side) =
    let (x = side * (slot_t() / 2 + CARTRIDGE_WALL / 2))
        [x, side * PLATE_PIN_Y, frame_top()];

module plate_pin_span(side) {
    p = plate_pin_entry(side);
    // Vertical lead-in so the top face stays a round hole, then the
    // angled run stays under the skin and only opens across the slot.
    z0 = p[2] - 2.0;
    a = [p[0], p[1], z0];
    b = [-side * (slot_t() / 2 + 1.6), p[1], z0 - PLATE_PIN_DROP];
    translate([p[0], p[1], (p[2] + 0.6 + z0) / 2])
        cylinder(d = PLATE_PIN_D, h = p[2] + 0.6 - z0, center = true);
    hull() {
        translate(a) sphere(d = PLATE_PIN_D);
        translate(b) sphere(d = PLATE_PIN_D);
    }
}

module plate_filament_pin_preview() {
    rotate([0, 0, -45])
        for (side = [-1, 1]) {
            p = plate_pin_entry(side);
            color("DarkOrange", 0.9)
                translate([p[0], p[1], p[2] + 1.2])
                    cylinder(d = PLATE_PIN_D, h = 2.4, center = true);
        }
}

module plate_filament_pin_holes() {
    rotate([0, 0, -45])
        for (side = [-1, 1])
            plate_pin_span(side);
}

module place_plate(glass = false) {
    rotate([0, 0, -45])
        if (glass) {
            color("gold", 0.45)
                cube([BS_THICK, BS_W, BS_H], center = true);
        } else {
            bs_frame();
        }
}

module trap_ribs(len, h) {
    n = max(1, floor(len / RIB_PITCH));
    for (i = [0 : n - 1])
        translate([0, -len / 2 + (i + 0.5) * RIB_PITCH, 0])
            linear_extrude(height = h, center = true)
                polygon([
                    [0, -RIB_PITCH * 0.45],
                    [0,  RIB_PITCH * 0.45],
                    [RIB_DEPTH, 0]
                ]);
}

// One window per port face — do not punch the opposite wall.
module chamber_ports(sh) {
    d = TUBE_ID + 0.6;
    t = SKIRT_T;
    w = t + 6;
    // Lens face. The Ø60 barrel runs past the wall and into the frame.
    translate([0, -half() - 1, 0])
        rotate([-90, 0, 0])
            cylinder(h = lens_window_h(), d = EL180_BARREL);
    translate([half() - t / 2, cam_axis("R", sh).y, 0])
        rotate([0, 90, 0])
            cylinder(h = w, d = d, center = true);
    translate([cam_axis("T", sh).x, half() - t / 2, 0])
        rotate([-90, 0, 0])
            cylinder(h = w, d = d, center = true);
}

// Cross-hatch V-grooves in the plane z. bite < 0 cuts −Z, > 0 cuts +Z.
module hatch_ribs(z, bite, span) {
    n = max(1, floor(span / RIB_PITCH));
    module row(along_x) {
        for (i = [0 : n - 1]) {
            u = -span / 2 + (i + 0.5) * RIB_PITCH;
            translate(along_x ? [0, u, z] : [u, 0, z])
                rotate(along_x ? [90, 0, 90] : [90, 0, 0])
                    linear_extrude(height = span, center = true)
                        polygon([
                            [-RIB_PITCH * 0.45, 0],
                            [ RIB_PITCH * 0.45, 0],
                            [0, bite]
                        ]);
        }
    }
    row(true);
    row(false);
}

module floor_ribs() {
    hatch_ribs(floor_z() + FLOOR_T, -RIB_DEPTH, inner() - 2 * SKIRT_T - 2);
}

module lid_inner_ribs() {
    // 45° square bars: reliable boolean (triangular hatch_ribs sealed shut).
    span = BOX_XY - 2 * WALL - 2;
    p = RIB_PITCH;
    w = RIB_DEPTH * 2;
    n = max(1, floor(span / p));
    for (i = [0 : n - 1]) {
        u = -span / 2 + (i + 0.5) * p;
        translate([0, u, 0])
            rotate([45, 0, 0])
                cube([span + 2, w, w], center = true);
        translate([u, 0, 0])
            rotate([0, 45, 0])
                cube([w, span + 2, w], center = true);
    }
}

// Shallow pockets on the cup skin at the two clamp M3s + lid corners.
module chassis_fastener_relief(sh) {
    d = FASTENER_RELIEF_D;
    h = FASTENER_RELIEF_H;
    for (side = [-1, 1]) {
        s = clamp_xy("", side, sh);
        r = clamp_xy("R", side, sh);
        t = clamp_xy("T", side, sh);
        translate([s.x, -half(), s.y])
            rotate([90, 0, 0])
                translate([0, 0, -h])
                    cylinder(h = h + 0.3, d = d);
        translate([half(), r.y, -r.x])
            rotate([0, 90, 0])
                translate([0, 0, -h])
                    cylinder(h = h + 0.3, d = d);
        translate([t.x, half(), -t.y])
            rotate([-90, 0, 0])
                translate([0, 0, -h])
                    cylinder(h = h + 0.3, d = d);
    }
    for (sx = [-1, 1], sy = [-1, 1])
        translate([sx * (half() + d / 2 - h),
                   sy * (half() + d / 2 - h),
                   LID_NUT_Z])
            cylinder(h = PORT_NUT_T + 4, d = d, center = true);
}

module bs_frame() {
    w  = CARTRIDGE_WALL;
    py = plate_w();
    pz = plate_h();
    st = slot_t();
    z0 = floor_z();
    top = frame_top();
    reach = corner_y();
    face = st / 2 + w;
    th = st + w * 2;
    win_y = py - 6;
    win_z = pz - 6;

    difference() {
        translate([0, 0, (z0 + top) / 2])
            cube([th, 2 * reach, top - z0], center = true);

        translate([0, 0, (shelf_z() + top + 6) / 2])
            cube([st, py + 0.3, top + 6 - shelf_z()], center = true);

        cube([40, win_y, win_z], center = true);

        // Outer cheeks, full length (slot faces stay smooth for the glass).
        for (sx = [-1, 1])
            translate([sx * face, 0, (z0 + top) / 2])
                rotate([0, 0, sx > 0 ? 180 : 0])
                    trap_ribs(2 * reach - 2, top - z0 + 2);

        // Inner window around the plate.
        for (sy = [-1, 1])
            translate([0, sy * win_y / 2, 0])
                rotate([0, 0, sy > 0 ? 90 : -90])
                    trap_ribs(th - 0.4, win_z - 0.4);
        translate([0, 0, win_z / 2])
            rotate([0, -90, 0])
                trap_ribs(win_y - 0.4, th - 0.4);
        translate([0, 0, -win_z / 2])
            rotate([0, 90, 0])
                trap_ribs(win_y - 0.4, th - 0.4);
    }
    plate_centre_ribs();
}

function plate_rib_y() = (plate_w() - 6) / 4 + plate_w() / 4;   // mid-land

module plate_centre_ribs() {
    st = slot_t();
    r = PLATE_RIB_R;
    z0 = shelf_z();
    z1 = frame_top();
    zl = z1 - PLATE_RIB_LEAD;
    for (sx = [-1, 1], sy = [-1, 1]) {
        xc = sx * (PLATE_RIB_GAP / 2 + r);   // rib face at ±gap/2
        xf = sx * (st / 2 + r);              // flush with the cheek
        intersection() {
            hull() {
                translate([xc, sy * plate_rib_y(), z0])
                    cylinder(r = r, h = zl - z0, $fn = 24);
                translate([xf, sy * plate_rib_y(), z1 - 0.01])
                    cylinder(r = r, h = 0.01, $fn = 24);
            }
            translate([sx * (st / 4 + 0.25), 0, (z0 + z1) / 2])
                cube([st / 2 + 0.5, plate_w() + 1, z1 - z0], center = true);
        }
    }
}

// Open-top cup: uniform wall thickness, then recut the three port windows.
// Floor is a separate slab so the inner faces stay vertical — the old skirt
// step at FLOOR_T left an inward shelf that needed support when printing
// floor-down.
module chamber_walls(sh, tag = "fxp_tray") {
    z0 = floor_z();
    h  = wall_top() - z0;
    t  = SKIRT_T;
    wall_h = h - FLOOR_T;
    difference() {
        union() {
            difference() {
                translate([0, 0, z0 + FLOOR_T + wall_h / 2])
                    cube([inner(), inner(), wall_h], center = true);
                translate([0, 0, z0 + FLOOR_T + wall_h / 2])
                    cube([inner() - 2 * t, inner() - 2 * t, wall_h + 0.2],
                         center = true);
                for (a = [0, 90, 180, 270])
                    rotate([0, 0, a])
                        translate([half() - t, 0, z0 + FLOOR_T + wall_h / 2])
                            trap_ribs(inner() - 2 * t - 0.2, wall_h + 2);
            }
            translate([0, 0, z0 + FLOOR_T / 2])
                cube([inner(), inner(), FLOOR_T], center = true);
        }
        floor_ribs();
        tray_stamp(tag);
        chamber_ports(sh);
    }
}

// Readable from the stem, above the barrel hole on the −Y face.
module tray_stamp(tag = "fxp_tray") {
    translate([0, -half() + STAMP_DEPTH, EL180_BARREL / 2 + 3.2])
        rotate([90, 0, 180])
            part_stamp_cut(tag, STAMP_DEPTH, 3.0);
}

// Diagonal stiffener perpendicular to the plate — the dead quadrant no
// beam ever reaches, so it costs nothing optically.
module inactive_beams() {
    z0 = floor_z();
    L  = inner() * sqrt(2);
    rotate([0, 0, 45])
        difference() {
            translate([0, 0, z0 + SKIRT_H / 2])
                cube([SKIRT_T, L, SKIRT_H], center = true);
            for (sx = [-1, 1])
                translate([sx * SKIRT_T / 2, 0, z0 + SKIRT_H / 2])
                    rotate([0, 0, sx > 0 ? 180 : 0])
                        trap_ribs(L - 4, SKIRT_H + 2);
        }
}

module cartridge_posts() {
    top = frame_top();
    for (side = [-1, 1]) {
        retain_at(side)
            translate([0, 0, top + POST_H / 2])
                cube([POST_D, POST_W, POST_H], center = true);
        // −X+Y is not on the plate frame; drop a riser onto the inactive
        // beam so the peg is the same part as the cup.
        if (side < 0) {
            z0 = floor_z() + SKIRT_H;
            retain_at(side)
                translate([0, 0, (z0 + top) / 2])
                    cube([POST_D, POST_W, max(0.8, top - z0)], center = true);
        }
    }
}

module fxp_cartridge(show_glass = true, sh, tag = "fxp_tray") {
    color("SteelBlue")
    intersection() {
        difference() {
            union() {
                place_plate(glass = false);
                chamber_walls(sh, tag);
                inactive_beams();
                cartridge_posts();
            }
            chassis_fastener_relief(sh);
            plate_filament_pin_holes();
            translate([0, -half() - 1, 0])
                rotate([-90, 0, 0])
                    cylinder(h = lens_window_h(), d = EL180_BARREL);
        }
        translate([0, 0, floor_z() + (wall_top() - floor_z()) / 2])
            cube([inner(), inner(), wall_top() - floor_z() + 0.2],
                 center = true);
    }
    if (show_glass)
        intersection() {
            place_plate(glass = true);
            cube([inner(), inner(), BOX_Z - 1], center = true);
        }
    if ($preview)
        plate_filament_pin_preview();
}

module lid_retain_tabs(lip = 3) {
    for (side = [-1, 1])
        retain_at(side)
            difference() {
                translate([0, 0, (-lip - FORK_LEN + 1.2) / 2])
                    cube([POST_D + 3.2, POST_W + 4,
                          lip + FORK_LEN + 1.2], center = true);
                translate([0, 0, -lip - FORK_LEN / 2 - 0.6])
                    cube([POST_D + FORK_CLEAR * 2,
                          POST_W + FORK_CLEAR * 2,
                          FORK_LEN], center = true);
            }
}

module lid_retain_keepout(h = 10) {
    for (side = [-1, 1])
        retain_at(side)
            cube([POST_D + 5, POST_W + 6, h], center = true);
}

module fxp_pair(show_glass = true, explode_z = 0, sh, tag = "fxp_tray") {
    translate([0, 0, explode_z])
        fxp_cartridge(show_glass = show_glass, sh = sh, tag = tag);
}
