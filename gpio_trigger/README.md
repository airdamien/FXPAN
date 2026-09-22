# Dual-GPIO Nikon trigger — Pi + 2× synced TRS

Breadboard building block based on [Building Block - Arduino Nano Remote Camera
Trigger](https://www.instructables.com/Building-Block-Arduino-Nano-Remote-Camera-Trigger/)
(Captive Image Photography, 2021): **two 4N35 optocouplers** (focus + shutter),
optical isolation, focus-before-shutter in software.

Adapted for this project:

| Instructables (Nano) | This build (Pi) |
|----------------------|-----------------|
| Arduino 5 V + battery/USB | **Pi 3.3 V GPIO only** — no separate supply, no battery |
| `camFocus` / `camShutter` on D2/D3 | **BCM 20** (focus), **BCM 21** (shutter) |
| One camera output | **Two TRS jacks**, same GPIO timing → both cameras fire together |
| Tactile test switches | `gpio_seq.py` (or `cam/gpio.py` later) |

Replaces the single-channel Corona clip path for D800 10-pin bodies that require
half-press before release.

## What the Instructables circuit does

Each camera line is a **switch to ground**, not a voltage source:

1. **Focus** opto pulls **Ring → Sleeve**.
2. **Shutter** opto pulls **Tip → Sleeve** while focus stays closed.

The Nano never ties its GND to the camera. Same rule here: Pi GND only returns the
opto **LED** current; camera ground is only on the **transistor** side (TRS sleeve).

## Dual synced outputs

One Pi fires **two identical TRS jacks** in parallel — one cable per D800 (no Y-lead
required on the trigger box). Each jack gets its **own** focus + shutter opto so load
and wiring stay independent; both opto LEDs on a channel share one GPIO through
**separate** series resistors (do not daisy-chain one resistor into two LEDs).

```
                         ┌── 330Ω ── 4N35 U1 ── J1 Ring (focus)
  Pi BCM 20 (focus) ─────┤
                         └── 330Ω ── 4N35 U3 ── J2 Ring (focus)

                         ┌── 330Ω ── 4N35 U2 ── J1 Tip (shutter)
  Pi BCM 21 (shutter) ───┤
                         └── 330Ω ── 4N35 U4 ── J2 Tip (shutter)

  J1 Sleeve ── U1 E + U2 E ── (camera A ground)
  J2 Sleeve ── U3 E + U4 E ── (camera B ground)

  Pi GND ── cathodes of all four LED sides (pins 2 on 4N35)
```

GPIO HIGH → LED on → phototransistor on → that TRS contact shorted to sleeve.

## 4N35 pinout (DIP)

```
     (pin 1) LED anode  ─── GPIO via 330Ω
     (pin 2) LED cathode ─── Pi GND
     (pin 3) NC (base)   ─── leave open
     (pin 4) emitter     ─── TRS sleeve (per jack)
     (pin 5) collector   ─── TRS ring or tip
     (pin 6) collector   ─── same as pin 5 (tie together) OR use pin 5 only
```

On **4N35**, pins 5 and 6 are both collector — either works. **PC817** is pin 1 anode,
2 cathode, 3 NC, 4 emitter, 5 collector.

## TRS → Nikon

| TRS | Function | Nikon 10-pin |
|-----|----------|--------------|
| Sleeve | Ground | Pin 6 |
| Ring | Focus / half-press | Pin 9 |
| Tip | Shutter / full-press | Pin 4 |

**Sequence:** Ring→Sleeve, hold ~50–200 ms, Tip→Sleeve, pulse, release Tip, release Ring.

Cheap cables sometimes swap Tip and Ring — swap the two GPIO dupont wires at the Pi,
not the camera grounds.

**Connector:** **3.5 mm TRS** (3-pole stereo: tip / ring / sleeve). Same as the Corona
clip output and standard 3.5→10-pin Nikon cables. Not 2.5 mm, not 4-pole TRRS.

## Pi wiring

| Signal | BCM | Physical pin |
|--------|-----|--------------|
| Focus | 20 | 38 |
| Shutter | 21 | 40 |
| GND | — | 39 (or any Pi GND) |

**Resistors:** Instructables uses ~220 Ω on 5 V Nano. On **3.3 V Pi use 330 Ω** per
opto LED (one resistor per LED, four total). Do not go below ~150 Ω.

**Do not** connect Pi GND to TRS sleeve.

## Software timing (from Instructables logic)

```text
digitalWrite(focus, HIGH);
delay(focusLead);
digitalWrite(shutter, HIGH);
delay(shutterPulse);
digitalWrite(shutter, LOW);
digitalWrite(focus, LOW);
```

Defaults in `gpio_seq.py`: focus lead **100 ms**, shutter pulse **300 ms**.

```bash
cd ~/nikonduals/gpio_trigger
python3 gpio_seq.py
python3 gpio_seq.py --focus 0.15 --shutter 0.3
python3 gpio_seq.py --hold-focus    # half-press only, for cable check
```

## Build steps (mirrors Instructables Step 1)

1. Fit **four 4N35** (or two per jack) and **two 3.5 mm TRS jacks** on perfboard.
2. **Input side:** each LED gets its own 330 Ω from the correct GPIO; all cathodes → Pi GND.
3. **Output side:** U1/U2 emitters → J1 sleeve; U3/U4 emitters → J2 sleeve.
4. U1 collector → J1 ring; U2 collector → J1 tip; U3 → J2 ring; U4 → J2 tip.
5. PCB: solder a **2×20 female socket** and plug the board onto the Pi GPIO header (pin 1 to pin 1). Only pins **38** (focus), **39** (GND), and **40** (shutter) are connected. Perfboard builds can use three dupont wires to those same pins.
6. Run `gpio_seq.py` with USB unplugged or released (D800 ignores 10-pin while USB is claimed).

Optional indicators, grouped on the board and labeled **focus** / **shutter** under **CAM 1** and **CAM 2**. Each is a 5 mm LED plus its own 330 Ω on the Pi side of the optos. **D1** / **D2** are camera 1 focus / shutter (pin 38 / pin 40). **D3** / **D4** are camera 2 focus / shutter: they follow pin 38/40 while JP1/JP2 are bridged, and pin 37/35 after you cut and bridge 2–3. Leave an LED and its resistor off together if you don't want that lamp.

## Enclosure / rig

- Both 3.5 mm jacks sit together on the **pin-1** end of the GPIO socket and face out that edge, away from the Pi's Ethernet port
- **J1** (upper jack) → D800 top (T). **J2** (lower jack) → D800 right (R)
- The 2×20 socket is soldered on the **bottom** and plugs onto the Pi. Square pad is pin 1
- Same electrical event on both jacks within opto + GPIO skew (sub-ms).

Your existing FlashZebra **Y-lead is optional** if this box already has two outputs.

## Schematics & layout

| File | Description |
|------|-------------|
| [schematic.svg](schematic.svg) | Electrical schematic (Pi → 4× 4N35 → 2× TRS) |
| [layout-perf.svg](layout-perf.svg) | Perfboard + Hammond 1591TBK placement |
| [layout-pcb.svg](layout-pcb.svg) | PCB: both jacks on the pin-1 end |
| [fab/pcbway/](fab/pcbway/) | PCBWay gerber zip |
| [netlist.csv](netlist.csv) | Wire-by-wire connection list |
| [BOARD.md](BOARD.md) | Assembly notes |
| [kicad/](kicad/) | KiCad project — full schematic + placed PCB footprints |

Regenerate: `python3 gen_cad.py`

## Parts list

See [bom.md](bom.md).

## Safety

- 4N35 isolation is mandatory — same rationale as the Instructables article.
- No battery: Pi powers only the opto LEDs; cameras bias their own remote lines.
- Unplug or USB-release before trusting 10-pin fire during bring-up.

## Reference

- [Instructables: Building Block - Arduino Nano Remote Camera Trigger](https://www.instructables.com/Building-Block-Arduino-Nano-Remote-Camera-Trigger/)
