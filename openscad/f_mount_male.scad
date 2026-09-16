// F-mount = your STL, untouched on the camera face. Peg / collar / tine
// pads are unions only — difference() on the import shreds preview/render.

include <params.scad>

// Female M52×0.75 in the tube wall (Fotodiox reverse ring). Parent must
// include lib/threads.scad. difference() this — NOT ScrewHole (that bloats OD).
module f_rev_thread_cut(h = undef) {
    _h = is_undef(h) ? F_REV_LEN + 0.3 : h;
    ScrewThread(F_REV_MAJOR, _h,
                pitch = F_REV_PITCH,
                tolerance = F_REV_TOL,
                tooth_angle = 30);
}

F_STL_FILE   = "../f-mount_raw.stl";
// Flange OD circle is already at XY origin; old CX/CY offsets shoved the
// bayonet off the arm bore.
F_STL_ZMIN   = -1.750;
F_STL_ZMAX   = 5.000;
F_STL_HEIGHT = F_STL_ZMAX - F_STL_ZMIN;
F_STL_OD     = 52;
// Meat behind the register (z=1.75). Covers fork roots (r=29) without
// growing the lugs or filling the ~2.4 mm pin slot.
F_PEG_H      = 5.5;
F_COLLAR_OD  = 62;
F_COLLAR_Z0  = -1.6;
F_COLLAR_H   = 2.0;
// Body lock pin (measured ~1.95 mm). Groove bridges the open floor under
// the STL fork tines so the body cannot roll once bayoneted.
F_PIN_W      = 1.95;    // CAD; slicer ~+0.05 → 2.00 (pin 1.95)
F_PIN_FLOOR_Z = 0;
F_PIN_SEAT_Z1 = 1.35;   // pin pocket depth under fork tines
F_PIN_X_IN   = 23.8;    // groove inner (toward bore), +X fork azimuth
F_PIN_X_OUT  = 29.4;

module f_mount_stl_raw() {
    translate([0, 0, -F_STL_ZMIN])
        import(F_STL_FILE, convexity = 12);
}

// Do NOT difference() the imported mesh — that shreds preview/render.
module f_mount_male_solid(register_t = 0, boss = 4) {
    if (boss > 0)
        translate([0, 0, -boss])
            difference() {
                cylinder(h = boss + 0.4, d = F_STL_OD);
                translate([0, 0, -0.1])
                    cylinder(h = boss + 0.6, d = F_BORE);
            }
    color("Goldenrod")
        f_mount_stl_raw();
}

module f_mount_male(register_t = 0) {
    f_mount_male_solid(boss = 0);
}

// Raw forks at +X. Pin is 90° left of flange-mark-up (look −Z, CCW).
function f_pin_az(up_az) = up_az + 90;

// Radial groove on the tube-end annulus (reverse-ring seat), at the
// lock-pin azimuth. Engraved so the ring still sits flat; clock to it.
module f_pin_line_cut(out_len, up_az) {
    t = 0.65;
    r0 = TUBE_ID / 2 + 2.6;
    r1 = TUBE_OD / 2 - 0.4;
    rotate([0, 0, f_pin_az(up_az)])
        translate([(r0 + r1) / 2, 0, out_len - t / 2])
            cube([r1 - r0, 0.9, t + 0.1], center = true);
}

// Two M3 set screws 120° apart pinch the ring barrel (roll + clock).
module rev_lock_cuts(out_len, az = 180) {
    for (a = [0, 120])
        rev_lock_cut_one(out_len, az + a);
}

module rev_lock_cut_one(out_len, az) {
    z0 = out_len - F_REV_LEN / 2;
    r_mid = (TUBE_ID + TUBE_OD) / 4;
    nw = 5.5 + 0.2;
    nt = 2.4 + 0.2;
    floor_z = z0 - 5.5 / 2 - 0.2;
    rotate([0, 0, az]) {
        translate([0, 0, z0])
            rotate([0, 90, 0])
                cylinder(h = TUBE_OD / 2 + 1, d = PORT_SCREW_D);
        translate([r_mid, 0, (out_len + floor_z) / 2])
            cube([nt, nw, out_len - floor_z + 0.2], center = true);
    }
}

// Tine roots only (y ≈ ±2.55). Pin slot bridged by f_pin_seat_floor().
module f_fork_pads() {
    for (s = [-1, 1])
        translate([26.6, s * 2.55, 0.65])
            cube([5.5, 2.2, 1.3], center = true);
}

// Solid floor under lock forks with a 2.0 mm y-centered pin groove (+X).
module f_pin_seat_floor() {
    z0 = F_PIN_FLOOR_Z;
    z1 = F_PIN_SEAT_Z1;
    x0 = F_PIN_X_IN;
    x1 = F_PIN_X_OUT;
    difference() {
        translate([(x0 + x1) / 2, 0, (z0 + z1) / 2])
            cube([x1 - x0, 5.4, z1 - z0 + 0.05], center = true);
        translate([(x0 + x1) / 2, 0, (z0 + z1) / 2])
            cube([x1 - x0 + 0.4, F_PIN_W + 0.05, z1 - z0 + 0.1], center = true);
    }
}

// Back at z=0 (tube end). Register face at z=1.75. Lock-pin forks at +X
// in the raw mesh (not +Y). Clock so those forks sit 90° left of
// flange-mark-up — that is where the D7000 body pin actually is.
// Bored peg sinks into TUBE_ID; collar / pads stay behind the register.
// peg_face: recede the tube-facing peg by this much so a PETG liner can
// sit there without overlapping PCTG. Do not difference the STL.
module f_mount_on_tube(clock = 0, peg_face = 0, back_extra = 0) {
    // FX body fitting can require a deeper rear support while preserving
    // the calibrated register face and bayonet geometry.
    translate([0, 0, -F_PEG_H - back_extra])
        difference() {
            cylinder(h = F_PEG_H + back_extra + 0.4, d = F_STL_OD);
            translate([0, 0, -0.1])
                cylinder(h = F_PEG_H + back_extra + 0.6, d = F_BORE);
            if (peg_face > 0)
                translate([0, 0, -0.1])
                    cylinder(h = peg_face + back_extra + 0.1,
                             d = F_STL_OD + 0.4);
        }
    translate([0, 0, F_COLLAR_Z0])
        difference() {
            cylinder(h = F_COLLAR_H, d = F_COLLAR_OD);
            translate([0, 0, -0.1])
                cylinder(h = F_COLLAR_H + 0.2, d = F_BORE);
        }
    rotate([0, 0, clock]) {
        f_mount_stl_raw();
        f_fork_pads();
        f_pin_seat_floor();
    }
}

// Light-path PETG: sleeve in the F throat + washer on the peg’s tube face.
// Unions only — sits inside F_BORE, does not difference the import.
module f_mount_path_liner(lining = 1.6) {
    id = F_BORE - 2 * lining;
    translate([0, 0, -F_PEG_H])
        difference() {
            union() {
                cylinder(h = F_PEG_H + F_STL_HEIGHT + 0.3, d = F_BORE);
                cylinder(h = lining, d = F_STL_OD);
            }
            translate([0, 0, -0.2])
                cylinder(h = F_PEG_H + F_STL_HEIGHT + 0.8, d = id);
        }
}
