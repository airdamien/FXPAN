#!/usr/bin/env bash
# Export printable STLs from openscad/WATCH_ME.scad into stls/
# Usage: ./export_stls.sh [part ...]
# Default parts: chassis stem arm_l arm_r lid mirror_tray shims
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
scad=$root/openscad/WATCH_ME.scad
out=$root/stls

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
    parts=(chassis stem arm_l arm_r lid mirror_tray shims)
fi

mkdir -p "$out"

for part in "${parts[@]}"; do
    dest=$out/$part.stl
    echo "export $part -> $dest"
    "$osc" -o "$dest" --export-format binstl -D "PART=\"$part\"" "$scad"
done

echo "done. print chassis floor-down; tubes cookie-down."
echo "$out"
