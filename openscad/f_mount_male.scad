// Male Nikon F bayonet — camera mounts onto this (lens-rear style).
// Use f_mount_male_solid() when unioning into a chassis tube end.

include <params.scad>

module f_mount_lug() {
    rotate_extrude(angle = F_LUG_SWEEP)
        translate([F_THROAT / 2, 0])
            square([(F_LUG_OD - F_THROAT) / 2, F_LUG_T]);
}

// Standalone test print (has bolt circle)
module f_mount_male(register_t = F_REGISTER_T) {
    difference() {
        f_mount_male_solid(register_t = register_t, boss = 0);
        for (a = [30, 150, 270])
            rotate([0, 0, a])
                translate([F_LUG_OD / 2 + 1.5, 0, -0.1])
                    cylinder(h = register_t + 0.2, d = 3.2);
    }
}

// Solid mount for union into chassis. Local +Z = toward camera (away from knife).
// boss = extra cylinder behind register that fuses into the arm tube.
module f_mount_male_solid(register_t = F_REGISTER_T, boss = 12) {
    difference() {
        union() {
            if (boss > 0)
                translate([0, 0, -boss])
                    cylinder(h = boss + 0.01, d = TUBE_OD);
            // register flange (camera seats against z=0..register_t outer face at z=register_t? )
            // Camera mount face is at z=0 coming from -Z tube; bayonet grows +Z into camera.
            // Actually: tube approaches from -Z. Register rear is at z=0, face toward camera at z=register_t? 
            // Standard: register plane is the face the camera's mount flange seats on.
            // Lugs are on the camera side of that plane.
            // So: boss/tube at z<0, register disk from z=-epsilon to z=0 is the seat? 
            // Nikon: lens male has register face; camera female seats against it.
            // Our male: register face at z=0 facing camera (+Z), material of flange is z=-register_t..0
            // Wait current code had flange at z=0..register_t then lugs at register_t.
            // Keep that convention: flange cylinder z=0..register_t, lugs at z=register_t, camera approaches from +Z.
            // Tube attaches at z<=0.
            translate([0, 0, 0])
                cylinder(h = register_t, d = max(F_LUG_OD + 10, TUBE_OD));
            translate([0, 0, register_t])
                cylinder(h = F_LUG_T + 1.2, d = F_THROAT);
            translate([0, 0, register_t])
                for (a = [0, 120, 240])
                    rotate([0, 0, a - F_LUG_SWEEP / 2])
                        f_mount_lug();
        }
        // optical bore — F_BORE at mount (NOT TUBE_ID, or lugs vanish)
        translate([0, 0, -boss - 0.1])
            cylinder(h = boss + register_t + F_LUG_T + 2, d = F_BORE);
        // release-pin notch
        translate([0, -F_LUG_OD / 2, register_t + F_LUG_T / 2])
            cube([F_LOCK_NOTCH_W, F_LOCK_NOTCH_D * 2, F_LUG_T + 0.2], center = true);
    }
}
