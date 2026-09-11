# DX bodies for this build

Drop-in **F-mount DX** only — same 46.5 mm register, same ~23.5×15.6 mm window, so the printed arms / toe / Kraken stitch still match. The taking-lens iris stays on the enlarger; AF and the OVF do not matter. What does: **pixels on the stitch**, **no AA filter**, **high ISO** (hybrid 50/50 is −1 stop), **MC-DC2** (keep the Y-lead), **USB PTP** for `cam/web.py` live view, and a screen you can still see when the body is on +X / +Y.

Nikon DX **never went past 24.2 MP**. The ceiling is the 2013 D7100/D7200 / D5300-family chip (6000×4000). After that Nikon *dropped* to **20.9 MP** (D500, D7500, every Z DX including Z50 II) for readout and high ISO. The 26 / 32 / 40 MP APS-C numbers are Canon, Sony, and Fuji — not Nikon. A Z7/Z8 DX *crop* is ~19 MP off a 45.7 MP FX sensor, not a native DX body.

Prices are **2026 US used-body guesses** (private sale / mid KEH), not mint-boxed. Buy two that match (same model, similar shutter count).

## F-mount, cheapest first

| Body | Used $ | Pair ×2 | Sensor | Pitch | AA | Native ISO | Remote | Why it is better here |
|------|--------|---------|--------|-------|----|------------|--------|------------------------|
| **D5200** | $150 | **$300** | 24.1 MP · 6000×4000 | 3.9 µm | yes | 100–6400 | MC-DC2 | +49% pixels vs D7000; flip screen for chassis LV. Same ISO ceiling, worse build. |
| **D7000** | $180 | **$360** | 16.2 MP · 4928×3264 | 4.8 µm | yes | 100–6400 | MC-DC2 | What you have. Dual SD, weather, gphoto2. The stitch is ~8.9k px wide. |
| **D5300** | $190 | **$380** | 24.2 MP · 6000×4000 | 3.9 µm | **no** | 100–12800 | MC-DC2 | First cheap **no-AA** 24 MP. Enlarger glass can use the extra acuity. Flip screen. |
| **D5500** | $240 | **$480** | 24.2 MP · 6000×4000 | 3.9 µm | **no** | 100–25600 | MC-DC2 | Same 24 MP / no AA, touch flip screen, lighter. |
| **D7100** | $270 | **$540** | 24.1 MP · 6000×4000 | 3.9 µm | **no** | 100–6400 | MC-DC2 | D7000-shaped: weather, dual SD, grip. 24 MP no AA. Best “same chassis feel” upgrade. |
| **D5600** | $280 | **$560** | 24.2 MP · 6000×4000 | 3.9 µm | **no** | 100–25600 | MC-DC2 | Same sensor family as D5500. SnapBridge is unused here. |
| **D7200** | $400 | **$800** | 24.2 MP · 6000×4000 | 3.9 µm | **no** | 100–25600 | MC-DC2 | 24 MP no AA **and** two extra ISO stops vs D7000. Dual SD. The value pick if the pair budget is ~$800. |
| **D7500** | $550 | **$1,100** | 20.9 MP · 5568×3712 | 4.2 µm | yes | 100–51200 | MC-DC2 | D500 sensor: fewer pixels than a D7200, much cleaner at the ISO the 50/50 forces. USB 3, 4K, tilt. One SD slot. |
| **D500** | $800 | **$1,600** | 20.9 MP · 5568×3712 | 4.2 µm | yes | 100–51200 | **10-pin** | Same 20.9 MP / high-ISO win. Pro body, USB 3. **New remote** (not MC-DC2). Bigger / heavier on the arms. |

Skip **D3xxx** (D3300–D3500): 24 MP, but no MC-DC2 — the Y-lead you already have will not fire them. Skip **D300 / D300S / D90**: fewer pixels than the D7000.

## What the extra resolution does

Hybrid stitch width is `SENSOR_W × (2 − OVERLAP_FRAC)` ≈ **42.5 mm** at the default 0.20 overlap ([`openscad/hybrid/params.scad`](openscad/hybrid/params.scad)).

| Body | Stitch px (wide) | vs D7000 |
|------|------------------|----------|
| D7000 16.2 MP | ~8.9k | — |
| D7500 / D500 20.9 MP | ~10.1k | +13% |
| D5300–D7200 24.2 MP | ~10.8k | +22% |

The 135/5.6 circle already covers that 42.5 mm. 24 MP no-AA is the resolution upgrade; D7500/D500 is the **light-starved** upgrade (hybrid plate). On the hard-V pano both sensors get full brightness, so 24 MP wins.

Field is the same DX window. Compare native photosites on that stitch: [`docs/kraken/el135_d7200.png`](docs/kraken/el135_d7200.png).

## Same path, not the same plug: Z DX + FTZ

FTZ keeps F-register **46.5 mm**, so the optical path does not change. The stack hangs farther behind each arm. Sensor is the 20.9 MP D500 chip (not 24 MP). Live view is native (no mirror). Need **two FTZ** (~$150–200 used each) on top of the pair.

| Body | Used $ | Pair ×2 | + 2× FTZ | Sensor | Why |
|------|--------|---------|----------|--------|-----|
| **Z30** | $400 | **$800** | ~$1,100 | 20.9 MP · 5568×3712 | Cheap Z DX, no EVF, USB-C. Fine as a pair of rear screens. |
| **Z50** | $550 | **$1,100** | ~$1,400 | 20.9 MP | EVF + better LV than any F-mount PTP preview. |
| **Zfc** | $650 | **$1,300** | ~$1,600 | 20.9 MP | Same chip, worse grip on a box. |
| **Z50 II** | $850 | **$1,700** | ~$2,000 | 20.9 MP | EXPEED 7, USB-C, best tether of the DX Zs. Still 20.9 MP. |

## Practical pick

- **Cheap stitch upgrade:** two **D5300** (~$380). 24 MP, no AA, flip screen, MC-DC2.
- **Same-body-as-now upgrade:** two **D7100** (~$540) or two **D7200** (~$800) if you want the ISO as well.
- **Hybrid 50/50:** two **D7500** (~$1,100) — spend the money on high ISO, not megapixels.
- Keep the D7000s until the chassis is proven. The mount does not care.
