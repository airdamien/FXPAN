#!/usr/bin/env python3
"""Generate schematic SVG, board layouts, and KiCad project for gpio_trigger."""

from __future__ import annotations

import heapq
import json
import math
import re
import subprocess
import textwrap
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KICAD_ROOT = Path("/Applications/KiCad/KiCad.app/Contents/SharedSupport")
SHEET_UUID = "60b82a67-605d-4edc-a527-425f55d0316b"
PROJECT_NAME = "gpio_trigger"


def uid() -> str:
    return str(uuid.uuid4())


def write_schematic_svg(path: Path) -> None:
    svg = """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1100 720" font-family="ui-monospace, Menlo, Consolas, monospace" font-size="13">
  <defs>
    <marker id="arrow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
      <path d="M0,0 L6,3 L0,6 z" fill="#333"/>
    </marker>
    <style>
      .wire { stroke:#1a1a1a; stroke-width:2; fill:none }
      .bus { stroke:#0b5; stroke-width:2.5; fill:none }
      .iso { stroke:#c33; stroke-width:2; stroke-dasharray:8 6; fill:none }
      .box { fill:#f8f8f8; stroke:#333; stroke-width:1.5 }
      .pi { fill:#e8f4ff; stroke:#2563eb; stroke-width:2 }
      .cam { fill:#fff7ed; stroke:#c2410c; stroke-width:2 }
      .lbl { fill:#111 }
      .sub { fill:#555; font-size:11px }
      .title { font-size:20px; font-weight:bold; fill:#111 }
    </style>
  </defs>
  <rect width="1100" height="720" fill="#fff"/>
  <text x="40" y="36" class="title">Pi dual TRS Nikon trigger — electrical schematic</text>
  <text x="40" y="58" class="sub">3.5 mm TRS × 2 · BCM 20/21 both cameras, or cut JP1/JP2 and use BCM 26/19 for camera B</text>

  <!-- Pi -->
  <rect x="40" y="90" width="170" height="150" class="pi" rx="8"/>
  <text x="58" y="118" class="lbl" font-weight="bold">Raspberry Pi GPIO</text>
  <text x="58" y="142" class="lbl">BCM 20 (pin 38) — FOCUS</text>
  <text x="58" y="166" class="lbl">BCM 21 (pin 40) — SHUTTER</text>
  <text x="58" y="190" class="lbl">GND (pin 39) · J2 alt: pin 37 focus, pin 35 shutter</text>
  <text x="58" y="220" class="sub">3.3 V logic · no battery</text>

  <!-- isolation barrier -->
  <line x1="320" y1="70" x2="320" y2="650" class="iso"/>
  <text x="328" y="88" class="sub" fill="#c33">optical isolation — Pi GND ≠ camera GND</text>

  <!-- focus bus -->
  <line x1="210" y1="138" x2="300" y2="138" class="bus"/>
  <text x="230" y="128" class="sub" fill="#0b5">FOCUS</text>

  <!-- shutter bus -->
  <line x1="210" y1="162" x2="300" y2="162" class="bus"/>
  <text x="228" y="152" class="sub" fill="#0b5">SHUTTER</text>

  <!-- gnd bus -->
  <line x1="210" y1="186" x2="300" y2="186" class="wire"/>
  <line x1="300" y1="186" x2="300" y2="600" class="wire"/>
  <text x="218" y="176" class="sub">GND</text>

  <!-- channel template positions -->
"""

    channels = [
        ("U1", "R1", "J1", "CAM A", 110, "focus", "RING"),
        ("U2", "R2", "J1", "CAM A", 190, "shutter", "TIP"),
        ("U3", "R3", "J2", "CAM B", 270, "focus", "RING"),
        ("U4", "R4", "J2", "CAM B", 350, "shutter", "TIP"),
    ]

    def opto_block(x: int, y: int, name: str, rname: str, jack: str, role: str, contact: str) -> str:
        gpio_y = 138 if role == "focus" else 162
        parts = [
            f'  <line x1="300" y1="{gpio_y}" x2="{x}" y2="{gpio_y}" class="bus"/>',
            f'  <rect x="{x}" y="{y}" width="28" height="14" fill="#fff" stroke="#333"/>',
            f'  <text x="{x+4}" y="{y+11}" font-size="10">{rname}</text>',
            f'  <text x="{x+34}" y="{y+11}" class="sub">330Ω</text>',
            f'  <line x1="{x+28}" y1="{y+7}" x2="{x+90}" y2="{y+7}" class="wire"/>',
            # 4N35 box
            f'  <rect x="{x+90}" y="{y-30}" width="120" height="90" class="box" rx="4"/>',
            f'  <text x="{x+98}" y="{y-12}" font-weight="bold">{name} 4N35</text>',
            f'  <text x="{x+98}" y="{y+4}" class="sub">1 anode ← {rname}</text>',
            f'  <text x="{x+98}" y="{y+20}" class="sub">2 cathode → GND</text>',
            f'  <text x="{x+98}" y="{y+36}" class="sub">4 emitter → {jack} SLEEVE</text>',
            f'  <text x="{x+98}" y="{y+52}" class="sub">5 collector → {jack} {contact}</text>',
            f'  <line x1="{x+90}" y1="{y+7}" x2="{x+98}" y2="{y+7}" class="wire"/>',
            f'  <line x1="{x+98}" y1="{y+7}" x2="{x+98}" y2="{y+4}" class="wire"/>',
            f'  <line x1="{x+210}" y1="{y+52}" x2="895" y2="{y+52}" class="wire"/>',
            f'  <text x="{x+285}" y="{y+48}" class="sub">{jack}.{contact}</text>',
            f'  <line x1="{x+98}" y1="{y+20}" x2="300" y2="186" class="wire"/>',
        ]
        return "\n".join(parts)

    body = []
    for u, r, j, cam, y, role, contact in channels:
        body.append(opto_block(340, y, u, r, j, role, contact))

    # Jacks
    jacks = """
  <rect x="900" y="180" width="150" height="120" class="cam" rx="8"/>
  <text x="918" y="208" font-weight="bold">J1 — 3.5 mm TRS</text>
  <text x="918" y="232" class="lbl">TIP ← U2 (shutter)</text>
  <text x="918" y="252" class="lbl">RING ← U1 (focus)</text>
  <text x="918" y="272" class="lbl">SLEEVE ← U1E + U2E</text>
  <text x="918" y="292" class="sub">→ D800 top (T)</text>

  <rect x="900" y="380" width="150" height="120" class="cam" rx="8"/>
  <text x="918" y="408" font-weight="bold">J2 — 3.5 mm TRS</text>
  <text x="918" y="432" class="lbl">TIP ← U4 (shutter)</text>
  <text x="918" y="452" class="lbl">RING ← U3 (focus)</text>
  <text x="918" y="472" class="lbl">SLEEVE ← U3E + U4E</text>
  <text x="918" y="492" class="sub">→ D800 right (R)</text>

  <rect x="40" y="560" width="1020" height="130" fill="#fafafa" stroke="#ccc"/>
  <text x="58" y="588" font-weight="bold">Sequence (gpio_seq.py)</text>
  <text x="58" y="612" class="lbl">1. FOCUS high → ring→sleeve on both jacks</text>
  <text x="58" y="634" class="lbl">2. wait 50–200 ms</text>
  <text x="58" y="656" class="lbl">3. SHUTTER high → tip→sleeve · pulse · release shutter · release focus</text>
  <text x="560" y="612" class="sub">Nikon 10-pin: pin 9 focus, pin 4 shutter, pin 6 ground</text>
  <text x="560" y="634" class="sub">If tip/ring swapped on cable, swap GPIO 20/21 at Pi only</text>
"""
    path.write_text(svg + "\n".join(body) + jacks + "\n</svg>\n")


def write_layout_perf(path: Path) -> None:
    """50×70 mm perfboard inside Hammond 1591TBK — component placement."""
    w, h = 900, 620
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" font-family="ui-monospace, Menlo, Consolas, monospace" font-size="12">',
        "<defs><style>.grid{stroke:#ddd;stroke-width:0.5}.hole{fill:#fff;stroke:#999;stroke-width:0.8}"
        ".comp{fill:#eef;stroke:#333;stroke-width:1.2}.jack{fill:#fed;stroke:#c2410c;stroke-width:1.5}"
        ".wire-f{stroke:#0a7;stroke-width:2;fill:none}.wire-s{stroke:#06c;stroke-width:2;fill:none}"
        ".wire-g{stroke:#333;stroke-width:2;fill:none}.encl{fill:none;stroke:#666;stroke-width:2;stroke-dasharray:6 4}"
        ".dim{stroke:#888;stroke-width:1;marker-end:url(#a)}</style>"
        '<marker id="a" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6 z" fill="#888"/></marker></defs>',
        f'<rect width="{w}" height="{h}" fill="#fff"/>',
        '<text x="30" y="32" font-size="18" font-weight="bold">Perfboard layout — top view (mm)</text>',
        '<text x="30" y="52" fill="#555">50×70 mm veroboard · 2.54 mm pitch · fits Hammond 1591TBK</text>',
    ]
    # enclosure 120x80 outline (scaled 3 px/mm), offset
    ox, oy, scale = 80, 80, 3
    ex, ey = 120 * scale, 80 * scale
    lines.append(f'<rect x="{ox}" y="{oy}" width="{ex}" height="{ey}" class="encl" rx="4"/>')
    lines.append(f'<text x="{ox+8}" y="{oy+16}" fill="#666">1591TBK 120×80 mm</text>')

    # perfboard 50x70 centered
    pb_w, pb_h = 50 * scale, 70 * scale
    pbx = ox + (ex - pb_w) / 2
    pby = oy + 30
    lines.append(f'<rect x="{pbx}" y="{pby}" width="{pb_w}" height="{pb_h}" fill="#f5f5f0" stroke="#333" stroke-width="1.5"/>')
    lines.append(f'<text x="{pbx+4}" y="{pby-6}" font-weight="bold">Perfboard 50×70</text>')

    # grid holes
    for row in range(0, 28):
        for col in range(0, 20):
            cx = pbx + 4 + col * 2.54 * scale
            cy = pby + 4 + row * 2.54 * scale
            if cx > pbx + pb_w - 4 or cy > pby + pb_h - 4:
                continue
            lines.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="1.8" class="hole"/>')

    def place(name: str, cx_mm: float, cy_mm: float, cw_mm: float, ch_mm: float, cls: str = "comp") -> None:
        x = pbx + cx_mm * scale
        y = pby + cy_mm * scale
        lines.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{cw_mm*scale:.1f}" height="{ch_mm*scale:.1f}" class="{cls}" rx="2"/>'
        )
        lines.append(f'<text x="{x+3:.1f}" y="{y+ch_mm*scale/2+4:.1f}" font-size="10">{name}</text>')

    # component positions in mm from perfboard top-left
    place("U1", 4, 8, 7.6, 10)
    place("U2", 4, 28, 7.6, 10)
    place("U3", 4, 48, 7.6, 10)
    place("U4", 4, 58, 7.6, 10)
    for i, u in enumerate(["R1", "R2", "R3", "R4"], 1):
        place(u, 14, 6 + (i - 1) * 17, 3, 6)

    # J1 → top camera: right wall, plug faces out (+X)
    jx_r = ox + ex + 8
    lines.append(f'<rect x="{jx_r:.1f}" y="{oy+35:.1f}" width="36" height="54" class="jack" rx="3"/>')
    lines.append(f'<text x="{jx_r+4:.1f}" y="{oy+65:.1f}" font-size="11">J1 TRS → D800 top</text>')
    # J2 → right camera: left wall, plug faces out (-X)
    jx_l = ox - 44
    lines.append(f'<rect x="{jx_l:.1f}" y="{oy+120:.1f}" width="36" height="54" class="jack" rx="3"/>')
    lines.append(f'<text x="{jx_l+4:.1f}" y="{oy+150:.1f}" font-size="11">J2 TRS → D800 right</text>')

    # harness
    lines.append(f'<rect x="{ox-50}" y="{oy+100}" width="40" height="30" fill="#e8f4ff" stroke="#2563eb"/>')
    lines.append(f'<text x="{ox-46}" y="{oy+120}" font-size="10">Pi harness</text>')
    lines.append(f'<text x="{ox-46}" y="{oy+134}" font-size="9">38 39 40</text>')

    # legend
    leg_y = 480
    lines += [
        f'<text x="30" y="{leg_y}" font-weight="bold">Wire routing (see netlist.csv)</text>',
        f'<line x1="30" y1="{leg_y+20}" x2="80" y2="{leg_y+20}" class="wire-f"/><text x="88" y="{leg_y+24}">FOCUS (GPIO 20)</text>',
        f'<line x1="30" y1="{leg_y+40}" x2="80" y2="{leg_y+40}" class="wire-s"/><text x="88" y="{leg_y+44}">SHUTTER (GPIO 21)</text>',
        f'<line x1="30" y1="{leg_y+60}" x2="80" y2="{leg_y+60}" class="wire-g"/><text x="88" y="{leg_y+64}">GND (LED cathodes only)</text>',
        f'<text x="30" y="{leg_y+95}" fill="#555">Drill 6 mm panel holes for jacks on short wall · keep camera-side leads short</text>',
        "</svg>",
    ]
    path.write_text("\n".join(lines) + "\n")


def write_layout_pcb(path: Path) -> None:
    """PCB outline is a 78×45 mm stepped board. Socket tab stays clear of Ethernet."""
    scale = 6
    bw, bh = 78, 45
    ox, oy = 60, 60
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 700" font-family="ui-monospace, Menlo, Consolas, monospace" font-size="11">',
        "<style>.brd{fill:#1a472a;stroke:#0f2d1a;stroke-width:2}.cu{fill:#c9a227;opacity:.35}"
        ".pad{fill:#c9a227;stroke:#8a6d12}.silk{fill:none;stroke:#fff;stroke-width:.8}"
        ".outline{fill:none;stroke:#333;stroke-width:2}.hole{fill:#222}</style>",
        '<rect width="800" height="700" fill="#2d5016"/>',
        '<text x="60" y="36" fill="#fff" font-size="18" font-weight="bold">PCB layout — plugs onto Pi GPIO (78×45 mm, stepped)</text>',
        '<text x="60" y="54" fill="#ccc">J1 and J2 exit the pin-1 end, away from Ethernet · 2×20 socket on the bottom · D1–D4 camera lamps</text>',
        f'<rect x="{ox}" y="{oy}" width="{bw*scale}" height="{bh*scale}" class="brd" rx="3"/>',
        f'<rect x="{ox}" y="{oy}" width="{bw*scale}" height="{bh*scale}" class="outline" rx="3"/>',
    ]

    def mm(x: float, y: float, w: float, h: float, label: str, pad: bool = True) -> None:
        px, py = ox + x * scale, oy + y * scale
        cls = "pad" if pad else "silk"
        lines.append(f'<rect x="{px:.1f}" y="{py:.1f}" width="{w*scale:.1f}" height="{h*scale:.1f}" class="{cls}" rx="1"/>')
        lines.append(f'<text x="{px+2:.1f}" y="{py+h*scale/2+3:.1f}" fill="#fff" font-size="9">{label}</text>')

    # 4N35 footprints DIP-6 7.62mm
    for i, name in enumerate(["U1", "U2", "U3", "U4"]):
        mm(4, 6 + i * 12, 7.62, 10, name)

    for i, name in enumerate(["R1", "R2", "R3", "R4"]):
        mm(16, 7 + i * 12, 5, 2.5, name)

    mm(2, 16, 16, 10, "← J1")
    mm(2, 4, 16, 10, "← J2")
    mm(22, 2, 54, 8, "J3 Pi 2x20  pin1 left", pad=True)
    mm(62, 28, 5, 5, "1 focus", pad=True)
    mm(70, 28, 5, 5, "1 shutter", pad=True)
    mm(62, 36, 5, 5, "2 focus", pad=True)
    mm(70, 36, 5, 5, "2 shutter", pad=True)
    lines.append(f'<text x="{ox}" y="{oy+bh*scale+24}" fill="#fff">J3: 1=GND 2=FOCUS 3=SHUTTER · 2.54 mm header · mount on board edge to Pi dupont</text>')
    lines.append(f'<text x="{ox}" y="{oy+bh*scale+42}" fill="#ccc">Gerbers: open kicad/gpio_trigger.kicad_pcb in KiCad → File → Fabrication Outputs</text>')
    lines.append("</svg>")
    path.write_text("\n".join(lines) + "\n")


def write_netlist(path: Path) -> None:
    rows = [
        "net,from,to",
        "FOCUS,GPIO20,R1.1",
        "FOCUS,GPIO20,JP1.1",
        "J2_FOCUS,JP1.2,R3.1",
        "B_FOCUS,JP1.3,GPIO26",
        "FOCUS,R1.2,U1.1",
        "J2_FOCUS,R3.2,U3.1",
        "SHUTTER,GPIO21,R2.1",
        "SHUTTER,GPIO21,JP2.1",
        "J2_SHUTTER,JP2.2,R4.1",
        "B_SHUTTER,JP2.3,GPIO19",
        "SHUTTER,R2.2,U2.1",
        "J2_SHUTTER,R4.2,U4.1",
        "GND,GPIO_GND,U1.2",
        "GND,GPIO_GND,U2.2",
        "GND,GPIO_GND,U3.2",
        "GND,GPIO_GND,U4.2",
        "CAM_GND_A,U1.4,J1.SLEEVE",
        "CAM_GND_A,U2.4,J1.SLEEVE",
        "CAM_GND_B,U3.4,J2.SLEEVE",
        "CAM_GND_B,U4.4,J2.SLEEVE",
        "J1_RING,U1.5,J1.RING",
        "J1_TIP,U2.5,J1.TIP",
        "J2_RING,U3.5,J2.RING",
        "J2_TIP,U4.5,J2.TIP",
        "FOCUS,GPIO20,R5.1",
        "FOCUS,R5.2,D1.A",
        "GND,D1.K,GPIO_GND",
        "SHUTTER,GPIO21,R6.1",
        "SHUTTER,R6.2,D2.A",
        "GND,D2.K,GPIO_GND",
        "J2_FOCUS,R7.1,D3.A",
        "D3_A,R7.2,D3.A",
        "GND,D3.K,GPIO_GND",
        "J2_SHUTTER,R8.1,D4.A",
        "D4_A,R8.2,D4.A",
        "GND,D4.K,GPIO_GND",
    ]
    path.write_text("\n".join(rows) + "\n")


def _extract_symbol_block(text: str, name: str) -> str:
    pattern = re.compile(rf'\(symbol "{re.escape(name)}"(\s|\))')
    match = pattern.search(text)
    if not match:
        raise ValueError(f"symbol {name} not found")
    idx = match.start()
    depth = 0
    for i in range(idx, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[idx : i + 1]
    raise ValueError(f"unterminated symbol {name}")


def _indent(text: str, spaces: int) -> str:
    pad = " " * spaces
    return "\n".join(pad + line if line else line for line in text.splitlines())


def _build_lib_symbols() -> str:
    needed = [
        ("Device", "R"),
        ("Device", "LED"),
        ("Jumper", "SolderJumper_3_Bridged12"),
        ("Isolator", "4N25"),
        ("Connector_Audio", "AudioJack3"),
        ("Connector", "Raspberry_Pi_4"),
    ]
    blocks: list[str] = []
    sym_dir = KICAD_ROOT / "symbols"
    for lib, name in needed:
        raw = (sym_dir / f"{lib}.kicad_sym").read_text()
        body = _extract_symbol_block(raw, name)
        body = body.replace(f'(symbol "{name}"', f'(symbol "{lib}:{name}"', 1)
        blocks.append(_indent(body, 2))
    return "(lib_symbols\n" + "\n".join(blocks) + "\n)"


def _sch_symbol(
    lib_id: str,
    ref: str,
    value: str,
    x: float,
    y: float,
    angle: int = 0,
    footprint: str = "",
    pins: list[str] | None = None,
    hide_ref: bool = False,
    dnp: bool = False,
) -> str:
    pin_uuids = {p: uid() for p in (pins or [])}
    pin_lines = "\n".join(f'    (pin "{p}" (uuid {pin_uuids[p]}))' for p in pin_uuids)
    ref_effects = "(hide yes)" if hide_ref else ""
    dnp_flag = "yes" if dnp else "no"
    return f"""  (symbol
    (lib_id "{lib_id}")
    (at {x} {y} {angle})
    (unit 1)
    (exclude_from_sim no)
    (in_bom yes)
    (on_board yes)
    (dnp {dnp_flag})
    (uuid {uid()})
    (property "Reference" "{ref}"
      (at {x} {y - 5.08} {angle})
      (effects (font (size 1.27 1.27)) {ref_effects})
    )
    (property "Value" "{value}"
      (at {x} {y + 5.08} {angle})
      (effects (font (size 1.27 1.27)))
    )
    (property "Footprint" "{footprint}"
      (at {x} {y} {angle})
      (effects (font (size 1.27 1.27)) (hide yes))
    )
    (property "Datasheet" "~"
      (at {x} {y} {angle})
      (effects (font (size 1.27 1.27)) (hide yes))
    )
{pin_lines}
    (instances
      (project "{PROJECT_NAME}"
        (path "/{SHEET_UUID}"
          (reference "{ref}")
          (unit 1)
        )
      )
    )
  )"""


def _sch_wire(x1: float, y1: float, x2: float, y2: float) -> str:
    return (
        f'  (wire (pts (xy {x1} {y1}) (xy {x2} {y2}))'
        f' (stroke (width 0) (type default)) (uuid {uid()}))'
    )


def _sch_label(name: str, x: float, y: float, angle: int = 0) -> str:
    return f"""  (label "{name}"
    (at {x} {y} {angle})
    (effects (font (size 1.27 1.27)) (justify left bottom))
    (uuid {uid()})
  )"""


def _fmt(n: float) -> str:
    s = f"{n:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def _pins_in(block: str) -> list[tuple[str, float, float]]:
    pins: list[tuple[str, float, float]] = []
    for chunk in block.split("(pin ")[1:]:
        at = re.search(r"\(at\s+([-\d.]+)\s+([-\d.]+)", chunk)
        num = re.search(r'\(number\s+"([^"]+)"', chunk)
        if at and num:
            pins.append((num.group(1), float(at.group(1)), float(at.group(2))))
    return pins


def _glabel(name: str, x: float, y: float) -> str:
    return f"""  (global_label "{name}"
    (shape bidirectional)
    (at {_fmt(x)} {_fmt(y)} 0)
    (effects (font (size 1.27 1.27)) (justify left))
    (uuid {uid()})
  )"""


def _sch_no_connect(x: float, y: float) -> str:
    return f"  (no_connect (at {_fmt(x)} {_fmt(y)}) (uuid {uid()}))"


def _embed_footprint(
    lib: str,
    name: str,
    at_x: float,
    at_y: float,
    angle: int,
    ref: str,
    value: str,
    pad_nets: dict[str, tuple[int, str]],
    dnp: bool = False,
    bottom: bool = False,
    mirror_x: bool = False,
) -> str:
    mod_path = KICAD_ROOT / "footprints" / f"{lib}.pretty" / f"{name}.kicad_mod"
    body = mod_path.read_text().strip()
    body = body.replace(f'(footprint "{name}"', f'(footprint "{lib}:{name}"', 1)
    body = re.sub(
        r'\(property "Reference" "[^"]*"',
        f'(property "Reference" "{ref}"',
        body,
        count=1,
    )
    body = re.sub(
        r'\(property "Value" "[^"]*"',
        f'(property "Value" "{value}"',
        body,
        count=1,
    )
    if "(at " not in body.split(")", 1)[0]:
        body = body.replace(
            f'(footprint "{lib}:{name}"',
            f'(footprint "{lib}:{name}"\n\t(uuid {uid()})\n\t(at {at_x} {at_y} {angle})',
            1,
        )
    else:
        body = re.sub(r"\(at [^)]+\)", f"(at {at_x} {at_y} {angle})", body, count=1)
    for pad_id, (net_id, net_name) in pad_nets.items():
        pat = rf'(\(pad "{pad_id}"[^)]*(?:\([^)]*\)[^)]*)*?)(\n\t\))'
        def repl(m: re.Match[str], nid=net_id, nname=net_name) -> str:
            chunk = m.group(1)
            if "(net " in chunk:
                chunk = re.sub(r"\(net \d+ \"[^\"]*\"\)", f'(net {nid} "{nname}")', chunk)
                return chunk + m.group(2)
            return chunk + f'\n\t\t(net {nid} "{nname}")' + m.group(2)

        body, n = re.subn(pat, repl, body, count=1, flags=re.DOTALL)
        if n == 0:
            raise ValueError(f"pad {pad_id} missing in {name}")
    if dnp:
        body = body.replace("(attr through_hole)", "(attr through_hole dnp)", 1)
    if bottom:
        # Same holes. Silk and courtyard move to the back with the body.
        # The model is built for the library pin row (local X negative).
        # This footprint mirrors that row so the even pins face the board
        # edge, so the housing also needs +2.54 mm in X. +48.26 mm in Y
        # slides it along the row onto the holes.
        body = body.replace('(layer "F.Cu")', '(layer "B.Cu")', 1)
        for front, back in (
            ("F.SilkS", "B.SilkS"),
            ("F.CrtYd", "B.CrtYd"),
            ("F.Fab", "B.Fab"),
            ("F.Paste", "B.Paste"),
            ("F.Mask", "B.Mask"),
        ):
            body = body.replace(f'(layer "{front}")', f'(layer "{back}")')
        body = body.replace(
            "(offset\n\t\t\t(xyz 0 0 0)",
            "(offset\n\t\t\t(xyz 2.54 48.26 0)",
            1,
        )
    if "SJ1-3535NG" in name:
        # Manufacturer STEP is modeled on its side, straddling Z=0 with the
        # pins up. 180° about X drops the pins through the board; -90° yaw
        # puts the plug on the footprint's -Y nose (out the pin-1 edge).
        # Z +7 sits the housing on the top face. The pins still pass through
        # the 1.6 mm board. X/Y keep those pins on the holes.
        body = body.replace(
            "${KICAD9_3DMODEL_DIR}/Connector_Audio.3dshapes/Jack_3.5mm_CUI_SJ1-3535NG_Horizontal.step",
            "${KIPRJMOD}/3d/SJ1-3535NG.step",
        )
        body = body.replace(
            "(offset\n\t\t\t(xyz 0 0 0)",
            "(offset\n\t\t\t(xyz 1 4.8 7)",
            1,
        )
        body = body.replace(
            "(rotate\n\t\t\t(xyz 0 0 0)",
            "(rotate\n\t\t\t(xyz 180 0 -90)",
            1,
        )
        # Library slots run along the plug. The SJ1-3535NG pins are flat the
        # other way; turn the ovals 90° so the drills match the part.
        body = body.replace("(size 2.8 1.8)", "(size 1.8 2.8)")
        body = body.replace("(drill oval 2 1)", "(drill oval 1 2)")
        # The library ref sits past the plug nose and falls off the board edge.
        body = body.replace(
            "(at 0.1 -6.45 0)\n\t\t(layer \"F.SilkS\")",
            "(at 0.1 -6.45 0)\n\t\t(hide yes)\n\t\t(layer \"F.SilkS\")",
            1,
        )
    if ref in ("R5", "R6", "R7", "R8"):
        body = body.replace(
            "(at 1.27 -2.37 0)\n\t\t(layer \"F.SilkS\")",
            "(at 1.27 -2.37 0)\n\t\t(hide yes)\n\t\t(layer \"F.SilkS\")",
            1,
        )
    if lib == "LED_THT":
        # Column and row captions replace the designator on the silk.
        body = body.replace(
            "(at 1.27 -3.96 0)\n\t\t(layer \"F.SilkS\")",
            "(at 1.27 -3.96 0)\n\t\t(hide yes)\n\t\t(layer \"F.SilkS\")",
            1,
        )
    if name.startswith("MountingHole"):
        body = body.replace(
            '(layer "F.SilkS")',
            '(layer "F.SilkS")\n\t\t(hide yes)',
            1,
        )
    if mirror_x:
        body = _mirror_fp_x(body)
    return _indent(body, 1)


def _mirror_fp_x(body: str) -> str:
    """Flip local X so the even header row faces the low-Y edge. Skip the placement."""
    skipped = {"at": False}

    def at_repl(m: re.Match[str]) -> str:
        if not skipped["at"]:
            skipped["at"] = True
            return m.group(0)
        return f"(at {-float(m.group(1)):.4g} {m.group(2)}"

    body = re.sub(r"\(at ([-+\d.]+) ([-+\d.eE]+)", at_repl, body)

    def xy_repl(m: re.Match[str]) -> str:
        return f"({m.group(1)} {-float(m.group(2)):.4g} {m.group(3)}"

    return re.sub(r"\((start|end|mid|center|xy) ([-+\d.]+) ([-+\d.eE]+)", xy_repl, body)


def _write_kicad_schematic(path: Path) -> None:
    """Label every pin at its real symbol coordinate. No guessed wires."""
    pi_block = _extract_symbol_block(
        (KICAD_ROOT / "symbols" / "Connector.kicad_sym").read_text(),
        "Raspberry_Pi_4",
    )
    pi_pins = _pins_in(pi_block)
    pi_x, pi_y = 55.88, 127.0
    # 4N35 (drawn as 4N25 geometry): pin -> (dx, dy) from symbol origin
    opto = {
        "1": (-7.62, 2.54),
        "2": (-7.62, -2.54),
        "3": (-5.08, 0.0),
        "4": (7.62, -2.54),
        "5": (7.62, 0.0),
        "6": (7.62, 2.54),
    }
    jack_pin = {"T": (5.08, -2.54), "R": (5.08, 0.0), "S": (5.08, 2.54)}
    channels = [
        ("U1", "R1", "FOCUS", "J1_RING", "J1_SLEEVE", 35.56),
        ("U2", "R2", "SHUTTER", "J1_TIP", "J1_SLEEVE", 60.96),
        ("U3", "R3", "J2_FOCUS", "J2_RING", "J2_SLEEVE", 86.36),
        ("U4", "R4", "J2_SHUTTER", "J2_TIP", "J2_SLEEVE", 111.76),
    ]
    jacks = {"J1": (228.6, 48.26), "J2": (228.6, 99.06)}
    parts: list[str] = [
        "(kicad_sch",
        "\t(version 20250114)",
        '\t(generator "nikonduals-gpio_trigger")',
        '\t(generator_version "9.0")',
        f'\t(uuid "{SHEET_UUID}")',
        '\t(paper "A3")',
        "\t(title_block",
        '\t\t(title "Pi dual TRS Nikon trigger")',
        '\t\t(date "2026-09-21")',
        '\t\t(rev "1.1")',
        '\t\t(comment 1 "JP1/JP2 bridged 1-2: both cameras on pin 38/40. Cut and bridge 2-3 for J2 on pin 37/35.")',
        '\t\t(comment 2 "Nets are global labels on the real pin positions. Regenerate: python3 gen_cad.py")',
        "\t)",
        _indent(_build_lib_symbols(), 1),
        _sch_symbol(
            "Connector:Raspberry_Pi_4",
            "J3",
            "Pi_GPIO",
            pi_x,
            pi_y,
            footprint="Connector_PinSocket_2.54mm:PinSocket_2x20_P2.54mm_Vertical",
            pins=list(dict.fromkeys(n for n, _, _ in pi_pins)),
        ),
    ]
    used = {
        "35": "B_SHUTTER",
        "37": "B_FOCUS",
        "38": "FOCUS",
        "39": "GND",
        "40": "SHUTTER",
    }
    for num, dx, dy in pi_pins:
        wx, wy = pi_x + dx, pi_y - dy
        if num in used:
            parts.append(_glabel(used[num], wx, wy))
        else:
            parts.append(_sch_no_connect(wx, wy))

    for uname, rname, bus, out_net, sleeve, y in channels:
        rx, ux = 139.7, 170.18
        led_net = f"{rname}_LED"
        parts.append(
            _sch_symbol(
                "Device:R",
                rname,
                "330",
                rx,
                y,
                footprint="Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical",
                pins=["1", "2"],
            )
        )
        parts.append(
            _sch_symbol(
                "Isolator:4N25",
                uname,
                "4N35",
                ux,
                y,
                footprint="Package_DIP:DIP-6_W7.62mm",
                pins=["1", "2", "3", "4", "5", "6"],
            )
        )
        parts.append(_glabel(bus, rx, y - 3.81))
        parts.append(_glabel(led_net, rx, y + 3.81))
        parts.append(_glabel(led_net, ux + opto["1"][0], y - opto["1"][1]))
        parts.append(_glabel("GND", ux + opto["2"][0], y - opto["2"][1]))
        parts.append(_sch_no_connect(ux + opto["3"][0], y - opto["3"][1]))
        parts.append(_glabel(sleeve, ux + opto["4"][0], y - opto["4"][1]))
        parts.append(_glabel(out_net, ux + opto["5"][0], y - opto["5"][1]))
        parts.append(_sch_no_connect(ux + opto["6"][0], y - opto["6"][1]))

    for jname, (jx, jy) in jacks.items():
        parts.append(
            _sch_symbol(
                "Connector_Audio:AudioJack3",
                jname,
                "TRS_" + ("CAM_A" if jname == "J1" else "CAM_B"),
                jx,
                jy,
                footprint="Connector_Audio:Jack_3.5mm_CUI_SJ1-3535NG_Horizontal",
                pins=["T", "R", "S"],
            )
        )
        parts.append(_glabel(f"{jname}_TIP", jx + jack_pin["T"][0], jy - jack_pin["T"][1]))
        parts.append(_glabel(f"{jname}_RING", jx + jack_pin["R"][0], jy - jack_pin["R"][1]))
        parts.append(_glabel(f"{jname}_SLEEVE", jx + jack_pin["S"][0], jy - jack_pin["S"][1]))

    # Pads 1-2 are copper-bridged (net tie): both cameras follow pin 38/40.
    # Pad 3 is the per-camera GPIO. Cut 1-2 and blob 2-3 to split J2 off.
    jumper_pins = {"1": (-5.08, 0.0), "2": (0.0, -3.81), "3": (5.08, 0.0)}
    for ref, y, common, mid, alt in (
        ("JP1", 86.36, "FOCUS", "J2_FOCUS", "B_FOCUS"),
        ("JP2", 111.76, "SHUTTER", "J2_SHUTTER", "B_SHUTTER"),
    ):
        jx = 105.0
        parts.append(
            _sch_symbol(
                "Jumper:SolderJumper_3_Bridged12",
                ref,
                ref,
                jx,
                y,
                footprint="Jumper:SolderJumper-3_P1.3mm_Bridged12_Pad1.0x1.5mm",
                pins=["1", "2", "3"],
            )
        )
        parts.append(_glabel(common, jx + jumper_pins["1"][0], y + jumper_pins["1"][1]))
        parts.append(_glabel(mid, jx + jumper_pins["2"][0], y + jumper_pins["2"][1]))
        parts.append(_glabel(alt, jx + jumper_pins["3"][0], y + jumper_pins["3"][1]))

    # Four lamps: camera 1 is pin 38/40, camera 2 follows the jumper mid net.
    for ref_r, ref_d, bus, value, y in (
        ("R5", "D1", "FOCUS", "1 focus", 142.24),
        ("R6", "D2", "SHUTTER", "1 shutter", 157.48),
        ("R7", "D3", "J2_FOCUS", "2 focus", 172.72),
        ("R8", "D4", "J2_SHUTTER", "2 shutter", 187.96),
    ):
        rx, dx = 200.66, 220.98
        mid = f"{ref_d}_A"
        parts.append(
            _sch_symbol(
                "Device:R",
                ref_r,
                "330",
                rx,
                y,
                footprint="Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical",
                pins=["1", "2"],
                dnp=True,
            )
        )
        parts.append(
            _sch_symbol(
                "Device:LED",
                ref_d,
                value,
                dx,
                y,
                footprint="LED_THT:LED_D5.0mm",
                pins=["1", "2"],
                dnp=True,
            )
        )
        parts.append(_glabel(bus, rx, y - 3.81))
        parts.append(_glabel(mid, rx, y + 3.81))
        parts.append(_glabel(mid, dx + 3.81, y))
        parts.append(_glabel("GND", dx - 3.81, y))
    parts.append(")")
    path.write_text("\n".join(parts) + "\n")


def _parse_svg_rings(d: str) -> list[list[tuple[float, float]]]:
    rings: list[list[tuple[float, float]]] = []
    for chunk in re.findall(r"[Mm][^Mm]*", d):
        nums = [float(n) for n in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", chunk)]
        pts = list(zip(nums[0::2], nums[1::2]))
        if len(pts) >= 2 and pts[0] == pts[-1]:
            pts = pts[:-1]
        if len(pts) >= 3:
            rings.append(pts)
    return rings


def _ring_area(ring: list[tuple[float, float]]) -> float:
    a = 0.0
    for i, (x1, y1) in enumerate(ring):
        x2, y2 = ring[(i + 1) % len(ring)]
        a += x1 * y2 - x2 * y1
    return a / 2


def _point_in_ring(pt: tuple[float, float], ring: list[tuple[float, float]]) -> bool:
    x, y = pt
    inside = False
    j = len(ring) - 1
    for i, (xi, yi) in enumerate(ring):
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _simplify(pts: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    if len(pts) < 4:
        return pts

    def rec(a: int, b: int) -> list[int]:
        x1, y1 = pts[a]
        x2, y2 = pts[b]
        dx, dy = x2 - x1, y2 - y1
        den = dx * dx + dy * dy or 1.0
        best_i, best_d = a, 0.0
        for i in range(a + 1, b):
            px, py = pts[i]
            t = ((px - x1) * dx + (py - y1) * dy) / den
            t = 0.0 if t < 0 else 1.0 if t > 1 else t
            d = (px - (x1 + t * dx)) ** 2 + (py - (y1 + t * dy)) ** 2
            if d > best_d:
                best_i, best_d = i, d
        if best_d <= eps * eps:
            return [a, b]
        return rec(a, best_i)[:-1] + rec(best_i, b)

    idx = rec(0, len(pts) - 1)
    return [pts[i] for i in idx]


def _stitch_holes(
    outer: list[tuple[float, float]], holes: list[list[tuple[float, float]]]
) -> list[tuple[float, float]]:
    pts = list(outer)
    if _ring_area(pts) < 0:
        pts.reverse()
    for hole in holes:
        h = list(hole)
        if _ring_area(h) > 0:
            h.reverse()
        bi = hi = 0
        best = 1e99
        for i, p in enumerate(pts):
            for j, q in enumerate(h):
                d = (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2
                if d < best:
                    best, bi, hi = d, i, j
        loop = h[hi:] + h[: hi + 1]
        pts = pts[: bi + 1] + loop + [pts[bi]] + pts[bi + 1 :]
    return pts


def _interior_point(ring: list[tuple[float, float]]) -> tuple[float, float]:
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    if _point_in_ring((cx, cy), ring):
        return cx, cy
    for i, (x1, y1) in enumerate(ring):
        x2, y2 = ring[(i + 1) % len(ring)]
        for t in (0.25, 0.5, 0.75):
            p = (x1 + (cx - x1) * t, (y1 + (y2 - y1) * 0.5) + (cy - y1) * t * 0.0)
            mid = ((x1 + x2) / 2, (y1 + y2) / 2)
            p = (mid[0] + (cx - mid[0]) * t, mid[1] + (cy - mid[1]) * t)
            if _point_in_ring(p, ring):
                return p
    return cx, cy


def _evenodd_contours(rings: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Opposite winding is a hole (how fxpan.svg encodes evenodd cutouts)."""
    solids = [i for i, ring in enumerate(rings) if _ring_area(ring) > 0]
    holes = [i for i, ring in enumerate(rings) if _ring_area(ring) < 0]
    grouped: dict[int, list[list[tuple[float, float]]]] = {i: [] for i in solids}
    for h in holes:
        pt = _interior_point(rings[h])
        parents = [i for i in solids if _point_in_ring(pt, rings[i])]
        if not parents:
            continue
        parent = min(parents, key=lambda i: abs(_ring_area(rings[i])))
        grouped[parent].append(rings[h])
    return [_stitch_holes(rings[i], grouped[i]) for i in solids]


def _fxpan_silk(x_left: float, y_header: float, width: float) -> str:
    """fxpan.svg as filled F.SilkS polygons.

    y_header is the GPIO side of the box. Letter tops point the other way, so
    the mark reads FX PAN with pin 1 on the left in KiCad's top view.
    """
    svg = (ROOT.parent / "logos" / "fxpan.svg").read_text()
    vb = re.search(r'viewBox="([^"]+)"', svg)
    vb_x, vb_y, vb_w, vb_h = (float(n) for n in vb.group(1).split())
    scale = width / vb_w
    y_far = y_header - vb_h * scale
    polys: list[str] = []
    for d in re.findall(r'<path d="([^"]+)"', svg):
        rings = [_simplify(r, 0.15) for r in _parse_svg_rings(d)]
        for contour in _evenodd_contours(rings):
            pts = []
            for sx, sy in contour:
                x = x_left + (sx - vb_x) * scale
                y = y_far + (sy - vb_y) * scale
                pts.append(f"(xy {x:.3f} {y:.3f})")
            polys.append(
                "\t(gr_poly\n"
                f"\t\t(pts {' '.join(pts)})\n"
                "\t\t(stroke (width 0) (type solid))\n"
                "\t\t(fill solid)\n"
                '\t\t(layer "F.SilkS")\n'
                f"\t\t(uuid {uid()}))"
            )
    return "\n".join(polys)


def _xy_rot(lx: float, ly: float, deg: float) -> tuple[float, float]:
    # KiCad's positive footprint angle is clockwise in Y-up board coordinates.
    # Confirmed with pcbnew: file angle 90 maps (x, y) to (y, -x).
    a = math.radians(-deg)
    c, s = math.cos(a), math.sin(a)
    return lx * c - ly * s, lx * s + ly * c


def _fp_text(lib: str, name: str) -> str:
    return (KICAD_ROOT / "footprints" / f"{lib}.pretty" / f"{name}.kicad_mod").read_text()


def _fp_pads(lib: str, name: str) -> list[dict]:
    text = _fp_text(lib, name)
    pads = []
    for m in re.finditer(r'\(pad "([^"]*)"', text):
        chunk = text[m.start() : m.start() + 450]
        at = re.search(r"\(at ([-\d.]+) ([-\d.]+)", chunk)
        size = re.search(r"\(size ([-\d.]+) ([-\d.]+)\)", chunk)
        if not at or not size:
            continue
        pads.append(
            {
                "id": m.group(1),
                "lx": float(at.group(1)),
                "ly": float(at.group(2)),
                "r": min(float(size.group(1)), float(size.group(2))) / 2,
            }
        )
    return pads


def _courtyard(
    lib: str, name: str, ax: float, ay: float, ang: float, mirror_x: bool = False
) -> tuple[float, float, float, float]:
    text = _fp_text(lib, name)
    xs: list[float] = []
    ys: list[float] = []
    for m in re.finditer(
        r"\(fp_(?:line|rect)\s+\(start ([-\d.]+) ([-\d.]+)\)\s+\(end ([-\d.]+) ([-\d.]+)\)[\s\S]{0,200}?[FB]\.CrtYd",
        text,
    ):
        for lx, ly in (
            (float(m.group(1)), float(m.group(2))),
            (float(m.group(3)), float(m.group(4))),
        ):
            if mirror_x:
                lx = -lx
            x, y = _xy_rot(lx, ly, ang)
            xs.append(ax + x)
            ys.append(ay + y)
    for m in re.finditer(
        r"\(fp_circle\s+\(center ([-\d.]+) ([-\d.]+)\)\s+\(end ([-\d.]+) ([-\d.]+)\)[\s\S]{0,200}?[FB]\.CrtYd",
        text,
    ):
        cx, cy = float(m.group(1)), float(m.group(2))
        radius = math.hypot(float(m.group(3)) - cx, float(m.group(4)) - cy)
        for lx, ly in ((cx - radius, cy), (cx + radius, cy), (cx, cy - radius), (cx, cy + radius)):
            if mirror_x:
                lx = -lx
            x, y = _xy_rot(lx, ly, ang)
            xs.append(ax + x)
            ys.append(ay + y)
    if not xs:
        raise ValueError(f"no courtyard in {name}")
    return min(xs), min(ys), max(xs), max(ys)


# Pi 4 outline, pin 1 at (30, -8). The GPIO edge is the low-Y side, which is
# the top of KiCad's 3D view. Even pins face that edge. The Pi body is the
# inland side (increasing Y). USB and Ethernet start near x=91, so the board
# stops at x=87. Pi rect: x 21.63..86.63, y -12.77..43.23.
_DESIGN_OUTLINE = [(21.8, -12.55), (87.0, -12.55), (87.0, 42.9), (21.8, 42.9)]
_SHEET_INSET = 14.0
_DX = _SHEET_INSET - min(p[0] for p in _DESIGN_OUTLINE)
_DY = _SHEET_INSET - min(p[1] for p in _DESIGN_OUTLINE)
OUTLINE = [(x + _DX, y + _DY) for x, y in _DESIGN_OUTLINE]
TRACK = 0.4
CLEAR = 0.3
GRID = 0.25


def _in_poly(x: float, y: float, poly: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(poly) - 1
    for i, (xi, yi) in enumerate(poly):
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def _dist_seg(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx, dy = bx - ax, by - ay
    den = dx * dx + dy * dy or 1.0
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / den))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _on_board(x: float, y: float, margin: float) -> bool:
    if not _in_poly(x, y, OUTLINE):
        return False
    for i, a in enumerate(OUTLINE):
        b = OUTLINE[(i + 1) % len(OUTLINE)]
        if _dist_seg(x, y, a[0], a[1], b[0], b[1]) < margin:
            return False
    return True


def _board_parts() -> list[dict]:
    gnd = (1, "GND")
    parts: list[dict] = []

    def add(ref, lib, name, x, y, ang, value, nets, dnp=False, bottom=False, mirror_x=False):
        parts.append(
            {
                "ref": ref,
                "lib": lib,
                "name": name,
                "x": x,
                "y": y,
                "ang": ang,
                "value": value,
                "nets": nets,
                "dnp": dnp,
                "bottom": bottom,
                "mirror_x": mirror_x,
            }
        )

    add(
        "J3",
        "Connector_PinSocket_2.54mm",
        "PinSocket_2x20_P2.54mm_Vertical",
        30,
        8,
        90,
        "Pi_GPIO",
        {
            "35": (13, "B_SHUTTER"),
            "37": (12, "B_FOCUS"),
            "38": (2, "FOCUS"),
            "40": (3, "SHUTTER"),
            **{p: gnd for p in ("6", "9", "14", "20", "25", "30", "34", "39")},
        },
        bottom=True,
        mirror_x=True,
    )
    add(
        "J1",
        "Connector_Audio",
        "Jack_3.5mm_CUI_SJ1-3535NG_Horizontal",
        27.75,
        -11.5,
        90,
        "TRS_CAM_A",
        {"T": (5, "J1_TIP"), "R": (4, "J1_RING"), "S": (6, "J1_SLEEVE")},
    )
    add(
        "J2",
        "Connector_Audio",
        "Jack_3.5mm_CUI_SJ1-3535NG_Horizontal",
        27.75,
        0.2,
        90,
        "TRS_CAM_B",
        {"T": (8, "J2_TIP"), "R": (7, "J2_RING"), "S": (9, "J2_SLEEVE")},
    )
    dips = [
        ("U1", 51, -12.5, {"1": (14, "R1_LED"), "2": gnd, "4": (6, "J1_SLEEVE"), "5": (4, "J1_RING")}),
        ("U2", 69, -12.5, {"1": (15, "R2_LED"), "2": gnd, "4": (6, "J1_SLEEVE"), "5": (5, "J1_TIP")}),
        ("U3", 51, -1.5, {"1": (16, "R3_LED"), "2": gnd, "4": (9, "J2_SLEEVE"), "5": (7, "J2_RING")}),
        ("U4", 69, -1.5, {"1": (17, "R4_LED"), "2": gnd, "4": (9, "J2_SLEEVE"), "5": (8, "J2_TIP")}),
    ]
    for ref, x, y, nets in dips:
        add(ref, "Package_DIP", "DIP-6_W7.62mm", x, y, 0, "4N35", nets)
    resistors = [
        ("R1", 51, -12.5, {"1": (2, "FOCUS"), "2": (14, "R1_LED")}),
        ("R2", 69, -12.5, {"1": (3, "SHUTTER"), "2": (15, "R2_LED")}),
        ("R3", 51, -1.5, {"1": (10, "J2_FOCUS"), "2": (16, "R3_LED")}),
        ("R4", 69, -1.5, {"1": (11, "J2_SHUTTER"), "2": (17, "R4_LED")}),
    ]
    for ref, x, y, nets in resistors:
        add(
            ref,
            "Resistor_THT",
            "R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical",
            x - 5.2,
            y,
            0,
            "330",
            nets,
        )
    # Camera 1 follows pin 38/40. Camera 2 follows the jumper, so it tracks a split.
    # Grouped at the inland corner: focus column, shutter column, cam 1 then cam 2.
    add("D1", "LED_THT", "LED_D5.0mm", 64.8, -24.05, 0, "1 focus", {"1": gnd, "2": (18, "D1_A")})
    add("D2", "LED_THT", "LED_D5.0mm", 73.8, -24.05, 0, "1 shutter", {"1": gnd, "2": (19, "D2_A")})
    add(
        "R5",
        "Resistor_THT",
        "R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical",
        64.8,
        -29.15,
        0,
        "330",
        {"1": (2, "FOCUS"), "2": (18, "D1_A")},
    )
    add(
        "R6",
        "Resistor_THT",
        "R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical",
        73.8,
        -29.15,
        0,
        "330",
        {"1": (3, "SHUTTER"), "2": (19, "D2_A")},
    )
    add("D3", "LED_THT", "LED_D5.0mm", 64.8, -34.25, 0, "2 focus", {"1": gnd, "2": (20, "D3_A")})
    add("D4", "LED_THT", "LED_D5.0mm", 73.8, -34.25, 0, "2 shutter", {"1": gnd, "2": (21, "D4_A")})
    add(
        "R7",
        "Resistor_THT",
        "R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical",
        64.8,
        -39.35,
        0,
        "330",
        {"1": (10, "J2_FOCUS"), "2": (20, "D3_A")},
    )
    add(
        "R8",
        "Resistor_THT",
        "R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical",
        73.8,
        -39.35,
        0,
        "330",
        {"1": (11, "J2_SHUTTER"), "2": (21, "D4_A")},
    )
    # Default copper bridge is pads 1-2: J2 follows the same GPIO as J1.
    # Cut that bridge and blob pad 2 to pad 3 to give J2 its own pins.
    add(
        "JP1",
        "Jumper",
        "SolderJumper-3_P1.3mm_Bridged12_Pad1.0x1.5mm",
        82.5,
        -8.0,
        0,
        "J2_focus",
        {"1": (2, "FOCUS"), "2": (10, "J2_FOCUS"), "3": (12, "B_FOCUS")},
    )
    add(
        "JP2",
        "Jumper",
        "SolderJumper-3_P1.3mm_Bridged12_Pad1.0x1.5mm",
        82.5,
        -13.0,
        0,
        "J2_shutter",
        {"1": (3, "SHUTTER"), "2": (11, "J2_SHUTTER"), "3": (13, "B_SHUTTER")},
    )
    # All four Pi M2.5 holes. H1/H2 are on the header centerline, 4.87 mm past
    # each end. H3/H4 are 49 mm inland, on the Pi.
    add("H1", "MountingHole", "MountingHole_2.7mm_M2.5", 25.13, 9.27, 0, "M2.5", {})
    add("H2", "MountingHole", "MountingHole_2.7mm_M2.5", 83.13, 9.27, 0, "M2.5", {})
    add("H3", "MountingHole", "MountingHole_2.7mm_M2.5", 25.13, -39.73, 0, "M2.5", {})
    add("H4", "MountingHole", "MountingHole_2.7mm_M2.5", 83.13, -39.73, 0, "M2.5", {})
    for part in parts:
        # Low Y is the GPIO edge (top of the 3D view). Design numbers above
        # were written with the header at +Y; flip them onto that edge.
        part["y"] = -part["y"]
        part["x"] += _DX
        part["y"] += _DY
    return parts


def _world_pads(part: dict) -> list[dict]:
    out = []
    for pad in _fp_pads(part["lib"], part["name"]):
        lx, ly = pad["lx"], pad["ly"]
        if part.get("mirror_x"):
            lx = -lx
        dx, dy = _xy_rot(lx, ly, part["ang"])
        out.append(
            {
                "id": pad["id"],
                "x": part["x"] + dx,
                "y": part["y"] + dy,
                "r": pad["r"],
                "net": part["nets"].get(pad["id"]),
                "ref": part["ref"],
            }
        )
    return out


def _check_placement(parts: list[dict]) -> None:
    boxes = []
    for part in parts:
        box = _courtyard(
            part["lib"], part["name"], part["x"], part["y"], part["ang"], part.get("mirror_x", False)
        )
        boxes.append((part["ref"], box))
        x0, y0, x1, y1 = box
        for x, y in ((x0, y0), (x0, y1), (x1, y0), (x1, y1)):
            if not _in_poly(x, y, OUTLINE):
                raise SystemExit(f"{part['ref']} courtyard {box} is outside the board at {x:.2f},{y:.2f}")
    for i, (ra, a) in enumerate(boxes):
        ax0, ay0, ax1, ay1 = a
        for rb, b in boxes[i + 1 :]:
            bx0, by0, bx1, by1 = b
            if ax0 < bx1 - 0.05 and ax1 > bx0 + 0.05 and ay0 < by1 - 0.05 and ay1 > by0 + 0.05:
                raise SystemExit(f"courtyards overlap: {ra} {a} and {rb} {b}")


def _route_copper(parts: list[dict]) -> str:
    pads = [p for part in parts for p in _world_pads(part)]
    # Pins 38 and 40 are the outer header row, against the Pi edge. A 0.25 mm
    # track fits between the 2.54 mm pins; the maze keepout does not. Drop a
    # via on the inland side and let the router start there.
    j3 = {p["id"]: p for p in pads if p["ref"] == "J3"}
    p38, p40 = j3["38"], j3["40"]
    focus_via = {
        "id": "esc",
        "x": (p38["x"] + p40["x"]) / 2,
        "y": p38["y"] + 5.0,
        "r": 0.4,
        "net": p38["net"],
        "ref": "ESC",
    }
    shut_via = {
        "id": "esc",
        "x": p40["x"] + 2.0,
        "y": p40["y"] + 5.0,
        "r": 0.4,
        "net": p40["net"],
        "ref": "ESC",
    }
    pads.extend((focus_via, shut_via))
    escapes = []
    # Solder-jumper pads are 1.3 mm apart, closer than the maze keepout.
    # Step straight off each pad, then let the router start in the clear.
    jumper_ends = []
    for pad in [p for p in pads if str(p["ref"]).startswith("JP")]:
        # Fan the stubs apart so one net's trace cannot wall off the others.
        dx, dy = {"1": (-2.4, 0.0), "2": (0.0, -2.4), "3": (0.0, 2.4)}[pad["id"]]
        end = {
            "id": "esc",
            "x": pad["x"] + dx,
            "y": pad["y"] + dy,
            "r": 0.55,
            "net": pad["net"],
            "ref": "ESC",
        }
        jumper_ends.append((pad, end))
        nid, _name = pad["net"]
        escapes.append(
            f'\t(segment (start {pad["x"]:.3f} {pad["y"]:.3f}) (end {end["x"]:.3f} {end["y"]:.3f}) '
            f'(width 0.25) (layer "F.Cu") (net {nid}) (uuid {uid()}))'
        )
        escapes.append(
            f'\t(via (at {end["x"]:.3f} {end["y"]:.3f}) (size 0.8) (drill 0.4) '
            f'(layers "F.Cu" "B.Cu") (net {nid}) (uuid {uid()}))'
        )
    pads.extend(end for _, end in jumper_ends)
    # Indicator resistors sit on a 0.25 mm grid. A via in the next cell
    # would break the hole-to-hole rule, so step off the pad first.
    for ref, dx, dy in (
        ("R5", -2.4, 0.0),
        ("R6", -2.4, 0.0),
        ("R7", -2.4, 0.0),
        ("R8", -2.4, 0.0),
    ):
        pad = next(p for p in pads if p["ref"] == ref and p["id"] == "1")
        end = {
            "id": "esc",
            "x": pad["x"] + dx,
            "y": pad["y"] + dy,
            "r": 0.55,
            "net": pad["net"],
            "ref": "ESC",
        }
        nid, _name = pad["net"]
        escapes.append(
            f'\t(segment (start {pad["x"]:.3f} {pad["y"]:.3f}) (end {end["x"]:.3f} {end["y"]:.3f}) '
            f'(width 0.25) (layer "F.Cu") (net {nid}) (uuid {uid()}))'
        )
        escapes.append(
            f'\t(via (at {end["x"]:.3f} {end["y"]:.3f}) (size 0.8) (drill 0.4) '
            f'(layers "F.Cu" "B.Cu") (net {nid}) (uuid {uid()}))'
        )
        pads.append(end)
    for src, via in ((p38, focus_via), (p40, shut_via)):
        nid, _name = src["net"]
        escapes.append(
            f'\t(segment (start {src["x"]:.3f} {src["y"]:.3f}) (end {via["x"]:.3f} {src["y"]:.3f}) '
            f'(width 0.25) (layer "F.Cu") (net {nid}) (uuid {uid()}))'
        )
        escapes.append(
            f'\t(segment (start {via["x"]:.3f} {src["y"]:.3f}) (end {via["x"]:.3f} {via["y"]:.3f}) '
            f'(width 0.25) (layer "F.Cu") (net {nid}) (uuid {uid()}))'
        )
        escapes.append(
            f'\t(via (at {via["x"]:.3f} {via["y"]:.3f}) (size 0.8) (drill 0.4) '
            f'(layers "F.Cu" "B.Cu") (net {nid}) (uuid {uid()}))'
        )
    led_bus = {("R5", "1"), ("R6", "1"), ("R7", "1"), ("R8", "1")}
    route_pads = [
        p
        for p in pads
        if not (p["ref"] == "J3" and p["id"] in ("38", "40"))
        and not str(p["ref"]).startswith("JP")
        and (p["ref"], p["id"]) not in led_bus
    ]
    by_net: dict[int, dict] = {}
    for pad in route_pads:
        if not pad["net"]:
            continue
        nid, name = pad["net"]
        by_net.setdefault(nid, {"name": name, "pads": []})["pads"].append(pad)

    xs = [p[0] for p in OUTLINE]
    ys = [p[1] for p in OUTLINE]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    nx = int(round((x1 - x0) / GRID)) + 4
    ny = int(round((y1 - y0) / GRID)) + 4
    margin = 0.5 + TRACK / 2

    def coord(ix: int, iy: int) -> tuple[float, float]:
        return x0 + ix * GRID, y0 + iy * GRID

    on_board = [[False] * ny for _ in range(nx)]
    for ix in range(nx):
        for iy in range(ny):
            x, y = coord(ix, iy)
            on_board[ix][iy] = _on_board(x, y, margin)

    blocked: set[tuple[int, int, int]] = set()

    def stamp_disk(x: float, y: float, radius: float, layers: tuple[int, ...]) -> None:
        n = int(radius / GRID) + 2
        ix0 = int(round((x - x0) / GRID))
        iy0 = int(round((y - y0) / GRID))
        for ix in range(ix0 - n, ix0 + n + 1):
            for iy in range(iy0 - n, iy0 + n + 1):
                if not (0 <= ix < nx and 0 <= iy < ny):
                    continue
                cx, cy = coord(ix, iy)
                if math.hypot(cx - x, cy - y) <= radius:
                    for lay in layers:
                        blocked.add((ix, iy, lay))

    def pad_block_for(nid: int) -> set[tuple[int, int, int]]:
        blocked_pads: set[tuple[int, int, int]] = set()

        def stamp_into(x: float, y: float, radius: float) -> None:
            n = int(radius / GRID) + 2
            ix0 = int(round((x - x0) / GRID))
            iy0 = int(round((y - y0) / GRID))
            for ix in range(ix0 - n, ix0 + n + 1):
                for iy in range(iy0 - n, iy0 + n + 1):
                    if not (0 <= ix < nx and 0 <= iy < ny):
                        continue
                    cx, cy = coord(ix, iy)
                    if math.hypot(cx - x, cy - y) <= radius:
                        blocked_pads.add((ix, iy, 0))
                        blocked_pads.add((ix, iy, 1))

        for pad in pads:
            if pad["net"] and pad["net"][0] == nid:
                continue
            stamp_into(pad["x"], pad["y"], pad["r"] + CLEAR + TRACK / 2 + 0.45)
        for src, via in ((p38, focus_via), (p40, shut_via)):
            if src["net"][0] == nid:
                continue
            for x, y in ((via["x"], via["y"]), (via["x"], src["y"])):
                stamp_into(x, y, 0.9)
            steps = 8
            for i in range(steps + 1):
                t = i / steps
                stamp_into(via["x"], src["y"] + (via["y"] - src["y"]) * t, 0.7)
                stamp_into(src["x"] + (via["x"] - src["x"]) * t, src["y"], 0.7)
        for src, end in jumper_ends:
            if src["net"][0] == nid:
                continue
            steps = 8
            for i in range(steps + 1):
                t = i / steps
                x = src["x"] + (end["x"] - src["x"]) * t
                y = src["y"] + (end["y"] - src["y"]) * t
                stamp_into(x, y, 0.55)
        return blocked_pads

    def pad_cells(pad: dict) -> list[tuple[int, int, int]]:
        cells = []
        rad = max(0.05, pad["r"] - TRACK / 2)
        n = int(rad / GRID) + 2
        ix0 = int(round((pad["x"] - x0) / GRID))
        iy0 = int(round((pad["y"] - y0) / GRID))
        for ix in range(ix0 - n, ix0 + n + 1):
            for iy in range(iy0 - n, iy0 + n + 1):
                if not (0 <= ix < nx and 0 <= iy < ny) or not on_board[ix][iy]:
                    continue
                cx, cy = coord(ix, iy)
                if math.hypot(cx - pad["x"], cy - pad["y"]) <= rad:
                    cells.append((ix, iy, 0))
                    cells.append((ix, iy, 1))
        if not cells:
            raise SystemExit(f"pad {pad['ref']}.{pad['id']} at {pad['x']:.2f},{pad['y']:.2f} has no on-board cell")
        return cells

    segments: list[str] = []
    vias: list[str] = []

    def emit(path: list[tuple[int, int, int]], nid: int) -> None:
        if len(path) < 2:
            return
        pts = [(coord(ix, iy)[0], coord(ix, iy)[1], lay) for ix, iy, lay in path]
        run = [pts[0]]
        runs = []
        for p in pts[1:]:
            if p[2] != run[-1][2]:
                runs.append(run)
                vx, vy, _ = run[-1]
                vias.append(
                    f'\t(via (at {vx:.3f} {vy:.3f}) (size 0.8) (drill 0.4) '
                    f'(layers "F.Cu" "B.Cu") (net {nid}) (uuid {uid()}))'
                )
                stamp_disk(vx, vy, 1.2, (0, 1))
                run = [(p[0], p[1], p[2])]
                continue
            if len(run) >= 2:
                ax, ay, _ = run[-2]
                bx, by, _ = run[-1]
                if abs((bx - ax) * (p[1] - by) - (by - ay) * (p[0] - bx)) < 1e-6:
                    run[-1] = p
                    continue
            run.append(p)
        runs.append(run)
        layer_name = {0: "F.Cu", 1: "B.Cu"}
        for run in runs:
            for (ax, ay, lay), (bx, by, _) in zip(run, run[1:]):
                if abs(ax - bx) < 1e-6 and abs(ay - by) < 1e-6:
                    continue
                segments.append(
                    f'\t(segment (start {ax:.3f} {ay:.3f}) (end {bx:.3f} {by:.3f}) '
                    f'(width {TRACK}) (layer "{layer_name[lay]}") (net {nid}) (uuid {uid()}))'
                )
                steps = max(1, int(math.hypot(bx - ax, by - ay) / (GRID / 2)))
                for i in range(steps + 1):
                    t = i / steps
                    stamp_disk(ax + (bx - ax) * t, ay + (by - ay) * t, 1.0, (lay,))

    def dijkstra(starts, goals, prefer: int, pad_block: set[tuple[int, int, int]]) -> list[tuple[int, int, int]]:
        goalset = set(goals)
        startset = set(starts)
        if startset & goalset:
            return []
        dist: dict[tuple[int, int, int], float] = {}
        parent: dict[tuple[int, int, int], tuple[int, int, int] | None] = {}
        pq: list[tuple[float, int, tuple[int, int, int]]] = []
        seq = 0
        for s in starts:
            dist[s] = 0
            parent[s] = None
            heapq.heappush(pq, (0, seq, s))
            seq += 1
        found = None
        while pq:
            cost, _, cur = heapq.heappop(pq)
            if cost != dist.get(cur):
                continue
            if cur in goalset:
                found = cur
                break
            ix, iy, lay = cur
            nbrs = []
            for dix, diy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nbrs.append(((ix + dix, iy + diy, lay), 1 if lay == prefer else 4))
            nbrs.append(((ix, iy, 1 - lay), 18))
            for nxt, step in nbrs:
                jx, jy, nlay = nxt
                if not (0 <= jx < nx and 0 <= jy < ny) or not on_board[jx][jy]:
                    continue
                if nxt not in startset and nxt not in goalset and (nxt in blocked or nxt in pad_block):
                    continue
                ncost = cost + step
                if ncost < dist.get(nxt, 1e18):
                    dist[nxt] = ncost
                    parent[nxt] = cur
                    heapq.heappush(pq, (ncost, seq, nxt))
                    seq += 1
        if found is None:
            return []
        path = []
        node: tuple[int, int, int] | None = found
        while node is not None:
            path.append(node)
            node = parent[node]
        path.reverse()
        return path

    # Keep maze vias off the indicator-resistor holes. The F.Cu stub already
    # ties each pad to a via 2.4 mm away.
    for ref in ("R5", "R6", "R7", "R8"):
        pad = next(p for p in pads if p["ref"] == ref and p["id"] == "1")
        stamp_disk(pad["x"], pad["y"], 1.15, (0, 1))
    order = sorted(by_net, key=lambda nid: (nid == 1, len(by_net[nid]["pads"])))
    for nid in order:
        info = by_net[nid]
        if info["name"] == "GND":
            print("GND uses the bottom pour")
            continue
        prefer = 0
        group = info["pads"]
        pad_block = pad_block_for(nid)
        copper = set(pad_cells(group[0]))
        for pad in group[1:]:
            starts = pad_cells(pad)
            if any(s in copper for s in starts):
                copper.update(starts)
                continue
            path = dijkstra(starts, copper, prefer, pad_block)
            if not path:
                raise SystemExit(f"no route for {info['name']} to {pad['ref']}.{pad['id']}")
            emit(path, nid)
            copper.update(path)
            copper.update(starts)
        print(f"routed {info['name']} ({len(group)} pads)")
    return "\n".join(escapes + segments + vias)


def _write_kicad_pcb(path: Path) -> None:
    nets = [
        (0, ""),
        (1, "GND"),
        (2, "FOCUS"),
        (3, "SHUTTER"),
        (4, "J1_RING"),
        (5, "J1_TIP"),
        (6, "J1_SLEEVE"),
        (7, "J2_RING"),
        (8, "J2_TIP"),
        (9, "J2_SLEEVE"),
        (10, "J2_FOCUS"),
        (11, "J2_SHUTTER"),
        (12, "B_FOCUS"),
        (13, "B_SHUTTER"),
        (14, "R1_LED"),
        (15, "R2_LED"),
        (16, "R3_LED"),
        (17, "R4_LED"),
        (18, "D1_A"),
        (19, "D2_A"),
        (20, "D3_A"),
        (21, "D4_A"),
    ]
    net_lines = "\n".join(f'\t(net {i} "{name}")' for i, name in nets)
    parts = _board_parts()
    _check_placement(parts)
    copper = _route_copper(parts)
    footprints = [
        _embed_footprint(
            p["lib"],
            p["name"],
            p["x"],
            p["y"],
            p["ang"],
            p["ref"],
            p["value"],
            p["nets"],
            p["dnp"],
            p["bottom"],
            p.get("mirror_x", False),
        )
        for p in parts
    ]
    edge = []
    for a, b in zip(OUTLINE, OUTLINE[1:] + OUTLINE[:1]):
        edge.append(
            f'\t(gr_line (start {a[0]} {a[1]}) (end {b[0]} {b[1]})\n'
            f'\t\t(stroke (width 0.1) (type default)) (layer "Edge.Cuts") (uuid {uid()}))'
        )
    pcb = f"""(kicad_pcb
\t(version 20241229)
\t(generator "nikonduals-gpio_trigger")
\t(generator_version "9.0")
\t(general
\t\t(thickness 1.6)
\t\t(legacy_teardrops no)
\t)
\t(paper "A4")
\t(layers
\t\t(0 "F.Cu" signal)
\t\t(2 "B.Cu" signal)
\t\t(5 "F.SilkS" user "F.Silkscreen")
\t\t(7 "B.SilkS" user "B.Silkscreen")
\t\t(1 "F.Mask" user)
\t\t(3 "B.Mask" user)
\t\t(17 "Dwgs.User" user "User.Drawings")
\t\t(19 "Cmts.User" user "User.Comments")
\t\t(25 "Edge.Cuts" user)
\t\t(31 "F.CrtYd" user "F.Courtyard")
\t\t(29 "B.CrtYd" user "B.Courtyard")
\t\t(35 "F.Fab" user)
\t\t(33 "B.Fab" user)
\t)
\t(setup
\t\t(pad_to_mask_clearance 0)
\t)
{net_lines}
{chr(10).join(edge)}
{_fxpan_silk(22.0, 42.2 + _DY, 30.0)}
\t(gr_text "J1" (at {42.5 + _DX} {11.5 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 1.0 1.0) (thickness 0.15)))
\t\t(uuid {uid()})
\t)
\t(gr_text "J2" (at {42.5 + _DX} {-0.2 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 1.0 1.0) (thickness 0.15)))
\t\t(uuid {uid()})
\t)
\t(gr_text "JP1 focus  JP2 shutter" (at {53.8 + _DX} {-6.15 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 0.6 0.6) (thickness 0.1)) (justify left))
\t\t(uuid {uid()})
\t)
\t(gr_text "1-2 both cameras" (at {53.8 + _DX} {-4.85 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 0.6 0.6) (thickness 0.1)) (justify left))
\t\t(uuid {uid()})
\t)
\t(gr_text "cut, 2-3 = J2 alone" (at {53.8 + _DX} {-3.55 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 0.6 0.6) (thickness 0.1)) (justify left))
\t\t(uuid {uid()})
\t)
\t(gr_text "focus" (at {64.8 + _DX} {20.05 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 0.8 0.8) (thickness 0.12)))
\t\t(uuid {uid()})
\t)
\t(gr_text "shutter" (at {73.8 + _DX} {20.05 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 0.8 0.8) (thickness 0.12)))
\t\t(uuid {uid()})
\t)
\t(gr_text "CAM 1" (at {80.0 + _DX} {24.05 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 0.8 0.8) (thickness 0.12)) (justify left))
\t\t(uuid {uid()})
\t)
\t(gr_text "CAM 2" (at {80.0 + _DX} {34.25 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 0.8 0.8) (thickness 0.12)) (justify left))
\t\t(uuid {uid()})
\t)
\t(gr_text "socket on bottom" (at {60 + _DX} {-5.6 + _DY}) (layer "B.SilkS")
\t\t(effects (font (size 0.8 0.8) (thickness 0.1)) (justify left mirror))
\t\t(uuid {uid()})
\t)
\t(gr_text "1" (at {30 + _DX} {-5.45 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 1.0 1.0) (thickness 0.15)))
\t\t(uuid {uid()})
\t)
\t(gr_text "1" (at {30 + _DX} {-5.45 + _DY}) (layer "B.SilkS")
\t\t(effects (font (size 1.0 1.0) (thickness 0.15)) (justify mirror))
\t\t(uuid {uid()})
\t)
\t(gr_text "40" (at {82.2 + _DX} {-5.2 + _DY}) (layer "F.SilkS")
\t\t(effects (font (size 1.0 1.0) (thickness 0.15)))
\t\t(uuid {uid()})
\t)
\t(gr_text "40" (at {82.2 + _DX} {-5.2 + _DY}) (layer "B.SilkS")
\t\t(effects (font (size 1.0 1.0) (thickness 0.15)) (justify mirror))
\t\t(uuid {uid()})
\t)
{chr(10).join(footprints)}
{copper}
\t(zone (net 1) (net_name "GND") (layer "B.Cu") (uuid {uid()})
\t\t(hatch edge 0.5)
\t\t(priority 0)
\t\t(connect_pads (clearance 0.3))
\t\t(min_thickness 0.25)
\t\t(filled_areas_thickness no)
\t\t(fill (thermal_gap 0.3) (thermal_bridge_width 0.4))
\t\t(polygon (pts
\t\t\t(xy {22.4 + _DX} {-11.95 + _DY}) (xy {86.4 + _DX} {-11.95 + _DY}) (xy {86.4 + _DX} {42.3 + _DY}) (xy {22.4 + _DX} {42.3 + _DY})
\t\t))
\t)
)
"""
    path.write_text(pcb)
    _fill_zones(path)


def _fill_zones(path: Path) -> None:
    """Pour the bottom GND zone so the saved board matches fabrication."""
    py = Path("/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3")
    if not py.exists():
        return
    script = (
        "import pcbnew\n"
        f"b = pcbnew.LoadBoard({str(path)!r})\n"
        "pcbnew.ZONE_FILLER(b).Fill(b.Zones())\n"
        f"b.Save({str(path)!r})\n"
    )
    subprocess.run([str(py), "-c", script], check=True, capture_output=True)


def write_kicad_project(kdir: Path) -> None:
    kdir.mkdir(parents=True, exist_ok=True)
    pro_path = kdir / "gpio_trigger.kicad_pro"
    if not pro_path.exists():
        pro = {
            "board": {"design_settings": {"defaults": {"board_outline_line_width": 0.1}}},
            "meta": {"filename": "gpio_trigger.kicad_pro", "version": 3},
            "net_settings": {
                "classes": [{"name": "Default", "track_width": 0.25, "via_diameter": 0.8, "via_drill": 0.4}],
            },
            "pcbnew": {"last_paths": {"gencad": "", "idf": "", "netlist": "", "specctra_dsn": "", "step": ""}},
            "schematic": {"legacy_lib_dir": "", "legacy_lib_list": []},
            "sheets": [[SHEET_UUID, ""]],
            "text_variables": {},
        }
        pro_path.write_text(json.dumps(pro, indent=2) + "\n")

    _write_kicad_schematic(kdir / "gpio_trigger.kicad_sch")
    _write_kicad_pcb(kdir / "gpio_trigger.kicad_pcb")

    (kdir / "README.md").write_text(
        textwrap.dedent(
            """# KiCad project

1. Open `gpio_trigger.kicad_pro` in KiCad 9.
2. Schematic and PCB are generated by `python3 ../gen_cad.py` — parts placed, traces routed, bottom GND pour filled.
3. Both 3.5 mm jacks are on the pin-1 end of the header (away from the Pi Ethernet jack). Solder the 2×20 socket on the bottom.
4. Fabrication zip: `../fab/pcbway/gpio_trigger-pcbway.zip`.

Reference drawings: `../schematic.svg`, `../layout-pcb.svg`, `../layout-perf.svg`.
"""
        )
    )


def write_board_md(path: Path) -> None:
    path.write_text(
        textwrap.dedent(
            """# Board assembly

## Files

| File | Purpose |
|------|---------|
| [schematic.svg](schematic.svg) | Full electrical schematic |
| [layout-perf.svg](layout-perf.svg) | Perfboard + Hammond 1591TBK placement |
| [layout-pcb.svg](layout-pcb.svg) | PCB: both jacks on the pin-1 end, socket on the bottom |
| [netlist.csv](netlist.csv) | Connection list for wiring / KiCad |
| [kicad/](kicad/) | KiCad schematic + placed footprints |

Regenerate everything: `python3 gen_cad.py`

## PCB

The KiCad board is routed and stays inside the Raspberry Pi 4 outline. Both TRS jacks face out the **pin-1** end, away from Ethernet, with the plug mouth at that edge so a chassis wall can meet them. The right edge stops short of the USB and Ethernet jacks. Four 2.7 mm holes (H1–H4) match the Pi’s M2.5 standoffs. Solder the 2×20 female socket on the **bottom**. Pin 1 (square pad) meets Pi pin 1. Gerbers are in `fab/pcbway/`.

JP1 (focus) and JP2 (shutter) ship with pads 1–2 bridged, so both cameras follow pin 38 and pin 40. To drive camera B on its own pins, cut that bridge and solder pad 2 to pad 3. J1 stays on pin 38 / pin 40.

## Perfboard build (alternate)

1. **Board:** 50×70 mm veroboard, 2.54 mm pitch ([BOM](bom.md)).
2. **Enclosure:** drill one **6 mm** hole on each side wall — **J1** plug exits the right side, **J2** the left side (see `layout-perf.svg`).
3. **Mount** perfboard on standoffs; jacks on panel, wired to board edge.
4. **Orientation:** Input (resistors + LED side of 4N35) faces **left** toward Pi harness; output (transistor side) faces **right** toward jacks.
5. **Solder order:** jacks and 4N35 sockets first, resistors, then bus wires (focus, shutter, GND).

## 4N35 orientation

```
      ┌─────────┐
  1 ──┤ ●     ● ├── 6  (collector, tie to 5 or use 5 only)
  2 ──┤       ● ├── 5  → ring or tip
  3 ──┤       ● ├── 4  → sleeve (per jack)
      └─────────┘
   cathode ↑ anode
```

Pin 1 faces **left** (toward resistors) on the layout drawing.

## Pi connection

The PCB uses a **2×20 female socket** and plugs onto the Pi's 40-pin GPIO header.

| Pi physical pin | BCM | Net |
|-----------------|-----|-----|
| 35 | 19 | J2 shutter, only if JP2 pad 2–3 is bridged |
| 37 | 26 | J2 focus, only if JP1 pad 2–3 is bridged |
| 38 | 20 | FOCUS (J1, and J2 while JP1 pads 1–2 are bridged) |
| 39 | — | GND (opto LED cathodes and optional indicator LEDs only) |
| 40 | 21 | SHUTTER (J1, and J2 while JP2 pads 1–2 are bridged) |

Pin 1 of the socket is the square pad and must meet pin 1 on the Pi.

## Optional trigger LEDs

Four 5 mm LEDs, each with its own 330 Ω, on the **Pi side** of the optos. **D1** / **R5** is camera 1 focus (pin 38). **D2** / **R6** is camera 1 shutter (pin 40). **D3** / **R7** is camera 2 focus and **D4** / **R8** is camera 2 shutter: they follow pin 38/40 while the jumpers are bridged, and pin 37/35 after you cut and bridge 2–3. Marked DNP in the schematic. Leave an LED and its resistor off together to omit that lamp. Do not put these LEDs on the camera side of the 4N35.

## Test

```bash
python3 gpio_seq.py --hold-focus   # meter: ring→sleeve on both jacks
python3 gpio_seq.py                # full sequence
```
"""
        )
    )


def main() -> None:
    write_schematic_svg(ROOT / "schematic.svg")
    write_layout_perf(ROOT / "layout-perf.svg")
    write_layout_pcb(ROOT / "layout-pcb.svg")
    write_netlist(ROOT / "netlist.csv")
    write_board_md(ROOT / "BOARD.md")
    write_kicad_project(ROOT / "kicad")
    print("Wrote schematic.svg, layout-perf.svg, layout-pcb.svg, netlist.csv, BOARD.md, kicad/")


if __name__ == "__main__":
    main()
