// Emboss "name YYYYMMDDHHMM" — 0.4 mm nozzle, filled Bold, ~2 perimeters deep.
// STAMP is set by export_stls.sh. Preview with no stamp shows the name only.

STAMP = is_undef(STAMP) ? "" : STAMP;

STAMP_SIZE  = 3.6;
STAMP_DEPTH = 0.7;

function part_tag(name) =
    STAMP == "" ? name : str(name, " ", STAMP);

module part_stamp_2d(name, size = STAMP_SIZE) {
    text(part_tag(name), size = size,
         font = "Liberation Sans:style=Bold",
         halign = "center", valign = "center");
}

module part_stamp_cut(name, depth = STAMP_DEPTH, size = STAMP_SIZE) {
    linear_extrude(height = depth + 0.15)
        part_stamp_2d(name, size);
}

// Name over YYYYMMDDHHMM. For a narrow ring or hex flat.
module part_stamp_stack_cut(name, depth = STAMP_DEPTH, size = 2.6) {
    linear_extrude(height = depth + 0.15) {
        translate([0, STAMP == "" ? 0 : size * 0.72])
            text(name, size = size, font = "Liberation Sans:style=Bold",
                 halign = "center", valign = "center");
        if (STAMP != "")
            translate([0, -size * 0.72])
                text(STAMP, size = size, font = "Liberation Sans:style=Bold",
                     halign = "center", valign = "center");
    }
}

// Camera-side face of a port cookie (print flange on the bed).
// kind "" = stem (world down is local −Y). "R" / "T" match flange_marks.
module flange_stamp(name, kind = "", patch = 90, patch_t = 4,
                    depth = STAMP_DEPTH, size = STAMP_SIZE) {
    e = patch / 2 - 2.8;
    translate([0, 0, patch_t - depth])
        linear_extrude(height = depth + 0.15) {
            if (kind == "R")
                translate([e, 0])
                    rotate(90)
                        part_stamp_2d(name, size);
            else if (kind == "T")
                translate([0, e])
                    rotate(180)
                        part_stamp_2d(name, size);
            else
                translate([0, -e])
                    part_stamp_2d(name, size);
        }
}

// Outer +Z of a square plate, along −Y.
module plate_stamp(name, w, t, depth = STAMP_DEPTH, size = STAMP_SIZE) {
    translate([0, -(w / 2 - 3.6), t - depth])
        part_stamp_cut(name, depth, size);
}

// Inner floor along the back (−X). Up when the chassis prints floor-down.
module box_floor_stamp(name, s, wall, depth = STAMP_DEPTH, size = STAMP_SIZE) {
    translate([-(s / 2 - wall - 4.2), 0, -s / 2 + wall - depth])
        rotate(-90)
            part_stamp_cut(name, depth, size);
}

// Into a −Y face (outside, toward the lens).
module wall_ny_stamp(name, y, z, depth = STAMP_DEPTH, size = STAMP_SIZE) {
    translate([0, y - 0.05, z])
        rotate([-90, 0, 0])
            part_stamp_cut(name, depth, size);
}
