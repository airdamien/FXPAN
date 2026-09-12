#!/usr/bin/env bash
# Export printable STLs.
#   ./export_stls.sh [part ...]              panorama V → stls/
#   ./export_stls.sh --bsplit [part ...]     50/50 plate → stls/bsplit/
#   ./export_stls.sh --hybrid [part ...]     pano L (one 50/50) → stls/hybrid/
#
# Camera tubes export twice:
#   arm_r.stl / arm_t.stl / arm_l.stl     female 52×0.75 (reverse ring)
#   arm_r_f.stl / arm_t_f.stl / arm_l_f.stl  integrated F-bayonet
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
scad=$root/openscad/WATCH_ME.scad
out=$root/stls
default_parts=(chassis stem arm_l arm_l_f arm_r arm_r_f lid mirror_tray shims elnikkor_adapter)

if [[ "${1:-}" == "--bsplit" ]]; then
    shift
    scad=$root/openscad/bsplit/WATCH_ME.scad
    out=$root/stls/bsplit
    default_parts=(chassis stem arm_r arm_r_f arm_t arm_t_f lid bs_tray shims elnikkor_adapter)
elif [[ "${1:-}" == "--hybrid" ]]; then
    shift
    scad=$root/openscad/hybrid/WATCH_ME.scad
    out=$root/stls/hybrid
    default_parts=(chassis stem arm_r arm_r_f arm_t arm_t_f lid hybrid_tray shims elnikkor_adapter)
fi

if [[ -n "${OPENSCAD:-}" && -x "$OPENSCAD" ]]; then
    osc=$OPENSCAD
elif [[ -x /Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD ]]; then
    osc=/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD
elif command -v openscad >/dev/null; then
    osc=$(command -v openscad)
else
    echo "OpenSCAD not found. Set OPENSCAD or install the app." >&2
    exit 1
fi

if [[ $# -gt 0 ]]; then
    parts=("$@")
else
    parts=("${default_parts[@]}")
fi

mkdir -p "$out"

for req in "${parts[@]}"; do
    mount=0
    scad_part=$req
    dest_stem=$req
    case $req in
        arm_l_f|arm_r_f|arm_t_f)
            scad_part=${req%_f}
            mount=1
            dest_stem=$req
            ;;
    esac
    dest=$out/$dest_stem.stl
    echo "export $dest_stem (ARM_MOUNT=$mount) -> $dest"
    "$osc" -o "$dest" --export-format binstl \
        -D "PART=\"$scad_part\"" -D "ARM_MOUNT=$mount" "$scad"
done

echo "done. print chassis floor-down; tubes flange-on-bed (F-bayonet up)."
echo "$out"
