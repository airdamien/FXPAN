// Female Nikon F — a lens bayonets onto this (camera-throat style).
// Lug sectors from f-mount_raw.stl, then −60° to the insert clock.
// Dry-fit the 50 and add F_STEM_CLOCK if the index locks off.

F_FEM_THROAT    = 44.4;
F_FEM_SLOT_ID   = 47.6;
F_FEM_GROOVE_OD = 47.4;
F_FEM_LIP_ID    = 44.8;
F_FEM_REG_T     = 2.4;
F_FEM_GROOVE_H  = 2.3;
F_FEM_BACK_H    = 3.0;
F_FEM_PIN_D     = 2.4;

function f_fem_h(back = F_FEM_BACK_H) = back + F_FEM_GROOVE_H + F_FEM_REG_T;

// Insert slots (looking +Z). Locked lugs sit 60° CW from these.
function f_fem_slots() = [
    [328, 66],
    [ 90, 62],
    [208, 74]
];

// Lips over the locked lug seats (STL 30–90 / 152–208 / 270–338).
function f_fem_lips() = [
    [ 32, 56],
    [154, 52],
    [274, 62]
];

module f_fem_pie(a0, sweep, r, h) {
    rotate([0, 0, a0])
        rotate_extrude(angle = sweep)
            square([r, h]);
}

module f_fem_ring(a0, sweep, r0, r1, h) {
    rotate([0, 0, a0])
        rotate_extrude(angle = sweep)
            translate([r0, 0])
                square([r1 - r0, h]);
}

module f_mount_female_solid(od = 68, back = F_FEM_BACK_H) {
    h = f_fem_h(back);
    z_gr = back;
    difference() {
        union() {
            difference() {
                cylinder(h = h, d = od);
                translate([0, 0, z_gr])
                    cylinder(h = F_FEM_GROOVE_H, d = F_FEM_GROOVE_OD);
                translate([0, 0, z_gr + F_FEM_GROOVE_H - 0.05])
                    for (s = f_fem_slots())
                        f_fem_pie(s[0], s[1], F_FEM_SLOT_ID / 2,
                                  F_FEM_REG_T + 0.2);
                translate([0, 0, h - 0.55])
                    cylinder(h = 0.65, d1 = F_FEM_SLOT_ID,
                             d2 = F_FEM_SLOT_ID + 1.2);
            }
            translate([0, 0, z_gr])
                for (s = f_fem_lips())
                    f_fem_ring(s[0], s[1], F_FEM_LIP_ID / 2,
                               F_FEM_GROOVE_OD / 2 + 0.2,
                               F_FEM_GROOVE_H + 0.05);
            translate([0, od / 2 - 0.4, h - 0.6])
                sphere(d = 2.4);
        }
        translate([0, 0, -0.1])
            cylinder(h = h + 0.2, d = F_FEM_THROAT);
        translate([0, 0, z_gr + F_FEM_GROOVE_H / 2])
            rotate([0, 90, 0])
                cylinder(h = od / 2 + 1, d = F_FEM_PIN_D);
    }
}

module f_mount_female(clock = 0, od = 68, back = F_FEM_BACK_H) {
    rotate([0, 0, clock])
        f_mount_female_solid(od, back);
}

// Preview stand-in: AI-s 50/1.8 envelope. Origin = F register, +Z subject.
module f50_ghost() {
    cylinder(h = 9, d = 63);
    translate([0, 0, 9])
        cylinder(h = 28, d = 61);
    translate([0, 0, 37])
        cylinder(h = 6, d = 54);
}
