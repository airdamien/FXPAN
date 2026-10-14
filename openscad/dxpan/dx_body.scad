// One piece. Walls stay thin. The F-mounts sit on tubes that stand off
// the outer face, so a body can twist on without meeting the wall.
// The logo is engraved in the logo wall.

function dx_reg(mark) =
    let (tube = mark == "T" ? transmit_focus_tube_len()
                            : reflect_focus_tube_len())
        BOX_XY / 2 + patch_t() + tube + F_FMOUNT_STACK - CAM_RECESS
        + DX_TUBE_GAIN;
function dx_back(mark) = dx_reg(mark) - F_FMOUNT_STACK;

DX_CAV   = 27;     // cavity half. Plate cheeks stay inside it.
DX_WALL  = 6;      // camera panels. The arm beyond them is tube.
// The M65 cutter is 33.2 mm from the axis. These two faces sit outside it.
DX_HALF_Z = 36;
DX_LOGO   = 36;
// The helicoid male is 4.25 mm. The lip is that deep and no more.
// Back of the thread stays 20 mm from the plate. The 3.75 mm this
// used to be is on the tubes. Face was 39 mm out; gain is the rest.
DX_THREAD      = 4.25;
DX_THREAD_BORE = 62;          // core, under the M65 crests
DX_HELI_CLEAR_D = 83;         // keep-out around the helicoid body
DX_THREAD_BACK = 20;
DX_LENS        = DX_THREAD_BACK + DX_THREAD;
DX_TUBE_GAIN   = 39 - DX_LENS;
function dx_face(mark) = DX_CAV + DX_WALL;
DX_FLOOR = 3;
DX_LIP   = 2;
// The flange crown is r 31. The lid is everything above that, except the
// lens ledge, which stays so the M65 thread still has a roof.
DX_SEAT    = F_STL_OD / 2 + 0.8;
DX_LEDGE_Y = -DX_LENS + DX_THREAD;
DX_TAP_D   = 2.5;    // M3 cuts its own thread
DX_TAP_H   = 6;
DX_CLR_D   = 3.2;
DX_CSK_D   = 6.4;    // 90° countersink

function dx_x0() = -DX_LOGO;
function dx_x1() = dx_face("R");
function dx_y0() = -DX_LENS;
function dx_y1() = dx_face("T");

// Pilot stays in the wall. Heads sit in the lid, which spans the cavity.
function dx_lid_screws() = [
    [dx_x0() + 6.0,    2],
    [dx_x0() + 6.0,   24],
    [dx_x1() - 3.6,   18],
    [-18,            dx_y1() - 3.6],
    [16,             dx_y1() - 3.6]
];

module dx_outer() {
    translate([(-DX_LOGO + dx_face("R")) / 2,
               (-DX_LENS + dx_face("T")) / 2,
               0])
        cube([dx_face("R") + DX_LOGO,
              dx_face("T") + DX_LENS,
              2 * DX_HALF_Z], center = true);
}

module dx_cavity() {
    // Chassis floor is the bottom of the 50 mm glass. The plate sits on it.
    // Lens side is open to the back of the thread. No wall behind the crests.
    z0 = -BS_H / 2 - 0.15;
    z1 = DX_HALF_Z - DX_LIP;
    y0 = -(DX_LENS - DX_THREAD);
    y1 = DX_CAV;
    translate([0, (y0 + y1) / 2, (z0 + z1) / 2])
        cube([DX_CAV * 2, y1 - y0, z1 - z0 + 0.2], center = true);
}

// 50 × 50 × 1 plate. Cheeks are a light press, 0.97 mm on 1.00 mm glass.
// They run up to the lid so the cavity above the glass is a solid wall.
// The lens-side fin stops on the back of the thread and turns along it.
module dx_plate() {
    pinch = BS_THICK - 0.03;
    mouth = 1.6;
    wide = 4.9;
    plen = BS_W + 0.06;
    reach = DX_CAV * sqrt(2) + 0.6;
    shelf = -BS_H / 2 - 0.04;
    z0 = shelf - 2.2;
    z1 = DX_SEAT - 0.3;
    edge = 4;
    open0 = shelf + edge;
    open1 = BS_H / 2 - edge;
    glass_top = BS_H / 2;
    inner = -(DX_LENS - DX_THREAD);
    intersection() {
        rotate([0, 0, -45])
            union() {
                difference() {
                    translate([0, 0, (z0 + z1) / 2])
                        cube([wide, plen, z1 - z0], center = true);
                    // The slot stays open to the lid so the plate can slide in.
                    // Either side of it the cheek is solid up to the lid.
                    translate([0, 0, (shelf + z1 + 2) / 2])
                        cube([pinch, plen + 1, z1 + 2 - shelf], center = true);
                    hull() {
                        translate([0, 0, glass_top + 0.3])
                            cube([pinch, plen + 1, 0.2], center = true);
                        translate([0, 0, z1 + 1])
                            cube([mouth, plen + 1, 0.2], center = true);
                    }
                    translate([0, 0, (open0 + open1) / 2])
                        cube([wide + 1, BS_W - 2 * edge, open1 - open0], center = true);
                }
                for (sy = [-1, 1])
                    translate([0, sy * (plen / 2 + (reach - plen / 2) / 2), (z0 + z1) / 2])
                        cube([2.2, reach - plen / 2, z1 - z0], center = true);
            }
        // Cavity only. The lens fin used to run out through the threads.
        translate([0, (inner + 0.4 + DX_CAV) / 2, 0])
            cube([DX_CAV * 2 + 1.2, DX_CAV - inner - 0.4, 90], center = true);
    }
    // The clipped fin turns along the back of the thread and ties into
    // the cavity wall. It stays off the glass and on the cavity side of
    // the bore, so the port stays a round hole.
    translate([-(DX_CAV + 16.8) / 2, inner + 0.4, (z0 + z1) / 2])
        cube([DX_CAV - 16.8, 0.8, z1 - z0], center = true);
}

module dx_plate_pins() {
    rotate([0, 0, -45])
        for (sy = [-1, 1])
            translate([0, sy * (BS_W / 2 - 8), BS_H / 2 + 1.0])
                rotate([0, 90, 0])
                    cylinder(h = 16, d = 2.05, center = true, $fn = 24);
}

// Root of the tube, in the tube's own XY. Full flange diameter, cut back
// to the chassis outline where that circle would hang off the panel.
module dx_tube_root_2d(mark) {
    inset = 0.15;
    hz = DX_HALF_Z - inset;
    intersection() {
        circle(d = F_STL_OD, $fn = 96);
        if (mark == "R") {
            ay = -sensor_shift();
            y0 = -DX_LENS - ay + inset;
            y1 = dx_face("T") - ay - inset;
            translate([0, (y0 + y1) / 2])
                square([2 * hz, y1 - y0], center = true);
        } else {
            ax = sensor_shift();
            x0 = -DX_LOGO - ax + inset;
            x1 = dx_face("R") - ax - inset;
            translate([(x0 + x1) / 2, 0])
                square([x1 - x0, 2 * hz], center = true);
        }
    }
}

// From the outer panel to the bayonet. Flare the clipped sides out to the
// flange; the sides that already fit stay at the flange diameter.
// R's lens-side edge stays on the chassis clip until it is outside the
// helicoid keep-out, then takes a steeper angle out to the flange.
module dx_arm_tube(mark) {
    a = mark == "T" ? [sensor_shift(), 0, 0] : [0, -sensor_shift(), 0];
    dir = mark == "T" ? [0, 1, 0] : [1, 0, 0];
    span = dx_back(mark) - dx_face(mark);
    x0 = dx_face(mark) - 0.4;
    zc = DX_HELI_CLEAR_D / 2 + 0.8 - x0;
    translate(a + dir * x0)
        rotate(mark == "T" ? [-90, 0, 0] : [0, 90, 0])
            union() {
                // Hold the clipped edge out past the helicoid, then flare.
                if (mark == "R" && zc > 0.4 && zc < span - 2) {
                    hull() {
                        linear_extrude(0.2)
                            dx_tube_root_2d(mark);
                        translate([0, 0, zc])
                            linear_extrude(0.2)
                                dx_tube_root_2d(mark);
                    }
                    hull() {
                        translate([0, 0, zc])
                            linear_extrude(0.2)
                                dx_tube_root_2d(mark);
                        translate([0, 0, span - 1.6])
                            linear_extrude(0.2)
                                circle(d = F_STL_OD, $fn = 96);
                        translate([0, 0, span])
                            linear_extrude(0.2)
                                circle(d = F_STL_OD, $fn = 96);
                    }
                } else {
                    hull() {
                        linear_extrude(0.2)
                            dx_tube_root_2d(mark);
                        translate([0, 0, span - 1.6])
                            linear_extrude(0.2)
                                circle(d = F_STL_OD, $fn = 96);
                        translate([0, 0, span])
                            linear_extrude(0.2)
                                circle(d = F_STL_OD, $fn = 96);
                    }
                }
            }
}

module dx_arm_bore(mark) {
    a = mark == "T" ? [sensor_shift(), 0, 0] : [0, -sensor_shift(), 0];
    dir = mark == "T" ? [0, 1, 0] : [1, 0, 0];
    difference() {
        translate(a + dir * (DX_CAV - 1))
            rotate(mark == "T" ? [-90, 0, 0] : [0, 90, 0])
                cylinder(h = dx_back(mark) - DX_CAV + 8, d = TUBE_ID);
        if (mark == "R") {
            dx_r_thread_guard();
            dx_r_sep();
        }
    }
}

// Ring around the M65 core, in the 4.25 mm lip.
module dx_r_thread_guard() {
    translate([0, -DX_LENS - 0.3, 0])
        rotate([-90, 0, 0])
            difference() {
                cylinder(h = DX_THREAD + 0.8, d = 68, $fn = 64);
                translate([0, 0, -0.2])
                    cylinder(h = DX_THREAD + 1.2, d = DX_THREAD_BORE, $fn = 64);
            }
}

// 2.6 mm of the lens-side wall, the whole way to the bayonet.
// The bore is the rest of the circle. Both cutters leave this
// strip, so the lens port does not open into the tube.
module dx_r_sep() {
    wall = 2.6;
    x0 = DX_CAV - 0.3;
    x1 = dx_back("R") + 2;
    translate([(x0 + x1) / 2, -DX_LENS + wall / 2, 0])
        cube([x1 - x0, wall, 32], center = true);
}

// Short fairing where the R tube meets the lens-side print flats.
module dx_r_join(top) {
    x  = dx_x1();
    y  = dx_y0();
    sz = top ? 1 : -1;
    zc = sz * DX_HALF_Z;
    intersection() {
        hull() {
            intersection() {
                dx_arm_tube("R");
                translate([x - 2, y + 9, sz * 20])
                    cube([16, 16, 18], center = true);
            }
            translate([x - 12, y, zc])       cube(0.4, center = true);
            translate([x, y + 10, zc])       cube(0.4, center = true);
            translate([x, y, zc - sz * 12])  cube(0.4, center = true);
        }
        translate([x - 2, y + 6, sz * 24])
            cube([20, 20, 26], center = true);
        translate([0, 30 - DX_LENS, 0])
            cube([180, 60, 160], center = true);
    }
}

// Same chord as the FXPAN cookies. Flat 27 mm above the bore at the
// bayonet, raked back to the full flange circle at the chassis face, so
// the prism nose clears and the cut dies on the wall.
module dx_flash_cut(mark) {
    keep = TUBE_FLASH_KEEP;
    full = F_STL_OD / 2;
    // Flat across the whole bayonet, then rake back to the round tube
    // at the chassis face.
    mouth = dx_back(mark) + 6;
    face = dx_face(mark);
    // Only as wide as the flange. The old 90 mm slab shaved a lip
    // off the top edge of the T and R walls.
    w = F_STL_OD + 4;
    h = 50;
    difference() {
        if (mark == "R") {
            y = -sensor_shift();
            hull() {
                translate([mouth, y, keep + h / 2])
                    cube([20, w, h], center = true);
                translate([face + 1.2, y, full + h / 2])
                    cube([2, w, h], center = true);
            }
        } else {
            x = sensor_shift();
            hull() {
                translate([x, mouth, keep + h / 2])
                    cube([w, 20, h], center = true);
                translate([x, face + 1.2, full + h / 2])
                    cube([w, 2, h], center = true);
            }
        }
        dx_outer();
    }
}

module dx_mount(mark) {
    translate(mark == "T"
            ? [sensor_shift(), dx_back(mark), 0]
            : [dx_back(mark), -sensor_shift(), 0])
        rotate(mark == "T" ? [-90, 0, 0] : [0, 90, 0])
            f_mount_on_tube(mount_clock(mark), 0, FX_FMOUNT_EXTRA);
}

module dx_lens_bore() {
    // Core of the thread, ending on the back of the crests.
    // It stops there so the plate rib in the cavity is not cored out.
    difference() {
        translate([0, -DX_LENS - 0.4, 0])
            rotate([-90, 0, 0])
                cylinder(h = DX_THREAD + 0.45, d = DX_THREAD_BORE, $fn = 96);
        dx_r_sep();
    }
}

// ScrewHole cuts its own core, which deletes the lens-side wall and
// leaves a tunnel into the R tube. This cap is the overlap of that
// core and the R bore, put back after the thread.
module dx_r_cap() {
    intersection() {
        translate([(DX_CAV + dx_back("R")) / 2,
                   (-DX_LENS - 0.3 + -19.85) / 2, 0])
            cube([dx_back("R") - DX_CAV,
                  -19.85 - (-DX_LENS - 0.3), 32], center = true);
        translate([0, -DX_LENS - 1, 0])
            rotate([-90, 0, 0])
                cylinder(h = DX_THREAD + 2.6, d = DX_THREAD_BORE + 4, $fn = 72);
    }
}

module dx_lens_thread() {
    translate([0, -DX_LENS, 0])
        rotate([-90, 0, 0])
            ScrewHole(M65_MAJOR, DX_THREAD,
                      pitch = EL180_M62_PITCH,
                      tolerance = EL180_M62_TOL,
                      rotation = [0, 0, STEM_W_CLOCK]);
}

// Fitted to the short logo wall. One material, so the old colour layers
// are a single engraving. No red line, no anamorphic block.
module dx_logo_2d() {
    f = "Futura:style=Condensed Medium";
    text("DXPAN", size = 11, font = f, halign = "center", valign = "center",
         spacing = 1.02);
    translate([0, -12])
        text("29MP", size = 6, font = f, halign = "center", valign = "center",
             spacing = 1.05);
    translate([0, -20])
        text("8870×3264    2.72:1", size = 3.6, font = f,
             halign = "center", valign = "center", spacing = 1.04);
}

module dx_logo_cut() {
    // Outside is -X. Reading direction is the viewer's left to right
    // (world -Y), up is +Z. The art is centred on that face.
    translate([-DX_LOGO - 0.2, (dx_y0() + dx_y1()) / 2, 1])
        mirror([0, 1, 0])
            rotate([0, 90, 0])
                linear_extrude(1.3)
                    rotate(90)
                        translate([0, 8])
                            dx_logo_2d();
}

// Zero's four M2.5 pilots, 58 × 23 mm. The HAT pair does not fit on this lid.
// Columns sit clear of the lid screws. Blind, so they stay above the tubes.
function dx_trig_holes() = [
    [-29, -10],
    [ 29, -10],
    [-29,  13],
    [ 29,  13]
];

module dx_trig_pilots() {
    deep = DX_HALF_Z - DX_SEAT - 1.15;
    for (p = dx_trig_holes())
        translate([p[0], p[1], DX_HALF_Z - deep])
            cylinder(h = deep + 0.2, d = TRIG_PILOT_D, $fn = 20);
}

// Same flat as the original bed corner. sx/sy point outward. top=1 is a
// top corner, so the flat faces up and out instead of down and out.
module dx_print_corner(x, y, z, sx, sy, top = 0) {
    leg = 12;
    zin = top ? -1 : 1;
    hull() {
        translate([x, y, z + zin * leg])           cube(0.4, center = true);
        translate([x - sx * leg, y, z])            cube(0.4, center = true);
        translate([x, y - sy * leg, z])            cube(0.4, center = true);
        translate([x + sx * 6, y + sy * 6, z - zin * 6]) cube(0.4, center = true);
    }
}

module dx_bed_cuts(skip_r_lens = 0) {
    z = -DX_HALF_Z;
    dx_print_corner(dx_x0(), dx_y0(), z, -1, -1);
    if (!skip_r_lens)
        dx_print_corner(dx_x1(), dx_y0(), z,  1, -1);
    dx_print_corner(dx_x0(), dx_y1(), z, -1,  1);
    dx_print_corner(dx_x1(), dx_y1(), z,  1,  1);
}

// Front top corners stay on the ledge. The rear top corners are on the lid.
module dx_ledge_top_corners(skip_r_lens = 0) {
    z = DX_HALF_Z;
    dx_print_corner(dx_x0(), dx_y0(), z, -1, -1, 1);
    if (!skip_r_lens)
        dx_print_corner(dx_x1(), dx_y0(), z,  1, -1, 1);
}

// Roof over the helicoid only. Everything aft of it, above the seat, is the lid.
module dx_top_slice() {
    translate([(dx_x0() + dx_x1()) / 2,
               (DX_LEDGE_Y + dx_y1() + 2) / 2,
               (DX_SEAT + DX_HALF_Z + 2) / 2])
        cube([dx_x1() - dx_x0() + 4,
              dx_y1() + 2 - DX_LEDGE_Y,
              DX_HALF_Z + 2 - DX_SEAT], center = true);
}

module dx_lid_taps() {
    for (p = dx_lid_screws())
        translate([p[0], p[1], DX_SEAT - DX_TAP_H])
            cylinder(h = DX_TAP_H + 0.3, d = DX_TAP_D, $fn = 24);
}

module dx_lid_top_corners() {
    z = DX_HALF_Z;
    y0 = DX_LEDGE_Y + 0.2;
    dx_print_corner(dx_x0(), y0,      z, -1, -1, 1);
    dx_print_corner(dx_x1(), y0,      z,  1, -1, 1);
    dx_print_corner(dx_x0(), dx_y1(), z, -1,  1, 1);
    dx_print_corner(dx_x1(), dx_y1(), z,  1,  1, 1);
}

module part_dx_body() {
    color("SlateGray")
    // Thread axis is +Z inside ScrewHole. Map that onto world +Y, into the
    // wall from the lens face. The cap goes on after ScrewHole, because
    // the thread core is what opens the R tube.
    union() {
    translate([0, -DX_LENS, 0])
        rotate([-90, 0, 0])
            ScrewHole(M65_MAJOR, DX_THREAD,
                      pitch = EL180_M62_PITCH,
                      tolerance = EL180_M62_TOL,
                      rotation = [0, 0, STEM_W_CLOCK])
                rotate([90, 0, 0])
                    translate([0, DX_LENS, 0])
                        difference() {
                            union() {
                                difference() {
                                    union() {
                                        difference() {
                                            dx_outer();
                                            dx_cavity();
                                        }
                                        dx_plate();
                                    }
                                    dx_bed_cuts();
                                    dx_ledge_top_corners();
                                    dx_top_slice();
                                }
                                dx_arm_tube("R");
                                dx_arm_tube("T");
                                dx_mount("R");
                                dx_mount("T");
                                dx_r_join(0);
                                dx_r_join(1);
                            }
                            dx_plate_pins();
                            dx_arm_bore("R");
                            dx_arm_bore("T");
                            dx_lens_bore();
                            dx_logo_cut();
                            dx_bed_cuts(1);
                            dx_flash_cut("R");
                            dx_flash_cut("T");
                            dx_top_slice();
                            dx_ledge_top_corners(1);
                            dx_lid_taps();
                        }
        dx_r_cap();
    }
}

// The sliced-off roof. Sits on the seat aft of the helicoid ledge.
// Countersunk M3s cut their own thread in the chassis pilots.
// Each top corner is the same print flat as the chassis bed corners.
module part_dx_lid() {
    t  = DX_HALF_Z - DX_SEAT;
    fit = 0.15;
    y0 = DX_LEDGE_Y + fit;
    x0 = dx_x0() + fit;
    x1 = dx_x1() - fit;
    y1 = dx_y1() - fit;
    csk_h = (DX_CSK_D - DX_CLR_D) / 2;
    color("DimGray")
    difference() {
        union() {
            translate([(x0 + x1) / 2, (y0 + y1) / 2,
                       DX_SEAT + t / 2])
                cube([x1 - x0, y1 - y0, t], center = true);
        }
        dx_lid_top_corners();
        for (p = dx_lid_screws()) {
            translate([p[0], p[1], DX_SEAT - 0.2])
                cylinder(h = t + 1, d = DX_CLR_D, $fn = 28);
            translate([p[0], p[1], DX_HALF_Z - csk_h])
                cylinder(h = csk_h + 0.2, d1 = DX_CLR_D, d2 = DX_CSK_D, $fn = 28);
        }
        dx_trig_pilots();
        translate([0, 0, DX_HALF_Z - STAMP_DEPTH])
            part_stamp_cut(dxp_tag("lid"), STAMP_DEPTH, 3.2);
    }
}
