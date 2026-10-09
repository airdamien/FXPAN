# FXPAN

Two Nikon D800 bodies behind one Nikkor-W 180 mm f/5.6. A 50 × 75 mm
beamsplitter sends each body half of the field. The stitch is

**64.80 × 23.9 mm · 2.711:1 · 13248 × 4912 · 65.1 MP**

XPan is 65 × 24 mm at 2.708:1. It is shot from f/5.6 to f/22. The
Nikkor-W covers the stitch wide open. The 44 mm mouths fully clear the
extreme corners from f/8.4; at f/5.6 those corners still pass most of the
light, and the long axis stays clean. The iPhone is the viewfinder and the
stitcher, and it can release both bodies over USB. A Pi Zero and the trigger
board are optional. They pulse both 10-pin remotes together.

![Assembled. Nikkor-W to the left, a D800 on each arm, trigger board on the lid.](docs/build/assembly.png)

![The rig: two D800s, the trigger board, the iPhone](docs/build/rig.jpg)

Buy list, print list, and assembly: [bom.md](bom.md).
The model, the measured focus numbers, and the long alignment notes:
[openscad/fxpan/README.md](openscad/fxpan/README.md).

![The phone on the camera.](docs/build/ios.jpg)

## On the phone

Landscape on an iPhone 17 Pro Max, in simulate mode.

![Home. The stitch on the left, the shutter on the right, six controls along the bottom.](docs/ios/home.png)

![Frame. Format, guide lines, and whether the edges clip to the overlap.](docs/ios/frame.png)

![Light. Mode, ISO, and shutter for both bodies.](docs/ios/light.png)

![Focus. Peaking, loupe, or range.](docs/ios/focus.png)

![Look. The base, the film stocks, and the color step.](docs/ios/look.png)

![Drive. USB, or the 10-pin sync.](docs/ios/drive.png)

![White balance.](docs/ios/wb.png)

Partly folded on an iPhone Duo. The picture and the last shots stay above the hinge. The controls and the shutter sit below it.

![Half open.](docs/ios/duo-folded.png)

## A Canon, as a try

System has a Canon switch. It stays off until you turn it on. One body, not the pair, and not the stitch.

The camera's USB connection is photo import / remote control. Live view, the shutter, and the copy use that body. The JPEG shows in the roll. A CR3 is saved beside it. The file stays on the card. Turn the switch off and the Nikon pair is back.

## How it goes together

The plate is in the tray, coating toward the lens, 75 mm across the fold.
The two arms leave the box at a right angle. The base carries both bodies.
The mouths are printed F. The lens is the Nikkor-W.

![Mid-build. One body on, the Nikkor-W in the stem, the trigger board on the lid.](docs/build/mid.jpg)

![Lid off. The blue plate is the 50 × 75 mm splitter.](docs/build/assembly-open.png)

![Pulled apart: lens, stem, arms, tray, lid, base.](docs/build/assembly-exploded.png)

![From above. One lens, two bodies.](docs/build/assembly-plan.png)

![The Nikkor-W and the trigger board, from the lens side.](docs/build/assembly-lens.png)

The board is optional. USB release fires both bodies and brings the frames back. The board is the 10-pin path: blue is focus, red is shutter, one pair for each body.

![The built trigger board. Blue is focus, red is shutter, one pair for each body. USB release does not need it.](docs/build/trigger.jpg)

## What the two frames become

![Field, stitched](docs/build/field.jpg)

![Prints: the field, and the tree line](docs/build/prints.jpg)

## The ray trace

The plate is 75 mm across the fold. At 45° that presents 53 mm, against the
44 mm the stitch needs at f/5.6.

![Plan of the fold](docs/kraken/fxpan_paths.png)

![Each sensor at f/5.6](docs/kraken/fxpan_frames.png)

![The stitch at f/11](docs/kraken/fxpan_pano.png)

![What has to pass, and what is there](docs/kraken/fxpan_margins.png)

A 2× anamorphic on the front of the 180 is drawn, not fitted on this rig.
Spherical is 20.3° at 50 m. 1.5× is 30.1°. 2× is 39.5°.

![Spherical against 1.33×, 1.5×, and 2×](docs/kraken/fxpan_anamorph_scene.png)

```
python kraken/fxpan_paths.py    # exits non-zero if the body and the numbers disagree
python kraken/fxpan_scene.py    # the countryside above
```

## Where the rest went

The D7000 hybrid, the V, the shifted kits, the 5D and α7 forks, and their
export scripts are in [archive/](archive/EARLIER.md). They are not this camera.

## Credits

The D800s in the assembly pictures are mariusimv's approximate model,
[Thingiverse #4815092](https://www.thingiverse.com/thing:4815092).

The printed F mouths start from Archive-663's Nikon mount,
[CC BY-NC-SA 4.0](https://github.com/Archive-663/lensMounts).

The metric threads are Ryan A. Colyer's `threads.scad`,
[CC0](https://www.thingiverse.com/thing:1686322).

The earlier D7000 ghost and the stand-in lens barrel are José Pedro's
Nikon DSLR,
[Printables #1733741](https://www.printables.com/model/1733741-nikon-dslr-camera-model-3d-printable),
CC BY-NC-SA 4.0.

The monitor case is Wormfingers' HAMTYSAN 10.1 enclosure,
[Printables #1041827](https://www.printables.com/model/1041827-hamtysan-101-touchscreen-enclosure),
CC BY 4.0.

The Pi 4 in those older pictures is a Printables mesh, lined up to
[Raspberry Pi's mechanical drawing](https://datasheets.raspberrypi.com/rpi4/raspberry-pi-4-mechanical-drawing.pdf).

The countryside in the anamorphic figure is
[Radek Hloch, CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:Landscape_of_Tuscany_3.jpg).

The app is set in Jost, SIL Open Font License 1.1,
[The Jost Project Authors](https://github.com/indestructible-type/Jost).
