# HAMTYSAN 10.1″ HCIK101V.CC

[Amazon B0B9M5SCG4](https://www.amazon.com/dp/B0B9M5SCG4) — 10.1″ IPS capacitive, **1024×600**, HDMI + micro-USB (5 V / 2 A, touch). No rear case. Four backside holes. OpenSCAD ghost: [`openscad/monitor/`](../../openscad/monitor/WATCH_ME.scad).

HAMTYSAN does not publish a STEP. The numbers below are the OEM outline plus the same 1024×600 glass / HDMI+CTP family.

## Published (this unit)

| | |
|---|---|
| P/N | HCIK101V.CC (Heng Cheng / WETECH / HAMTYSAN) |
| Outline | **235 × 143 × 7.3 mm** (UK listing 235×143×7; Heng Cheng CTP stack **10.4**) |
| Active area | **222.72 × 125.28 mm** |
| Pixel pitch | 0.2175 × 0.2088 mm |
| Brightness | 200–250 cd/m² (OEM vs listing) |
| Contrast | 800:1 |
| Touch | 5-point capacitive, USB HID, driver-free |
| Input | HDMI (accepts up to 1920×1080, panel is 1024×600) |
| Power | 5 V × 2 A on the micro-USB |
| Weight | ~770 g boxed (Ubuy) |

Thingiverse case for this ASIN measured the **board + jacks at 20 mm** deep and the glass about **235 × 145**. Use 20 mm behind the glass until you caliper yours.

## Drawings in this folder

| File | What it is |
|------|------------|
| [waveshare-10.1-panel.pdf](waveshare-10.1-panel.pdf) | Waveshare 10.1″ 1024×600 **glass** (235×143×5.10, AA 222.72×125.28, side M2 holes). Same outline family, **not** the HDMI board. |
| [AM-1024600-101E.pdf](AM-1024600-101E.pdf) | Amson 10.1″ 1024×600 LVDS module, same AA / outline. Page 16 is the outline. |
| [MDT1010AC-HDMI.pdf](MDT1010AC-HDMI.pdf) | Midas **HDMI + capacitive** sibling, 235×143×**14.70**. Page 9 is the only hole drawing in this class (corner locators, ~3.7 / 4.9 mm insets). Jacks and PCB will not match HAMTYSAN exactly. |

Heng Cheng table: [sz-htc product list](https://www.sz-htc.com/products_list/p-120-20.html) (HCIK101V.CC). Same outline on [Himfr](https://www.himfr.com/product-uuetkz-1gyxd6-10-1-inch-hdmi-lcd-displays-1024-600.html).

## Lid mount (Wormfingers case)

The Pi already sits on the 90 mm lid (HAT holes, USB toward −X). The 10.1″ case cannot bolt through that footprint.

[`display_mount.scad`](../../openscad/monitor/display_mount.scad) is a bridge: four feet in the free ±Y strips, 28 mm posts over the Pi, top plate with **AMPS 38×30.5** (the car-arm pattern Wormfingers built around) and a **48 mm square** (clone case-back spacing). Notch on −X for HDMI / micro-USB down to the Pi.

Lid gets four **12 mm bosses** (not through-holes — chamber stays dark). Drop an M3 nut in each boss. `display_mount` bolts down with 4× M3×10. Print the [Wormfingers enclosure](https://www.printables.com/model/1041827-hamtysan-101-touchscreen-enclosure) (4× M3×25 sandwich) and bolt its back / wall plate to the AMPS or 48 mm holes. Measure before you commit — their wall mount is a slide; the 3MF lets you resize holes.

Print `lid` outer-face up. Print `display_mount` feet down. `./export_stls.sh --hybrid lid display_mount`

Customizer: `SHOW_MONITOR=1` on the hybrid watch file.

## Printed cases (measure first)

Hole pitch **varies by batch**. Printables says so on the driver-board box.

- [Wormfingers enclosure](https://www.printables.com/model/1041827-hamtysan-101-touchscreen-enclosure) — **this is the case the lid mount is built for**, 4× M3×25 + nuts
- [prusader3D HDMI board box](https://www.printables.com/model/1118987-hdmi-driver-board-enclosure-for-wetech-hcik101vcc) — WETECH HCIK101V.CC PCB only
- [scottneumann Thingiverse #6621767](https://www.thingiverse.com/thing:6621767) — OpenSCAD case, 235×145×20

## What to caliper when it arrives

1. Glass W×H×T (expect 235×143×7–10).
2. Four hole centers (and whether they are M2 side-bezel or M3 through the back).
3. Driver-board outline and which edge HDMI / micro-USB sit on.
4. Max depth including the HDMI plug.

`openscad/monitor/params.scad` `HOLE_INSET_*` is a 5 mm placeholder until those numbers exist.
