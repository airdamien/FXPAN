#!/usr/bin/env bash
# Export printable STLs.
#   ./export_stls.sh [part ...]              panorama V → stls/v/
#   ./export_stls.sh --bsplit [part ...]     50/50 plate → stls/bsplit/
#   ./export_stls.sh --hybrid-shift [part ...] shifted-DX pano L → stls/hybrid_shift/
#   ./export_stls.sh --hybrid-shift-fx [part ...] shifted-FX D800 → stls/hybrid_shift_fx/
#   ./export_stls.sh --fxpan [part ...]      FXPAN 65 (75 mm plate) → stls/fxpan/
#   ./export_stls.sh --shadowgraph [part ...] same-image T / shadowgraph R → stls/hybrid_shadowgraph/
#   ./export_stls.sh --efhybrid [part ...]   FF 5D III EF pano L → stls/EFhybrid/
#   ./export_stls.sh --ehybrid [part ...]    FF A7 E pano L → stls/Ehybrid/
#   ./export_stls.sh --monitor               easel rails + case back + sunshade → stls/monitor/
#   ./export_stls.sh --isco [part ...]       EL180 + ISCO attachment → stls/isco/
#   ./export_stls.sh --tools                 bench tools → stls/tools/
#   focus_sled / focus_anchor → stls/tools/ (also in every chassis default list)
#   case_back is the Wormfingers bottom with easel + Pi holes.
#   sunshade → stls/monitor/ (also in hybrid / hybrid-shift / shadowgraph defaults)
#
# Each part is embossed with its name and the render minute (YYYYMMDDHHMM).
#
# Camera tubes export twice:
#   arm_r.stl / arm_t.stl / arm_l.stl     female 52×0.75 (reverse ring)
#   arm_r_f.stl / arm_t_f.stl / arm_l_f.stl  integrated F-bayonet
# Hybrid F 50 also exports 16 mm shorter tubes:
#   arm_r_s.stl / arm_t_s.stl / arm_r_sf.stl / arm_t_sf.stl
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
scad=$root/openscad/WATCH_ME.scad
out=$root/stls/v
default_parts=(chassis stem arm_l arm_l_f arm_r arm_r_f lid mirror_tray shims elnikkor_adapter focus_sled focus_anchor)
fx_extra=()
tail_note="print chassis floor-down; tubes flange-on-bed (F-bayonet up); brace floor-down (insert from the bed); *_inner = PETG lining, *_outer = PCTG shell; display_mount rails on their flat face; case_back outer-back down; focus_sled −X chevron on the bed."

if [[ "${1:-}" == "--bsplit" ]]; then
    shift
    scad=$root/openscad/bsplit/WATCH_ME.scad
    out=$root/stls/bsplit
    default_parts=(chassis stem arm_r arm_r_f arm_t arm_t_f lid bs_tray shims elnikkor_adapter focus_sled focus_anchor)
elif [[ "${1:-}" == "--hybrid" ]]; then
    shift
    scad=$root/openscad/hybrid/WATCH_ME.scad
    out=$root/stls/hybrid
    default_parts=(chassis stem stem_f50 arm_r arm_r_f arm_t arm_t_f arm_r_s arm_r_sf arm_t_s arm_t_sf lid display_mount case_back sunshade hybrid_tray brace shims elnikkor_adapter el180_adapter focus_sled focus_anchor)
elif [[ "${1:-}" == "--hybrid-shift" ]]; then
    shift
    scad=$root/openscad/hybrid_shift/WATCH_ME.scad
    out=$root/stls/hybrid_shift
    default_parts=(chassis chassis_inner chassis_outer chassis_logo stem stem_inner stem_outer stem_el180 stem_el180_inner stem_el180_outer arm_r arm_r_inner arm_r_outer arm_r_f arm_r_f_inner arm_r_f_outer arm_t arm_t_inner arm_t_outer arm_t_f arm_t_f_inner arm_t_f_outer lid lid_inner lid_outer display_mount case_back sunshade hybrid_tray brace shims elnikkor_adapter el180_adapter focus_sled focus_anchor)
elif [[ "${1:-}" == "--hybrid-shift-fx" ]]; then
    shift
    scad=$root/openscad/hybrid_shift/WATCH_ME.scad
    out=$root/stls/hybrid_shift_fx
    fx_extra=(-D "FX_MODE=1")
    default_parts=(chassis chassis_inner chassis_outer chassis_logo chassis_logo_fx chassis_logo_word chassis_logo_mp chassis_logo_rule chassis_logo_spec arm_r arm_r_inner arm_r_outer arm_r_f arm_r_f_inner arm_r_f_outer arm_t arm_t_inner arm_t_outer arm_t_f arm_t_f_inner arm_t_f_outer lid lid_inner lid_outer brace hybrid_tray stem_el180_inf stem_el180_inf_inner stem_el180_inf_outer)
elif [[ "${1:-}" == "--fxpan" ]]; then
    shift
    scad=$root/openscad/fxpan/WATCH_ME.scad
    out=$root/stls/fxpan
    default_parts=(chassis chassis_inner chassis_outer chassis_logo chassis_logo_fx chassis_logo_word chassis_logo_outline chassis_logo_mp chassis_logo_rule chassis_logo_spec chassis_logo_ana_mp chassis_logo_ana_rule chassis_logo_ana chassis_logo_stripe stem stem_inner stem_outer stem_el180_inf stem_el180_inf_inner stem_el180_inf_outer arm_r arm_r_inner arm_r_outer arm_r_f arm_r_f_inner arm_r_f_outer arm_t arm_t_inner arm_t_outer arm_t_f arm_t_f_inner arm_t_f_outer arm_r_h arm_r_h_inner arm_r_h_outer arm_t_h arm_t_h_inner arm_t_h_outer fmount_h_r fmount_h_t cam_helicoid lid lid_inner lid_outer display_mount fxp_tray base cradle_r cradle_t baffle ringgauge shims el180_adapter)
    tail_note="FXPAN 65: print ringgauge FIRST and set F_REV_CLEAR from it — the M52 mouth is the one fit this body cannot recover from. Then chassis floor-down; arms flange-on-bed (camera mouth up); lid outer face down; tray floor-down; base and cradles flat (inserts and screw heads from the bed); baffles and gauge flat. *_inner = PETG lining, *_outer = PCTG shell; chassis_logo_* drop into the chassis pocket as separate filaments."
elif [[ "${1:-}" == "--shadowgraph" ]]; then
    shift
    scad=$root/openscad/hybrid_shadowgraph/WATCH_ME.scad
    out=$root/stls/hybrid_shadowgraph
    default_parts=(chassis stem arm_r arm_r_f arm_t arm_t_f lid display_mount case_back sunshade hybrid_tray shims elnikkor_adapter focus_sled focus_anchor)
elif [[ "${1:-}" == "--monitor" ]]; then
    shift
    scad=$root/openscad/monitor/WATCH_ME.scad
    out=$root/stls/monitor
    default_parts=(display_mount case_back sunshade)
elif [[ "${1:-}" == "--efhybrid" ]]; then
    shift
    scad=$root/openscad/EFhybrid/WATCH_ME.scad
    out=$root/stls/EFhybrid
    default_parts=(chassis stem arm_r arm_r_f arm_t arm_t_f lid hybrid_tray shims elnikkor_adapter focus_sled focus_anchor)
elif [[ "${1:-}" == "--ehybrid" ]]; then
    shift
    scad=$root/openscad/Ehybrid/WATCH_ME.scad
    out=$root/stls/Ehybrid
    default_parts=(chassis stem arm_r arm_r_f arm_t arm_t_f lid hybrid_tray shims elnikkor_adapter focus_sled focus_anchor)
elif [[ "${1:-}" == "--isco" ]]; then
    shift
    scad=$root/openscad/isco/WATCH_ME.scad
    out=$root/stls/isco
    default_parts=(el_nikkor_180n isco_ultrastar isco_clamp isco_stand)
    tail_note="ISCO: envelope STLs for clearance only — measure L_* on the attachment and update isco_ultrastar_attachment.scad before trusting fit."
elif [[ "${1:-}" == "--tools" ]]; then
    shift
    scad=$root/openscad/focus_sled.scad
    out=$root/stls/tools
    default_parts=(focus_sled focus_anchor)
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
stamp=$(date +%Y%m%d%H%M)
echo "STAMP=$stamp"

for req in "${parts[@]}"; do
    if [[ "$req" == "focus_sled" ]]; then
        dest=$root/stls/tools/focus_sled.stl
        mkdir -p "$(dirname "$dest")"
        echo "export focus_sled -> $dest"
        "$osc" -o "$dest" --export-format binstl \
            -D "SHOW_RULERS=0" -D "STAMP=\"$stamp\"" \
            "$root/openscad/focus_sled.scad"
        continue
    fi
    if [[ "$req" == "focus_anchor" ]]; then
        dest=$root/stls/tools/focus_anchor.stl
        mkdir -p "$(dirname "$dest")"
        echo "export focus_anchor -> $dest"
        "$osc" -o "$dest" --export-format binstl \
            -D "SHOW_GHOSTS=0" -D "STAMP=\"$stamp\"" \
            "$root/openscad/focus_anchor.scad"
        continue
    fi
    if [[ "$req" == "case_back" ]]; then
        dest=$out/case_back.stl
        echo "export case_back -> $dest"
        "$osc" -o "$dest" --export-format binstl \
            -D "PRINT_CASE_BACK=1" -D "STAMP=\"$stamp\"" \
            "$root/openscad/monitor/WATCH_ME.scad"
        continue
    fi
    if [[ "$req" == "display_mount" && "$scad" == *"/monitor/WATCH_ME.scad" ]]; then
        dest=$out/display_mount.stl
        echo "export display_mount -> $dest"
        "$osc" -o "$dest" --export-format binstl \
            -D "PRINT_LAYOUT=1" -D "STAMP=\"$stamp\"" "$scad"
        continue
    fi
    if [[ "$req" == "sunshade" ]]; then
        dest=$root/stls/monitor/sunshade.stl
        mkdir -p "$(dirname "$dest")"
        echo "export sunshade -> $dest"
        "$osc" -o "$dest" --export-format binstl \
            -D "PRINT_SUNSHADE=1" -D "STAMP=\"$stamp\"" \
            "$root/openscad/monitor/WATCH_ME.scad"
        continue
    fi
    mount=0
    arms=0
    shell=full
    logo_layer=
    core=$req
    dest_stem=$req
    if [[ "$req" == *_inner ]]; then
        shell=inner
        core=${req%_inner}
        dest_stem=$req
    elif [[ "$req" == *_outer ]]; then
        shell=outer
        core=${req%_outer}
        dest_stem=$req
    fi
    scad_part=$core
    case $core in
        chassis_logo)
            scad_part=chassis
            shell=logo
            logo_layer=all
            ;;
        chassis_logo_fx)
            scad_part=chassis
            shell=logo
            logo_layer=fx
            ;;
        chassis_logo_word)
            scad_part=chassis
            shell=logo
            logo_layer=word
            ;;
        chassis_logo_outline)
            scad_part=chassis
            shell=logo
            logo_layer=outline
            ;;
        chassis_logo_mp)
            scad_part=chassis
            shell=logo
            logo_layer=mp
            ;;
        chassis_logo_rule)
            scad_part=chassis
            shell=logo
            logo_layer=rule
            ;;
        chassis_logo_spec)
            scad_part=chassis
            shell=logo
            logo_layer=spec
            ;;
        chassis_logo_ana_mp)
            scad_part=chassis
            shell=logo
            logo_layer=ana_mp
            ;;
        chassis_logo_ana_rule)
            scad_part=chassis
            shell=logo
            logo_layer=ana_rule
            ;;
        chassis_logo_ana)
            scad_part=chassis
            shell=logo
            logo_layer=ana
            ;;
        chassis_logo_stripe)
            scad_part=chassis
            shell=logo
            logo_layer=stripe
            ;;
        arm_l_f|arm_r_f|arm_t_f)
            scad_part=${core%_f}
            mount=1
            ;;
        arm_r_sf|arm_t_sf)
            scad_part=${core%_sf}
            mount=1
            arms=1
            ;;
        arm_r_s|arm_t_s)
            scad_part=${core%_s}
            arms=1
            ;;
        el_nikkor_180n)
            scad_part=lens
            ;;
        isco_ultrastar)
            scad_part=attachment
            ;;
        isco_clamp)
            scad_part=clamp
            ;;
        isco_stand)
            scad_part=stand
            ;;
    esac
    dest=$out/$dest_stem.stl
    echo "export $dest_stem (ARM_MOUNT=$mount ARMS=$arms SHELL=$shell) -> $dest"
    cmd=(
        "$osc" -o "$dest" --export-format binstl
        -D "PART=\"$scad_part\"" -D "ARM_MOUNT=$mount" -D "ARMS=$arms"
        -D "SHELL=\"$shell\""
        -D "STAMP=\"$stamp\""
    )
    if ((${#fx_extra[@]})); then
        cmd+=("${fx_extra[@]}")
    fi
    if [[ -n "$logo_layer" ]]; then
        cmd+=(-D "LOGO_LAYER=\"$logo_layer\"")
    fi
    cmd+=("$scad")
    "${cmd[@]}"
done

echo "done. $tail_note"
echo "$out"
