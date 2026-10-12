// =============================================================================
// lid_cap_rf.scad — the slip-on lid cap, roof raised for a framing finder
// =============================================================================
// Included from WATCH_ME.scad. Select lid_cap_rf. Same walls as lid_cap, with
// a flat top just above the frame. The extra height is solid. A framing tunnel runs
// through that solid, on the centerline, aimed at the lens (−Y).
//
// The eyehole is the round hole on the rear face, the face toward the T
// camera. It is on the outside of the cap, with a shallow countersink, so
// the eye meets the wall instead of having to enter it. The front opening
// is the 64.80 × 23.9 mm stitch at 180 mm, a pill, no range marks.
//
// Prints skirt-down. The bore is the same pill as the frame, so the roof
// only has to clear that opening.
// =============================================================================

RF_MASK   = 1.8;   // front wall, the frame
RF_PEEP_T = 3.0;   // rear wall, the eye stop
RF_PEEP_D = 6;
RF_CUP_D  = 9;     // light chamfer, still a round hole
RF_ABOVE  = 3.2;   // solid above the frame, then the flat top

function rf_half() = chassis_out() / 2 + CAP_GAP + CAP_WALL;
function rf_z_void() = CAP_SKIRT + CAP_RISE - CAP_WALL;
// Eye at the middle of the rear wall. Frame on the inner face of the mask.
function rf_L() = 2 * rf_half() - RF_PEEP_T / 2 - RF_MASK;
function rf_frame_w() = rf_L() * stitch_w() / EL_FOCAL;
function rf_frame_h() = rf_L() * SENSOR_H / EL_FOCAL;
function rf_z_axis() = rf_z_void() + 2.4 + rf_frame_h() / 2;
function rf_rise() =
    rf_z_axis() + rf_frame_h() / 2 + RF_ABOVE - CAP_SKIRT;

module rf_pill() {
    h = rf_frame_h();
    w = max(rf_frame_w(), h + 0.1);
    hull() {
        translate([-(w - h) / 2, 0]) circle(d = h, $fn = 48);
        translate([ (w - h) / 2, 0]) circle(d = h, $fn = 48);
    }
}

// Same pill as the frame, from the rear wall to the front mask.
module rf_bore() {
    span = rf_half() - RF_PEEP_T - (-rf_half() + RF_MASK);
    translate([0, rf_half() - RF_PEEP_T, rf_z_axis()])
        rotate([90, 0, 0])
            linear_extrude(span)
                rf_pill();
}

module rf_frame() {
    translate([0, -rf_half() - 1, rf_z_axis()])
        rotate([-90, 0, 0])
            linear_extrude(RF_MASK + 2.4)
                rf_pill();
}

module rf_eye() {
    translate([0, rf_half() - RF_PEEP_T - 1, rf_z_axis()])
        rotate([-90, 0, 0]) {
            cylinder(h = RF_PEEP_T + 3, d = RF_PEEP_D, $fn = 48);
            translate([0, 0, RF_PEEP_T + 0.6])
                cylinder(h = 1.6, d1 = RF_PEEP_D, d2 = RF_CUP_D, $fn = 48);
        }
}

module part_lid_cap_rf() {
    echo(str("roof rise ", round(rf_rise() * 10) / 10,
             " mm, ", round(RF_ABOVE * 10) / 10,
             " mm of wall over the frame"));
    echo(str("frame L ", round(rf_L() * 10) / 10,
             " mm, window ", round(rf_frame_w() * 10) / 10,
             " × ", round(rf_frame_h() * 10) / 10,
             " mm"));
    difference() {
        part_lid_cap(0, rf_rise(), "lid_rf", true);
        rf_bore();
        rf_frame();
        rf_eye();
    }
}
