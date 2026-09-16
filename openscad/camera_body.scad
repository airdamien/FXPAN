// Assembly ghost: D7000 DX or D800 FX.
// Callers must pass which= explicitly — `use`d files cannot see
// SHOW_BODIES / FX_MODE from WATCH_ME (OpenSCAD scope).
// which: 1 = D7000, 2 = D800

use <d7000_body.scad>
use <d800_body.scad>

module camera_body(roll = 0, which = 1) {
    if (which >= 2)
        d800_body(roll);
    else
        d7000_body(roll);
}
