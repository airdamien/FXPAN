// Soldering jig for the Pi GPIO trigger board.
//
// Geometry is taken from jig/assembly.stl (KiCad board + parts):
//   board 65.20 x 55.45 x 1.6 mm
//   J3 2x20 body 50.80 x 5.08 x 8.60 mm, on the bottom, 0.74 mm in from the GPIO edge
//   tallest top-side part (jacks) reaches 12.3 mm above the board
//
// Preview (F5) ghosts the assembly. F6 renders the jig only.
//   flip_board = false  header-solder pose: socket in the nest, board on top
//   flip_board = true   component-solder pose: each part sits in its own pocket
//
// Use:
//   1. Drop the 2x20 in the nest, pins up. Pin 1 (square pad) toward the "1".
//   2. Drop the bare board on the pins. Solder the header from above.
//   3. Form resistors on the edge cradle (straight 1/4 W, bend one lead around the curve).
//   4. Insert optos, jacks, LEDs, resistors from the top.
//   5. Flip the board back into the pocket, 2x20 edge toward the nest, parts down.
//      Each body bottoms out in its pocket, so it stays flush in the board.
//      Solder the other side. The header sticks up.
//
// If your socket plastic is not 8.6 mm tall, set header_h to the measured body.

show_assembly = true;
flip_board = false;

board_w = 65.20;
board_h = 55.45;
board_t = 1.60;

// Header body in board coordinates. GPIO / pin-1 edge is y = 0, pin 1 is low X.
hdr_x0 = 6.93;
hdr_y0 = 0.74;
hdr_l  = 50.80;
hdr_w  = 5.08;
header_h = 8.60;
hdr_clear = 0.20;   // per side; this pocket is the tight one

wall = 4.0;
board_clear = 0.30; // per side, so the PCB drops in
relief = 15.0;       // solid under the board; pockets are only as deep as each part
floor_t = 2.5;

// Vertical 1/4 W former: DIN0207 body, leads end 2.54 mm apart.
pitch = 2.54;
body_l = 6.3;
body_d = 2.5;
lead_d = 0.60;
anvil_r = pitch / 2 - lead_d / 2; // lead centerline wraps a 1.27 mm radius

eps = 0.02;
ledge_z = floor_t + relief;
total_h = ledge_z + board_t;
ox = wall + board_clear;
oy = wall + board_clear;
outer_x = ox + board_w + board_clear + wall;
outer_y = oy + board_h + board_clear + wall;

module assembly_ghost() {
    cx = ox + board_w / 2;
    cy = oy + board_h / 2;
    cz = ledge_z + board_t / 2;
    translate([cx, cy, cz])
        rotate(flip_board ? [0, 180, 0] : [0, 0, 0])
            translate([-cx, -cy, -cz])
                // STL origin is KiCad's, with Y negated: board x 14..79.2, y -69.45..-14, z 0 at the bottom.
                translate([ox - 14, oy - 14, ledge_z])
                    scale([1, -1, 1])
                        import("assembly.stl", convexity = 8);
}

module board_pocket() {
    translate([ox - eps, oy - eps, ledge_z])
        cube([board_w + 2 * board_clear + 2 * eps, board_h + 2 * board_clear + 2 * eps, board_t + eps]);
    // Lead-in step so the board starts without catching the rim.
    translate([ox - board_clear, oy - board_clear, total_h - 0.45])
        cube([board_w + 4 * board_clear, board_h + 4 * board_clear, 0.45 + eps]);
}

module pry_notches() {
    for (x = [0.6, outer_x - 2.6])
        translate([x, oy + board_h / 2 - 6, ledge_z - eps])
            cube([2.2, 12, board_t + 0.6]);
}

// One well per topside part, in the flipped pose (X mirrored, GPIO edge still at y = 0).
// [x, y, w, h, depth] from the board corner. Depth is below the ledge.
// From assembly.stl. Each well is 0.40 mm larger per side and 0.25 mm deeper
// than the body, so the part bottoms out flush and the board still sits on the rim.
part_pockets = [
    [45.65, 7.65, 18.85, 9.00, 12.55],   // J2 jack
    [19.96, 12.40, 4.89, 3.30, 9.75],    // vertical resistor
    [37.96, 12.40, 4.89, 3.30, 9.75],
    [9.85, 12.67, 8.67, 7.85, 3.93],     // 4N35
    [27.85, 12.67, 8.67, 7.85, 3.93],
    [45.65, 19.35, 18.85, 9.00, 12.55],  // J1 jack
    [19.96, 23.40, 4.89, 3.30, 9.75],
    [37.96, 23.40, 4.89, 3.30, 9.75],
    [9.85, 23.66, 8.67, 7.85, 3.93],
    [27.85, 23.66, 8.67, 7.85, 3.93],
    [8.63, 33.30, 6.20, 6.60, 11.84],    // LED
    [17.63, 33.30, 6.20, 6.60, 11.84],
    [9.96, 40.05, 4.89, 3.30, 9.75],
    [18.96, 40.05, 4.89, 3.30, 9.75],
    [8.63, 43.50, 6.20, 6.60, 11.84],
    [17.63, 43.50, 6.20, 6.60, 11.84],
    [9.96, 50.25, 4.89, 3.30, 9.75],
    [18.96, 50.25, 4.89, 3.30, 9.75],
];

module part_supports() {
    for (p = part_pockets)
        translate([ox + p[0], oy + p[1], ledge_z - p[4]])
            cube([p[2], p[3], p[4] + eps]);
}

module header_pocket() {
    translate([
        ox + hdr_x0 - hdr_clear,
        oy + hdr_y0 - hdr_clear,
        ledge_z - header_h
    ])
        cube([hdr_l + 2 * hdr_clear, hdr_w + 2 * hdr_clear, header_h + eps]);
    // Looser mouth for the first 1.5 mm, then the snug section seats the plastic.
    translate([
        ox + hdr_x0 - hdr_clear - 0.25,
        oy + hdr_y0 - hdr_clear - 0.25,
        ledge_z - 1.5
    ])
        cube([hdr_l + 2 * hdr_clear + 0.5, hdr_w + 2 * hdr_clear + 0.5, 1.5 + eps]);
}

module pin1_mark() {
    translate([wall / 2, oy + hdr_y0 + hdr_w / 2, total_h - 0.4])
        linear_extrude(0.45)
            text("1", size = 2.6, halign = "center", valign = "center",
                 font = "Liberation Sans:style=Bold");
}

// DIN0207 cradle on the inland corner opposite pin 1.
// A U-groove: two leads 2.54 mm apart, joined by a half-round you pull
// the wire around. Deep enough that the lead stays put while you tug.
former_h = 8;
lead_run = 9;
body_bed = body_l + 0.35;
slot_w = 1.15;
slot_d = 2.6;
body_w = body_d + 0.40;
y1 = 1.8;
x_body0 = lead_run;
x_body1 = lead_run + body_bed;
bend_r = pitch / 2; // centerline of the U
former_l = x_body1 + bend_r + slot_w / 2 + 1.6;
former_d = y1 + pitch + slot_w / 2 + 1.5;

module former_place() {
    translate([outer_x, outer_y - 0.01, 0])
        scale([-1, 1, 1])
            children();
}

module former_block() {
    former_place()
        cube([former_l, former_d, former_h]);
}

module lead_path_2d() {
    // Centerline of the U. offset() opens it to slot_w.
    hull() {
        translate([-eps, y1]) circle(0.04, $fn = 8);
        translate([x_body1, y1]) circle(0.04, $fn = 8);
    }
    hull() {
        translate([-eps, y1 + pitch]) circle(0.04, $fn = 8);
        translate([x_body1, y1 + pitch]) circle(0.04, $fn = 8);
    }
    translate([x_body1, y1 + bend_r])
        intersection() {
            difference() {
                circle(bend_r + 0.04, $fn = 64);
                circle(bend_r - 0.04, $fn = 64);
            }
            translate([-0.08, -bend_r - 0.1])
                square([bend_r + 0.2, pitch + 0.2]);
        }
}

module former_cuts() {
    former_place() {
        translate([0, 0, former_h - slot_d])
            linear_extrude(slot_d + eps)
                offset(delta = slot_w / 2 - 0.04)
                    lead_path_2d();
        // Body drops into the near groove, stopped where the curve starts.
        translate([x_body0, y1 - body_w / 2, former_h - slot_d])
            cube([body_bed + eps, body_w, slot_d + eps]);
    }
}

module jig() {
    difference() {
        union() {
            cube([outer_x, outer_y, total_h]);
            former_block();
        }
        board_pocket();
        pry_notches();
        part_supports();
        header_pocket();
        pin1_mark();
        former_cuts();
    }
}

jig();

if (show_assembly)
    %assembly_ghost();
