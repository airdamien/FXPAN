// Section: DXPAN chassis with the travel body cap on the lens port.
DXP_INCLUDE = 1;
include <../dxpan/WATCH_ME.scad>
use <dxpan_body_cap.scad>

// Male runs +Z in cap_seated(); rotate it onto world +Y, into the lip.
translate([0, -DX_LENS, 0])
    rotate([-90, 0, 0])
        cap_seated();
