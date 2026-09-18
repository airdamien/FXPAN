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
module f_rev_thread_cut(h = undef) {
    _h = is_undef(h) ? F_REV_LEN + 0.3 : h;
    ScrewThread(F_REV_MAJOR, _h,
                pitch = F_REV_PITCH,
                tolerance = F_REV_TOL,
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
