/** Default kit: Corona SLR clip on 39/40, same as cam/gpio.py. */

export function shutterClip() {
  return {
    id: "shutter",
    name: "Shutter clip",
    note: "Corona SLR · GND 39 + BCM 21 / pin 40 · 3.5 mm → Y-lead",
    color: "#ff6a00",
    pins: [39, 40],
  };
}

export function defaultProject() {
  return {
    board: "pi40",
    thickness: 0.5,
    hole: 0.95,
    margin: 3.2,
    collarH: 0.3,
    capUnused: true,
    devices: [shutterClip()],
  };
}
