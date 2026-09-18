// F-mount interface for FXPAN 65.
//
// This is a local copy of openscad/f_mount_male.scad rather than a `use` of
// it, because that file `include`s the top-level openscad/params.scad — and
// with `use` its modules keep those values (F_BORE 40.3, TUBE_ID 52, TUBE_OD
// 68), not this body's (44.0 / 46 / 60). A 14.4 mm shift needs 46.8 mm at the
// flange, so a 40.3 mm bore would vignette the outer corner of both frames.
// The bayonet mesh itself is shared and untouched.
//
// Do NOT difference() the imported mesh — that shreds preview and render.
// Peg / collar / tine pads are unions only.
//
// Parent must include params.scad and lib/threads.scad.

F_STL_FILE   = "../../f-mount_raw.stl";
F_STL_ZMIN   = -1.750;
F_STL_ZMAX   = 5.000;
F_STL_HEIGHT = F_STL_ZMAX - F_STL_ZMIN;
F_STL_OD     = 52;
// Measured off the mesh: its narrowest inner diameter is 38.00 mm, not the
// 44 mm of a real F throat. Opening F_BORE only widens the peg and collar
// behind it, so the printed bayonet is the stop, and the mesh cannot be
// difference()d.
//
// At a 14.4 mm shift that makes the printed F a fitting aid and nothing more:
// the frame corners need 38.47 mm even stopped fully down, so 38.00 never
// passes the whole frame at any aperture. The metal reverse ring keeps the
// real 44 mm throat and is clean from f/8.4, which is why ARM_MOUNT = 0 is
// the default. See bom.md.
F_STL_THROAT = 38.0;
F_COLLAR_OD  = 62;
F_COLLAR_Z0  = -1.6;
F_COLLAR_H   = 2.0;
// Body lock pin (measured ~1.95 mm). The groove bridges the open floor under
// the STL fork tines so the body cannot roll once bayoneted.
F_PIN_W       = 1.88;   // CAD; slicer ~+0.05 → 1.93
F_PIN_FLOOR_Z = 0;
F_PIN_SEAT_Z1 = 1.35;
F_PIN_X_IN    = 23.8;   // groove inner radius — clear of a 44.0 mm bore
F_PIN_X_OUT   = 29.4;

// Female M52×0.75 in the tube wall (Fotodiox reverse ring).
// difference() this — NOT ScrewHole, which bloats the OD.
//
// tooth_height is the point of this. Left at its default it equals the pitch
// and ScrewThread cuts a sharp full-height V, 0.650 mm deep radially at
// P = 0.75, where a real M52×0.75 female is 0.406 mm. The extra quarter
// millimetre of crest reaches into the ring's thread roots, so the ring
// rides on those crests instead of on its flanks and will not start square.
// F_REV_TOOTH truncates it back, and the clearance moves onto the major
// where it belongs. See params.scad, and print PART=ringgauge first.
module f_rev_thread_cut(h = undef, clear = undef) {
    _h = is_undef(h) ? F_REV_LEN + 0.3 : h;
    _c = is_undef(clear) ? F_REV_CLEAR : clear;
    ScrewThread(F_REV_MAJOR + _c, _h,
                pitch = F_REV_PITCH,
                tolerance = 0,
                tooth_height = F_REV_TOOTH,
                tooth_angle = 30);
}

module f_mount_stl_raw() {
    translate([0, 0, -F_STL_ZMIN])
        import(F_STL_FILE, convexity = 12);
}

// Raw forks sit at +X. The pin is 90° left of flange-mark-up (look −Z, CCW).
function f_pin_az(up_az) = up_az + 90;

// Radial groove on the tube-end annulus (reverse-ring seat) at the lock-pin
// azimuth. Engraved, so the ring still sits flat; clock the ring to it.
module f_pin_line_cut(out_len, up_az) {
    t = 0.65;
    r0 = TUBE_ID / 2 + 1.4;
    r1 = TUBE_OD / 2 - 0.4;
    rotate([0, 0, f_pin_az(up_az)])
        translate([(r0 + r1) / 2, 0, out_len - t / 2])
            cube([r1 - r0, 0.9, t + 0.1], center = true);
}

// Two M3 grub screws pinch the ring barrel (roll + clock). Both azimuths are
// taken off camera-up and straddle the far side of the tube, because camera-up
// is where the OD is raked back for the pentaprism. See REV_LOCK_* in
// params.scad for why the nut sits outboard of the thread rather than in it.
function rev_lock_az(up_az, s) = up_az + REV_LOCK_HOME + s * REV_LOCK_SPREAD / 2;

// What the lock actually needs is room for the nut slot to floor above the
// cookie face, not a whole F_REV_LEN of tube. The old test was the latter, and
// the T arm is bs_t_comp() shorter than the R arm for the glass path -- 7.697
// against 8 -- so it lost both set screws to a 0.3 mm rounding and there was
// nothing holding that ring's clock at all.
function rev_lock_ok(out_len) =
    out_len - F_REV_LEN / 2 - REV_LOCK_NUT_AF / 2 - 0.3 >= 0.3;

module rev_lock_cuts(out_len, up_az = 180) {
    for (s = [-1, 1])
        rev_lock_cut_one(out_len, rev_lock_az(up_az, s));
}

// Lugs for those nuts. Full tube height, so each one grows straight off the
// cookie with the arm printed mouth-up and carries no overhang at all, and
// level with the mouth so the ring still seats flat on the end annulus. The
// outer face stays on the rev_lock_r_out() cylinder and the width flares by
// REV_LOCK_FLARE on the way down to the plate — a taper that widens toward
// the bed, which is free.
module rev_lock_bosses(out_len, up_az = 180) {
    for (s = [-1, 1])
        rev_lock_boss_one(out_len, rev_lock_az(up_az, s));
}

module rev_lock_boss_one(out_len, az) {
    r = rev_lock_r_out();
    module lug(w) {
        translate([r / 2, 0])
            offset(2.0)
                offset(-2.0)
                    square([r + 1, w], center = true);
    }
    rotate([0, 0, az])
        intersection() {
            difference() {
                cylinder(h = out_len, r = r);
                translate([0, 0, -0.1])
                    cylinder(h = out_len + 0.2, d = TUBE_ID);
            }
            hull() {
                linear_extrude(0.02)
                    lug(REV_LOCK_W + 2 * REV_LOCK_FLARE);
                translate([0, 0, out_len - 0.02])
                    linear_extrude(0.02)
                        lug(REV_LOCK_W);
            }
        }
}

module rev_lock_cut_one(out_len, az) {
    z0 = out_len - F_REV_LEN / 2;          // screw axis, mid-engagement
    ri = rev_lock_r_in();
    nw = REV_LOCK_NUT_AF;
    nt = REV_LOCK_NUT_T;
    // Nut drops in from the mouth, so the slot has to be open up there.
    floor_z = z0 - nw / 2 - 0.3;
    rotate([0, 0, az]) {
        translate([0, 0, z0])
            rotate([0, 90, 0])
                cylinder(h = rev_lock_r_out() + 1.5, d = PORT_SCREW_D);
        translate([ri + nt / 2, 0, (out_len + 0.2 + floor_z) / 2])
            cube([nt, nw, out_len + 0.2 - floor_z], center = true);
    }
}

// Tine roots only (y ≈ ±2.55). The pin slot is bridged by f_pin_seat_floor().
module f_fork_pads() {
    for (s = [-1, 1])
        translate([26.6, s * 2.38, 0.72])
            cube([5.5, 2.45, 1.44], center = true);
}

// Solid floor under the lock forks with a y-centred pin groove (+X).
module f_pin_seat_floor() {
    z0 = F_PIN_FLOOR_Z;
    z1 = F_PIN_SEAT_Z1;
    x0 = F_PIN_X_IN;
    x1 = F_PIN_X_OUT;
    difference() {
        translate([(x0 + x1) / 2, 0, (z0 + z1) / 2])
            cube([x1 - x0, 6.0, z1 - z0 + 0.05], center = true);
        translate([(x0 + x1) / 2, 0, (z0 + z1) / 2])
            cube([x1 - x0 + 0.4, F_PIN_W + 0.05, z1 - z0 + 0.1], center = true);
    }
}

// Back at z=0 (tube end); register face at z=1.75. Clock so the raw mesh's
// +X forks sit 90° left of flange-mark-up — that is where the body pin is.
// back_extra deepens the rear support without moving the register face.
module f_mount_on_tube(clock = 0, peg_face = 0, back_extra = 0) {
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
