// Taking-lens visualization. No redistributable EL-Nikkor mesh exists;
// this is the kit-lens barrel cut from José Pedro's Nikon DSLR,
// Printables #1733741, CC BY-NC-SA 4.0, scaled toward an EL-Nikkor 135
// envelope (~62 mm OD). Not an F-Nikkor on the path — stand-in only.
// https://www.printables.com/model/1733741-nikon-dslr-camera-model-3d-printable
//
// Origin = rear / L39 face. +Z toward the subject.

TAKING_STL   = "taking_lens.stl";
TAKING_SCALE = 0.70;
TAKING_RX    = 0;
TAKING_RY    = 0;
TAKING_RZ    = 0;
TAKING_TX    = 0;
TAKING_TY    = 0;
TAKING_TZ    = 0;

module taking_lens() {
    translate([TAKING_TX, TAKING_TY, TAKING_TZ])
        rotate([TAKING_RX, TAKING_RY, TAKING_RZ])
            scale(TAKING_SCALE)
                import(TAKING_STL, convexity = 6);
}
