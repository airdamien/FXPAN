// =============================================================================
// isco/WATCH_ME.scad — EL-Nikkor 180/5.6N + ISCO Ultra-Star attachment
// =============================================================================
// Lens: el_nikkor_180n.scad. Attachment: isco_ultrastar_attachment.scad.
// Open this file to preview. Read README.md for what is measured vs guessed.
// =============================================================================

include <el_nikkor_180n.scad>
include <nikkor_w_180.scad>
include <isco_ultrastar_attachment.scad>
include <isco_mount.scad>

/* [Part] */
PART = "cutaway"; // [stack:180 + attachment, mounted:Full assembly, cutaway:Full assembly section, lens:EL 180 only, attachment:ISCO only, section:ISCO cutaway, clamp:M62 clamp, nw:Nikkor-W + ISCO, nw_clamp:Nikkor-W clamp, ef100:EF 100L + ISCO, ef100_clamp:EF 100L clamp, stand:Bench stand]

/* [View] */
SHOW_GLASS = 1; // [0:hide, 1:show]
CLAMP_GAP  = 0; // extra air beyond the clamp shoulder

echo(str("EL-Nikkor 180/5.6N  overall ", front_z - rear_z,
         "  front rim z ", front_z,
         "  rear tip z ", rear_z,
         "  Ø60 past the thread ", L_PAST));
echo(str("ISCO attachment  rear thread Ø", REAR_THREAD_OD,
         "  rear tube Ø", D_REAR_TUBE,
         "  front Ø", D_FRONT,
         "  length ", L_TOTAL,
         "  (measure L_* in isco_ultrastar_attachment.scad)"));

module part_lens() {
    color("DimGray")
        el180n(show_glass = SHOW_GLASS, cut = false);
}

module part_attachment() {
    color("Goldenrod")
        isco_ultrastar(show_glass = SHOW_GLASS,
                       cut = PART == "section");
}

module part_stack() {
    part_lens();
    translate([0, 0, front_z + CLAMP_GAP])
        part_attachment();
}

// Clamp face sits on the Ø76 shoulder behind the external thread.
function mounted_attachment_z() =
    front_z - M62_LEN + shoulder_z() + CLAMP_GAP;

// Centre of the Ø90 barrel, lens coordinates (+Z toward the subject).
function saddle_along() =
    mounted_attachment_z() + z_nose() + L_NOSE / 2;

module mounted_optics(clamp_tone = "DimGray") {
    part_lens();
    translate([0, 0, front_z - M62_LEN])
        isco_clamp(clamp_tone);
    translate([0, 0, mounted_attachment_z()])
        part_attachment();
}

// Bench frame: optical axis along +Y at AXIS_H, foot on z = 0.
// Stand saddle is along its local +X, centred at (65, 50, AXIS_H).
module part_mounted(clamp_tone = "DimGray") {
    translate([0, 0, AXIS_H])
        rotate([-90, 0, 0])
            mounted_optics(clamp_tone);
    translate([50, saddle_along() - 65, 0])
        rotate([0, 0, 90])
            isco_stand();
}

// Half the assembly, cut on the vertical plane through the optical axis.
module part_cutaway() {
    difference() {
        part_mounted("DarkOrange");
        translate([0.02, -250, -30])
            cube([500, 900, 500]);
    }
}

if (PART == "mounted")
    part_mounted();
else if (PART == "cutaway")
    part_cutaway();
else if (PART == "lens")
    part_lens();
else if (PART == "attachment" || PART == "section")
    part_attachment();
else if (PART == "clamp")
    isco_clamp();
else if (PART == "nw_clamp")
    isco_clamp_nw();
else if (PART == "ef100_clamp")
    isco_clamp_ef100();
else if (PART == "ef100") {
    isco_clamp_ef100("DarkOrange");
    translate([0, 0, FLANGE_T + THREAD_POCKET])
        part_attachment();
}
else if (PART == "nw") {
    nw180(show_glass = SHOW_GLASS);
    translate([0, 0, NW_SHUTTER + NW_GROOVE])
        isco_clamp_nw("DarkOrange");
    translate([0, 0, NW_FRONT + FLANGE_T + THREAD_POCKET])
        part_attachment();
}
else if (PART == "stand")
    isco_stand();
else
    part_stack();
