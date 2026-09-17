# pinjig

Browser tool that sits a color-coded print over a pin header so a HAT or clip can only go on the right pins.

Example: the **Corona Designs SLR shutter clip** on Raspberry Pi header pins **39 (GND)** and **40 (BCM 21)** — same pair `cam/gpio.py` pulses.

```
cd pinjig
python3 -m http.server 8766
# open http://127.0.0.1:8766/
```

Print a **0.5 mm** washer. Every hole is pin-tight (~0.95 mm). **Cap unused** is a shared cavity over neighboring unused pins (walls + roof), not a chimney per pin. Assigned pins stay open for the clip. Each device is a flush inlay in its 2.54 mm cells with a gap, so neighbors do not collide.

Load `body` + device STLs as **parts of one object** (keep original coordinates — do not auto-arrange). Files are binary STL in **millimeters** (`UNITS=mm` in the header). Notch = pin 1.
