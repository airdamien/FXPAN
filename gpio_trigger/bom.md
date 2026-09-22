# BOM — Pi dual TRS Nikon trigger

Based on [Building Block - Arduino Nano Remote Camera Trigger](https://www.instructables.com/Building-Block-Arduino-Nano-Remote-Camera-Trigger/).
**Raspberry Pi GPIO** replaces the Nano; **no battery**; **two synced 3.5 mm TRS outputs**.

**Amazon links:** Only listings that **Ship from Amazon** with **Prime 1–2 day** delivery (checked Sep 2026). Skip marketplace-only sellers and multi-week imports. If a direct link is out of stock, use the search link in that row and pick the same criteria.

## PCB version — order this

The bare board comes from PCBWay (upload [fab/pcbway/gpio_trigger-pcbway.zip](fab/pcbway/gpio_trigger-pcbway.zip)): **2-layer, 1.6 mm, FR-4, 1 oz, lead-free HASL, green mask, white silk**. These are the parts that go on that board. Perfboard, dupont jumpers, hookup wire, and a project box are not used. JP1 and JP2 are copper on the board. Pads 1–2 are already bridged, so both cameras follow pin 38 (focus) and pin 40 (shutter). Cut that bridge and solder pad 2 to pad 3 to put camera B alone on pin 37 (BCM 26, focus) and pin 35 (BCM 19, shutter).

| Qty | Item | Notes | Where |
|-----|------|--------|--------|
| 1 | **Fabricated PCB** | Stepped board, both jacks on the pin-1 end | [PCBWay zip](fab/pcbway/gpio_trigger-pcbway.zip) |
| 4 | **4N35** optocoupler, DIP-6 | Solder direct, or plug into optional sockets below. 2 per jack | [Search: 4N35 DIP-6, Prime](https://www.amazon.com/s?k=4N35+DIP-6+optocoupler&rh=p_90%3A8308921011) — pack ≥ 5, **Ships from Amazon** |
| 4 | **DIP-6 IC socket**, 7.62 mm row spacing | Optional. One per 4N35 (U1–U4). Tin-leaf or machine-pin — easier swap than soldering the chips | [Search: DIP 6 pin IC socket 7.62mm, Prime](https://www.amazon.com/s?k=DIP+6+pin+IC+socket+7.62mm&rh=p_90%3A8308921011) — **Ships from Amazon** |
| 8 | **330 Ω** resistor, ¼ W, axial | 4 required (R1–R4). R5–R8 only if you fit the matching LED. Mount standing up | [ELEGOO 525-piece 1/4 W kit](https://www.amazon.com/Elegoo-Values-Resistor-Assortment-Compliant/dp/B072BL2VX1) |
| 2 | **CUI SJ1-3535NG** 3.5 mm TRS jack, right-angle, PCB mount | Footprint on the board. **Not** a panel-mount jack — those will not fit the holes | [DigiKey SJ1-3535NG](https://www.digikey.com/en/products/detail/cui-devices/SJ1-3535NG/738699) — no matching Prime listing |
| 1 | **2×20 female pin socket**, 2.54 mm | Solder on the **bottom**. Square pad = Pi pin 1 | [Search: 2x20 female header, Prime](https://www.amazon.com/s?k=2x20+female+pin+header+2.54mm&rh=p_90%3A8308921011) — **Ships from Amazon** |
| 4 | **5 mm LED** | Optional. D1 camera 1 focus, D2 camera 1 shutter, D3 camera 2 focus, D4 camera 2 shutter (camera 2 follows the jumpers). Omit an LED and its 330 Ω together | Same ELEGOO kit — no extra order |
| 2 | **3.5 mm TRS male → Nikon 10-pin male** | One per D800. 3-pole only | [Keabroir 3.5 mm → N1 / 10-pin](https://www.amazon.com/dp/B0CYHL1B7F) — **order qty 2** |

## Perfboard version

Only if you are not ordering the PCB. Schematic: [schematic.svg](schematic.svg) · [layout-perf.svg](layout-perf.svg) · [BOARD.md](BOARD.md)

## Core board

| Qty | Item | Notes | Amazon (US) |
|-----|------|--------|-------------|
| 4 | **4N35** optocoupler, DIP-6 | Solder direct, or use optional sockets below. 2 per camera jack | [Search: 4N35 DIP-6, Prime](https://www.amazon.com/s?k=4N35+DIP-6+optocoupler&rh=p_90%3A8308921011) — pick **pack ≥ 5**, **Ships from Amazon** |
| 4 | **DIP-6 IC socket**, 7.62 mm row spacing | Optional. One per 4N35 | [Search: DIP 6 pin IC socket 7.62mm, Prime](https://www.amazon.com/s?k=DIP+6+pin+IC+socket+7.62mm&rh=p_90%3A8308921011) — **Ships from Amazon** |
| 4 | **330 Ω** resistor, ¼ W | One per opto LED (Pi 3.3 V) | [ELEGOO 525-piece 1/4 W kit](https://www.amazon.com/Elegoo-Values-Resistor-Assortment-Compliant/dp/B072BL2VX1) (includes 330 Ω × 25) |
| 2 | **3.5 mm TRS jack**, panel mount | **3-pole stereo** (tip / ring / sleeve). Not TRRS | [Lsgoodcare 10-pack panel TRS](https://www.amazon.com/Lsgoodcare-Female-Headphone-Stereo-Connector/dp/B01CVGD4UI) |
| 1 | **Perfboard** | 2.54 mm pitch; 73×100 mm OK (layout shows 50×70) | [YUNGUI 10× 73×100 mm stripboard](https://www.amazon.com/YUNGUI-Prototype-perfboard-Sording-Electronic/dp/B088GSJM7G) |
| 1 | **2×20 female pin socket**, 2.54 mm | PCB plugs onto the Pi 40-pin GPIO header. Only pins 38, 39, 40 are wired | [Search: 2x20 female header, Prime](https://www.amazon.com/s?k=2x20+female+pin+header+2.54mm&rh=p_90%3A8308921011) — **Ships from Amazon** |
| 3 | **Dupont jumper**, female–male | Perfboard only, if you are not plugging the PCB onto the Pi | [ELEGOO 235-piece kit](https://www.amazon.com/dp/B077D2N4KT) (includes 20× F–M + spare 330 Ω / 1× 4N35 for bench) |
| 4 | **5 mm LED** + **330 Ω** | Optional. D1/D2 camera 1 focus/shutter, D3/D4 camera 2 focus/shutter. Omit an LED and its resistor together | Same ELEGOO kit — no extra order |
| 1 | **22 AWG silicone wire kit** | Camera-side runs to jacks | [BNTECHGO 10×30 ft](https://www.amazon.com/dp/B0881HCN37) |
| 1 | **Heat-shrink tubing kit** | Insulate solder joints | [Ginsco 580-piece](https://www.amazon.com/Ginsco-580-pcs-Assorted-Sleeving/dp/B01MFA3OFA) |
| 1 | **Project box** | ~200×120×75 mm ABS; drill for 2 jacks | [Pinfox ABS enclosure 200×120×75](https://www.amazon.com/Waterproof-Electronic-Plastic-Junction-Enclosure/dp/B06XSMK61Q) |

### Bench LEDs (optional — Pi side only)

Included in the [ELEGOO 235-piece kit](https://www.amazon.com/dp/B077D2N4KT) above (LEDs + 330 Ω / 1 kΩ resistors). No extra order needed.

## Cables to cameras (FXPAN)

| Qty | Item | Notes | Amazon (US) |
|-----|------|--------|-------------|
| 2 | **3.5 mm TRS male → Nikon 10-pin male** | One per D800; 3-pole only | [Keabroir 3.5 mm → N1 / 10-pin](https://www.amazon.com/dp/B0CYHL1B7F) — **order qty 2** (listing is one cable) |

Vello RCCN135 and other coiled remotes are often **out of stock** on Amazon US; the Keabroir cable above is **Ships from Amazon** with Prime.

No Y-lead needed if both jacks are on this box.

## Not used (vs Instructables)

| Item | Why omitted |
|------|-------------|
| Arduino Nano | Pi BCM 20 / 21 |
| Battery / 5 V supply | Pi powers opto LEDs only |
| Tactile switches | `gpio_seq.py` |

## Pi / software

| Item | Notes |
|------|--------|
| Raspberry Pi 5 (or 4) | User `gpio` group; `python3-libgpiod` |
| `gpio_trigger/gpio_seq.py` | Focus-then-shutter test |

## Optional — MC-22 instead of TRS jacks

| Qty | Item | Notes | Where to buy |
|-----|------|--------|--------------|
| 1 | **Nikon MC-22** | Blue = focus, yellow = shutter, black = ground | [Nikon USA MC-22](https://www.nikonusa.com/p/mc-22-remote-cord-with-banana-plugs-394-in/4652/overview) — skip slow Amazon marketplace listings |

Wire opto collectors to the banana plugs; see [README.md](README.md).
