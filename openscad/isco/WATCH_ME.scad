// =============================================================================
// isco/WATCH_ME.scad — view the EL-Nikkor 180/5.6N
// =============================================================================
// The lens itself is el_nikkor_180n.scad. Include that from anywhere else.
// Open this file to look at it. Read README.md for the sheet versus this lens.
// =============================================================================

include <el_nikkor_180n.scad>

/* [Part] */
PART = "lens"; // [lens:Metal envelope, section:Cutaway]

/* [View] */
SHOW_GLASS = 1; // [0:hide, 1:show]

echo(str("EL-Nikkor 180/5.6N  overall ", front_z - rear_z,
         "  front rim z ", front_z,
         "  rear tip z ", rear_z,
         "  Ø60 past the thread ", L_PAST));
echo(str("register ", FFD, "  rear vertex ", rear_vertex_z,
         "  front vertex ", front_vertex_z,
         "  (rim-to-vertex ", front_z - front_vertex_z, ", sheet 1.8)"));

color("DimGray")
    el180n(show_glass = SHOW_GLASS, cut = PART == "section");
