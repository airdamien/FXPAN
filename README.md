# Nikon Duals — panoramic T chassis

Two Nikon D7000 bodies + one taking lens, field-split with first-surface mirrors.

**Infinity-capable:** M42/M39 helicoid + enlarger/LF lens on the stem (not an F-Nikkor).  
Path budget: `PATH_TOTAL = fold + 46.5 ≈ 136.5 mm` — see [OPTICS.md](OPTICS.md).

## Watch while editing

1. Open [`openscad/WATCH_ME.scad`](openscad/WATCH_ME.scad) in OpenSCAD
2. Enable **Design → Automatic Reload and Preview**
3. Tweak [`openscad/params.scad`](openscad/params.scad) (`EXPLODED`, distances, `PART`)

`./export_stls.sh` writes print STLs to `stls/`. Print the box floor-down. Print `stem` / `arm_l` / `arm_r` with the square flange on the bed, then bolt each flange onto the flat wall with 4× M3 + hex nuts.

## Files

| Path | Role |
|------|------|
| `openscad/WATCH_ME.scad` | Live assembly / STL export switch |
| `openscad/params.scad` | All critical dimensions |
| `openscad/f_mount_male.scad` | Male F bayonet for D7000s |
| `openscad/mirror_tray.scad` | 45° FSM trays + knife |
| `openscad/shims.scad` | Focus-match rings |
| `f-mount_raw.stl` | Reference scan for bayonet calibration |
| `OPTICS.md` / `bom.md` | Path math + shopping list |
