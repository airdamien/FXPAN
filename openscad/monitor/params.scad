// HAMTYSAN HCIK101V.CC — Amazon B0B9M5SCG4
// 10.1" 1024×600 IPS capacitive, HDMI + micro-USB (power/touch).
// https://www.amazon.com/dp/B0B9M5SCG4
// Sources and sibling drawings: docs/monitor/

PANEL_W = 235.0;      // OEM / UK listing / Heng Cheng
PANEL_H = 143.0;
PANEL_T = 7.3;        // glass + backlight. Heng Cheng CTP stack lists 10.4
AA_W    = 222.72;     // same 1024×600 glass family (Innolux N101L6 / Amson)
AA_H    = 125.28;
VA_W    = 226.37;     // Midas MDT1010AC-HDMI (HDMI+CTP sibling)
VA_H    = 128.7;
DEPTH_WITH_BOARD = 20; // Thingiverse #6621767 measured this ASIN (board + jacks)

// Four backside holes. Pitch is NOT on the HAMTYSAN sheet.
// Community cases use M3. Sibling HDMI+CTP drawing has ~3.7 / 4.9 corner insets.
// Measure the unit before printing a mount.
HOLE_INSET_X = 5;
HOLE_INSET_Y = 5;
HOLE_D       = 3.2;
