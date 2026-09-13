// Raspberry Pi 4 Model B visualization mesh.
// Envelope from the official mechanical drawing (85×56, holes 58×49):
// https://datasheets.raspberrypi.com/rpi4/raspberry-pi-4-mechanical-drawing.pdf
//
// After this module: PCB bottom at Z=0. Holes match pi4_holes().
// USB/ethernet toward −X. HDMI/USB-C toward −Y. GPIO toward +Y.

PI4_STL = "pi4_body.stl";

function pi4_holes() = [
    [42.5 - 3.5,  3.5 - 28],
    [42.5 - 61.5, 3.5 - 28],
    [42.5 - 3.5,  52.5 - 28],
    [42.5 - 61.5, 52.5 - 28]
];

module pi4_body() {
    // Raw Printables mesh: USB +X, chips +Y, width in Z.
    // +20 X lands the 58×49 holes on pi4_holes().
    translate([20, 0, 0])
        rotate([0, 0, 180])
            rotate([90, 0, 0])
                import(PI4_STL, convexity = 8);
}
