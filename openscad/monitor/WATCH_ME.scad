// =============================================================================
// monitor/WATCH_ME.scad  — easel on the lid, Pi on the case back
// =============================================================================
// Screen toward T (+Y). Rails print flat. Open this file.
// =============================================================================

include <params.scad>
use <monitor.scad>
use <display_mount.scad>

/* [View] */
SHOW_MOUNT = 1; // [0:hide, 1:show]
SHOW_PI = 1; // [0:hide, 1:show]
PRINT_LAYOUT = 0; // [0:on lid, 1:rails flat]
PRINT_CASE_BACK = 0; // [0:hide, 1:holed Wormfingers bottom]
PRINT_SUNSHADE = 0; // [0:hide, 1:clip-on hood]

if (PRINT_CASE_BACK)
    monitor_bottom();
else if (PRINT_LAYOUT)
    display_mount_print();
else if (PRINT_SUNSHADE)
    sunshade_print();
else {
    if (SHOW_MOUNT)
        display_mount();
    monitor_easel() {
        monitor_ghost();
        sunshade();
        if (SHOW_PI) {
            monitor_pi();
        }
    }
}
