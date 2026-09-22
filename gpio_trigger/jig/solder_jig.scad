// Soldering jig for the Pi GPIO trigger board.
//
// Geometry is taken from jig/assembly.stl (KiCad board + parts):
//   board 65.20 x 55.45 x 1.6 mm
//   J3 2x20 body 50.80 x 5.08 x 8.60 mm, on the bottom, 0.74 mm in from the GPIO edge
//   tallest top-side part (jacks) reaches 12.3 mm above the board
//
// Preview (F5) ghosts the assembly. F6 renders the jig only.
//   flip_board = false  header-solder pose: socket in the nest, board on top
//   flip_board = true   component-solder pose: jacks against the "1", parts down
//
// Use:
//   1. Drop the 2x20 in the nest, pins up. Pin 1 (square pad) toward the "1".
//   2. Drop the bare board on the pins. The nest floor holds the socket
//      plastic against the board. Solder the header from above.
//   3. Form resistors in the back-edge tool: drop one straight lead down the
//      hole. The snout stops the body. Lay the other lead in the V and it
//      slides to the apex, which is the 2.54 mm bend. Push the lead up from
//      below and lift the part out.
//   4. Insert optos, jacks, LEDs, resistors from the top.
//   5. Flip the board. The jacks land against the "1" wall. Everything else
//      sits in the well beside them, and the board sits flat on the deck.
//
// header_h is the housing bottom measured on assembly.stl (8.58 mm below
// the board). Raise it if your socket plastic is taller.
//
// FXPAN mark, same three parts as the chassis inlay (logos/fxpan_*.stl).
// part selects what an STL export contains. All four share this file's origin.
//   jig       holder, with the mark pocketed into the open deck
//   fx        gold FX + sweep
//   pan       white PAN
//   outline   red outline

show_assembly = true;
flip_board = false;
part = "jig"; // [jig, fx, pan, outline]

board_w = 65.20;
board_h = 55.45;
board_t = 1.60;

// Header body in board coordinates. GPIO / pin-1 edge is y = 0, pin 1 is low X.
hdr_x0 = 6.93;
hdr_y0 = 0.74;
hdr_l  = 50.80;
hdr_w  = 5.08;
header_h = 8.58;  // housing bottom, assembly.stl; seats the plastic on the board
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

eps = 0.02;
ledge_z = floor_t + relief;
total_h = ledge_z + board_t;
ox = wall + board_clear;
oy = wall + board_clear;
outer_x = ox + board_w + board_clear + wall;
outer_y = oy + board_h + board_clear + wall;

module assembly_ghost() {
    // STL origin is KiCad's, with Y negated: board x 14..79.2, y -69.45..-14, z 0 at the bottom.
    if (flip_board)
        // Same place as the jack anchors. Component face is down on the deck.
        translate([ox - 14, oy - 14, ledge_z + board_t])
            scale([1, -1, -1])
                import("assembly.stl", convexity = 8);
    else
        translate([ox - 14, oy - 14, ledge_z])
            scale([1, -1, 1])
                import("assembly.stl", convexity = 8);
}

// Left-to-right flip mirrors about the header center, so the outline
// overhangs the pin-1 side by this much while the pins stay in the nest.
flip_dx = board_w - 2 * (hdr_x0 + hdr_l / 2);

module board_pocket() {
    // Open on the pin-1 side so both poses drop in and sit on the deck.
    translate([ox - flip_dx - board_clear, oy - eps, ledge_z])
        cube([
            board_w + flip_dx + 2 * board_clear + eps,
            board_h + 2 * board_clear + 2 * eps,
            board_t + eps
        ]);
    // Lead-in step so the board starts without catching the rim.
    translate([ox - flip_dx - board_clear - 0.4, oy - board_clear, total_h - 0.45])
        cube([
            board_w + flip_dx + 4 * board_clear + 0.8,
            board_h + 4 * board_clear,
            0.45 + eps
        ]);
}

module pry_notches() {
    for (x = [0.6, outer_x - 2.6])
        translate([x, oy + board_h / 2 - 6, ledge_z - eps])
            cube([2.2, 12, board_t + 0.6]);
}

// Wells in the same frame as the TRS jacks, which land against the "1" wall.
// [x, y, w, h, depth] from that corner. Depth is below the ledge.
// From assembly.stl. Each well is 0.40 mm larger per side and 0.25 mm deeper
// than the body, so the part bottoms out flush and the board sits flat.
part_pockets = [
    [0.70, 7.65, 18.85, 9.00, 12.55],    // jack
    [22.35, 12.40, 4.89, 3.30, 9.75],
    [40.35, 12.40, 4.89, 3.30, 9.75],
    [28.67, 12.67, 8.67, 7.85, 3.93],
    [46.67, 12.67, 8.67, 7.85, 3.93],
    [0.70, 19.35, 18.85, 9.00, 12.55],   // jack
    [22.35, 23.40, 4.89, 3.30, 9.75],
    [40.35, 23.40, 4.89, 3.30, 9.75],
    [28.67, 23.67, 8.67, 7.85, 3.93],
    [46.67, 23.67, 8.67, 7.85, 3.93],
    [41.37, 33.30, 6.20, 6.60, 11.84],
    [50.37, 33.30, 6.20, 6.60, 11.84],
    [41.35, 40.05, 4.89, 3.30, 9.75],
    [50.35, 40.05, 4.89, 3.30, 9.75],
    [41.37, 43.50, 6.20, 6.60, 11.84],
    [50.37, 43.50, 6.20, 6.60, 11.84],
    [41.35, 50.25, 4.89, 3.30, 9.75],
    [50.35, 50.25, 4.89, 3.30, 9.75],
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

// Vertical 1/4 W former on the outside of the inland wall, opposite pin 1.
// A round snout stands against the top of the body. A 60° V follows the
// bend over that snout and down the face. The mouth is wide, the apex sharp,
// so the lead slides to the middle. The apex is one pitch from the hole.
lead_hole_d = 1.6;
cup_d = 3.5;
cup_depth = body_l;
rib_w = 16;
v_half = 30;
v_seat = (lead_d / 2) / sin(v_half);
v_wall = 5.0;
v_half_w = v_wall * tan(v_half);
apex_r = pitch / 2 - v_seat;
// Cheek surface sits inside the V mouth, so the groove breaks out as a V.
snout_r = apex_r + v_wall * 0.68;
bend_x = outer_x - 16;
bend_hole_y = (outer_y - wall) + 1.3 + cup_d / 2;
arc_y = bend_hole_y + pitch / 2;
return_y = bend_hole_y + pitch;
v_apex_y = return_y - v_seat;
bend_face_y = arc_y + snout_r;
// Just clear of the body, so the part drops in and the snout stops the top.
snout_y0 = bend_hole_y + body_d / 2 + 0.15;

module bender_rib() {
    translate([bend_x - rib_w / 2, outer_y - 0.01, 0])
        cube([rib_w, bend_face_y - (outer_y - 0.01), total_h]);
    // Round snout above the deck, clipped clear of the body column.
    intersection() {
        translate([bend_x - rib_w / 2, arc_y, total_h])
            rotate([0, 90, 0])
                cylinder(h = rib_w, r = snout_r, $fn = 72);
        translate([bend_x - rib_w / 2 - 0.1, snout_y0, total_h - 0.01])
            cube([rib_w + 0.2, bend_face_y - snout_y0 + 0.2, snout_r + 1]);
    }
}

module lead_v() {
    translate([0, 0, -1])
        linear_extrude(total_h + 2)
            polygon([
                [bend_x, v_apex_y],
                [bend_x - v_half_w, v_apex_y + v_wall],
                [bend_x + v_half_w, v_apex_y + v_wall],
            ]);
    // Upper semicircle: hole side, over the top, out to the return lead.
    translate([bend_x, arc_y, total_h])
        rotate([90, 0, 90])
            rotate_extrude(angle = 180, $fn = 64)
                polygon([
                    [apex_r, 0],
                    [apex_r + v_wall, -v_half_w],
                    [apex_r + v_wall, v_half_w],
                ]);
}

module bender_cuts() {
    translate([bend_x, bend_hole_y, -1])
        cylinder(h = total_h + 2, d = lead_hole_d, $fn = 32);
    translate([bend_x, bend_hole_y, -1])
        cylinder(h = 1.6, d1 = lead_hole_d + 1.4, d2 = lead_hole_d, $fn = 32);
    translate([bend_x, bend_hole_y, total_h - cup_depth])
        cylinder(h = cup_depth + eps, d = cup_d, $fn = 48);
    lead_v();
}

// Colour-separated FXPAN mark from logos/fxpan_gen.py. Native outline box,
// so one centering translate keeps gold, PAN and the red line registered.
logo_art = "../../logos";
logo_art_x0 = -1.200;
logo_art_y0 = -3.963;
logo_art_w = 143.367;
logo_art_h = 74.771;
// Open deck beside the jacks, clear of the other wells.
logo_h = 20.0;
logo_s = logo_h / logo_art_h;
logo_cx = ox + 20.1;
logo_cy = oy + 42.0;
logo_deep = 0.8;    // pocket, at least 0.6 mm
logo_fit = 0.04;    // plug bites the pocket wall so the sides are not coplanar
logo_proud = 0;     // flush with the deck; the board sits on this face
logo_outline_w_native = 0.6;  // fxpan_gen.py OUTLINE_WIDTH_MM
logo_outline_w_min = 0.42;    // printable with a 0.4 mm nozzle
logo_outline_boost = max(0, (logo_outline_w_min - logo_outline_w_native * logo_s) / 2);

module fxpan_art(name) {
    translate([logo_cx, logo_cy])
        scale(logo_s)
            translate([-logo_art_x0 - logo_art_w / 2,
                       -logo_art_y0 - logo_art_h / 2])
                projection(cut = false)
                    import(str(logo_art, "/", name), convexity = 12);
}

module fxpan_outline_art() {
    offset(delta = logo_outline_boost)
        fxpan_art("fxpan_outline_red.stl");
}

module logo_plug(name) {
    translate([0, 0, ledge_z - logo_deep - logo_fit])
        linear_extrude(logo_deep + logo_fit + logo_proud)
            offset(delta = logo_fit)
                fxpan_art(name);
}

module logo_plug_outline() {
    translate([0, 0, ledge_z - logo_deep - logo_fit])
        linear_extrude(logo_deep + logo_fit + logo_proud)
            offset(delta = logo_fit)
                fxpan_outline_art();
}

module logo_pocket() {
    translate([0, 0, ledge_z - logo_deep])
        linear_extrude(logo_deep + eps)
            union() {
                fxpan_art("fxpan_fx_gold.stl");
                fxpan_art("fxpan_pan_white.stl");
                fxpan_outline_art();
            }
}

module jig() {
    difference() {
        union() {
            cube([outer_x, outer_y, total_h]);
            bender_rib();
        }
        board_pocket();
        pry_notches();
        part_supports();
        header_pocket();
        pin1_mark();
        bender_cuts();
        logo_pocket();
    }
}

if (part == "jig") {
    jig();
    %color("Gold") logo_plug("fxpan_fx_gold.stl");
    %color("White") logo_plug("fxpan_pan_white.stl");
    %color("Crimson") logo_plug_outline();
} else if (part == "fx")
    color("Gold") logo_plug("fxpan_fx_gold.stl");
else if (part == "pan")
    color("White") logo_plug("fxpan_pan_white.stl");
else if (part == "outline")
    color("Crimson") logo_plug_outline();

if (show_assembly && part == "jig")
    %assembly_ghost();
