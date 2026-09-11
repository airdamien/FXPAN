#!/usr/bin/env bash
# Export printable STLs.
#   ./export_stls.sh [part ...]              panorama V → stls/
#   ./export_stls.sh --bsplit [part ...]     50/50 plate → stls/bsplit/
#   ./export_stls.sh --hybrid [part ...]     pano L (one 50/50) → stls/hybrid/
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
scad=$root/openscad/WATCH_ME.scad
out=$root/stls
default_parts=(chassis stem arm_l arm_r lid mirror_tray shims elnikkor_adapter)

if [[ "${1:-}" == "--bsplit" ]]; then
    shift
    scad=$root/openscad/bsplit/WATCH_ME.scad
    out=$root/stls/bsplit
    default_parts=(chassis stem arm_r arm_t lid bs_tray shims elnikkor_adapter)
elif [[ "${1:-}" == "--hybrid" ]]; then
    shift
    scad=$root/openscad/hybrid/WATCH_ME.scad
    out=$root/stls/hybrid
    default_parts=(chassis stem arm_r arm_t lid hybrid_tray shims elnikkor_adapter)
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

for part in "${parts[@]}"; do
    dest=$out/$part.stl
    echo "export $part -> $dest"
    "$osc" -o "$dest" --export-format binstl -D "PART=\"$part\"" "$scad"
done

echo "done. print chassis floor-down; tubes cookie-down."
echo "$out"
