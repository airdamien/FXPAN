// F-mount interface for FXPAN 65.
//
// This is a local copy of openscad/f_mount_male.scad rather than a `use` of
// it, because that file `include`s the top-level openscad/params.scad — and
// with `use` its modules keep those values (F_BORE 40.3, TUBE_ID 52, TUBE_OD
// 68), not this body's (44.0 / 46 / 58). A 14.4 mm shift needs 46.8 mm at the
// flange, so a 40.3 mm bore would vignette the outer corner of both frames.
//
// Printed mouth: Archive-663 mountLensBase (CC BY-NC-SA 4.0)
//   https://github.com/Archive-663/lensMounts  (Nikon F / STL)
// CAD, not the old scanned f-mount_raw.stl, so a through-bore is safe.
// As shipped the lips are 40 mm and the bayonet throat is 43.5 mm. Do not
// difference() this mesh: a bore coincident with that throat turns the
// barrel into a stack of hairline slots. The 40 mm lip is what enters the
// camera, and it is the printed mouth. Metal reverse ring is still 44 mm
// / f/8.4. ARM_MOUNT = 0 stays the default.
//
// Parent must include params.scad and lib/threads.scad.

F_STL_FILE   = "../../f-mount_archive663.stl";
F_STL_ZMIN   = 0;
F_STL_ZMAX   = 7.75;
F_STL_HEIGHT = F_STL_ZMAX - F_STL_ZMIN;
F_STL_OD     = 62;     // adapter flange; peg into the tube is F_PEG_OD
F_PEG_OD     = 52;     // sits in the tube wall (TUBE_ID 46 / TUBE_OD 58)
F_STL_THROAT = 40;     // the lip. The bayonet behind it is already 43.5 in the mesh.
// F_COLLAR_OD is in params.scad: the lock lugs are sized off it, and
// fxp_tray.scad reaches the port geometry without seeing this file.
F_COLLAR_Z0  = -1.6;
F_COLLAR_H   = 2.0;

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
    // 180° so the lock-pin recess sits at +X, matching f_pin_az.
    // Imported whole. A bore through this mesh splits the barrel wall
    // into the gap slots.
    rotate([0, 0, 180])
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

// Back at z=0 (tube end); register face at z=3 (62 mm flange front).
// Mesh is imported +180° so the lock-pin recess is at +X. T/R still add
// 0 / −90; F_MOUNT_CLOCK is extra if a dry-fit is still off.
// back_extra deepens the rear support without moving the register face.
module f_mount_on_tube(clock = 0, peg_face = 0, back_extra = 0) {
    translate([0, 0, -F_PEG_H - back_extra])
        difference() {
            cylinder(h = F_PEG_H + back_extra + 0.4, d = F_PEG_OD);
            translate([0, 0, -0.1])
                cylinder(h = F_PEG_H + back_extra + 0.6, d = F_BORE);
            if (peg_face > 0)
                translate([0, 0, -0.1])
                    cylinder(h = peg_face + back_extra + 0.1,
                             d = F_PEG_OD + 0.4);
        }
    translate([0, 0, F_COLLAR_Z0])
        difference() {
            cylinder(h = F_COLLAR_H, d = F_COLLAR_OD);
            translate([0, 0, -0.1])
                cylinder(h = F_COLLAR_H + 0.2, d = F_BORE);
        }
    rotate([0, 0, clock])
        f_mount_stl_raw();
}
