// ===================================================================
// FXPAN MULTI-SENSOR HARDWARE FACEPLATE ASSEMBLY (3D MANIFOLD MESH)
// ===================================================================

$fn = 60; // Smooths out all curved boundaries and fillets

// --- GLOBAL CALIBRATION METRICS (In Millimeters) ---
PLATE_W = 150.0; // Total chassis face width
PLATE_H = 90.0; // Total chassis face height
PLATE_T = 4.0; // Thickness of structural plate shell
EMBOSS_D = 0.8; // Depth of color insertion (exactly 4 layers at 0.2mm layer height)
CLEARANCE = 0.04; // Zero-tolerance precision air gap clearance for multi-material slicing

// --- PRE-ALIGNED VIEWPORT RENDER SELECTION ---
// Change these booleans to isolate individual parts for exporting to STL files
render_chassis_base = true;
render_gold_inlay = true;
render_white_inlay = true;

// ===================================================================
// PRIMARY RENDERING LOOP CONTROL BUILDER
// ===================================================================
union() {
if (render_chassis_base) {
color("DimGray") chassis_with_pockets();
}
if (render_gold_inlay) {
color("Gold") translate([0, 0, (PLATE_T/2) - EMBOSS_D]) logo_gold_segments();
}
if (render_white_inlay) {
color("White") translate([0, 0, (PLATE_T/2) - EMBOSS_D]) logo_white_segments();
}
}

// ===================================================================
// METRIC BUILD MODULES (MODULE DEFINITIONS)
// ===================================================================

// Master structural plate with a clean boolean cut out for the logo inserts
module chassis_with_pockets() {
difference() {
// Core structural backing plate matching the rounded style of the D800 body prism
linear_extrude(height = PLATE_T, center = true) {
minkowski() {
square([PLATE_W - 12, PLATE_H - 12], center = true);
circle(r = 6);
}
}

// Subtracts the expanded paths to make clean structural alignment slots
translate([0, 0, (PLATE_T/2) - EMBOSS_D]) {
minkowski() {
union() {
logo_gold_segments();
logo_white_segments();
}
// Creates an air-gap safety expansion block
cube([CLEARANCE * 2, CLEARANCE * 2, EMBOSS_D * 3], center = true);
}
}
}
}

// Extrudes the FX frame, interlocking X, and flowing baseline swoops
module logo_gold_segments() {
linear_extrude(height = EMBOSS_D + 0.1) {
translate([-48, -12, 0]) { // Zero-Origin alignment offset
// Part A: The FX Container Frame Bracket
polygon(points=[[0,55],[55,55],[45,43],[15,43],[15,31],[40,31],[38,19],[15,19],[15,2],[0,-10]]);

// Part B: The Sharp Interlocking X Assembly
polygon(points=[[35,43],[52,43],[77,13],[102,43],[119,43],[87,3],[102,-17],[85,-17],[70,5],[50,-17],[33,-17],[60,13]]);

// Part C: The Sweeping Underline Tail (Polygonal Bezier Approximation)
polygon(points=[
[82.5,9.5],[92.5,23.5],[110,31],[205,31],[205,25],[142.5,25],[110,16.5],[92.5,-2.5],
[75,-25],[57.5,-25],[85,4.5],[82.5,9.5]
]);
}
}
}

// Extrudes the custom wide-tracked P, A, and N typographic geometries
module logo_white_segments() {
linear_extrude(height = EMBOSS_D + 0.1) {
translate([-48, -12, 0]) {
// LETTER 'P' (With internal window cutout punched out)
difference() {
polygon(points=[[107,3],[135,3],[149,-4],[149,-22],[135,-30],[121,-30],[121,-55],[107,-55]]);
polygon(points=[[121,-11],[132,-11],[135,-15],[132,-22],[121,-22]]);
}

// LETTER 'A' (With structural bridge arch punched out)
difference() {
polygon(points=[[156,-55],[177,3],[191,3],[212,-55],[195,-55],[190,-40],[173,-40],[168,-55]]);
polygon(points=[[176,-26],[187,-26],[182,-2]]);
}

// LETTER 'N'
polygon(points=[[224,-55],[224,3],[238,3],[266,-33],[266,3],[280,3],[280,-55],[266,-55],[238,-19],[238,-55]]);
}
}
}
