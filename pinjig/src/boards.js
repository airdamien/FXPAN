/** 2.54 mm headers. phys is 1-based, odd = 3V3/GPIO row, even = 5V/GPIO row. */

export const PITCH = 2.54;

const pi40 = [
  [1, null, "3V3"], [2, null, "5V"],
  [3, 2, "GPIO2 SDA"], [4, null, "5V"],
  [5, 3, "GPIO3 SCL"], [6, null, "GND"],
  [7, 4, "GPIO4"], [8, 14, "GPIO14 TXD"],
  [9, null, "GND"], [10, 15, "GPIO15 RXD"],
  [11, 17, "GPIO17"], [12, 18, "GPIO18"],
  [13, 27, "GPIO27"], [14, null, "GND"],
  [15, 22, "GPIO22"], [16, 23, "GPIO23"],
  [17, null, "3V3"], [18, 24, "GPIO24"],
  [19, 10, "GPIO10 MOSI"], [20, null, "GND"],
  [21, 9, "GPIO9 MISO"], [22, 25, "GPIO25"],
  [23, 11, "GPIO11 SCLK"], [24, 8, "GPIO8 CE0"],
  [25, null, "GND"], [26, 7, "GPIO7 CE1"],
  [27, 0, "GPIO0 ID_SD"], [28, 1, "GPIO1 ID_SC"],
  [29, 5, "GPIO5"], [30, null, "GND"],
  [31, 6, "GPIO6"], [32, 12, "GPIO12"],
  [33, 13, "GPIO13"], [34, null, "GND"],
  [35, 19, "GPIO19"], [36, 16, "GPIO16"],
  [37, 26, "GPIO26"], [38, 20, "GPIO20"],
  [39, null, "GND"], [40, 21, "GPIO21"],
];

const pi26 = pi40.filter(([n]) => n <= 26);

function board(id, name, rows) {
  const pins = rows.map(([phys, bcm, label]) => ({ phys, bcm, label }));
  return {
    id, name, pitch: PITCH, rows: 2, cols: pins.length / 2, pins,
  };
}

export const BOARDS = [
  board("pi40", "Raspberry Pi 40-pin", pi40),
  board("pi26", "Raspberry Pi 26-pin", pi26),
];

export function boardById(id) {
  return BOARDS.find((b) => b.id === id) || BOARDS[0];
}

export function pinAt(board, phys) {
  return board.pins.find((p) => p.phys === phys);
}

/** Centered on origin. Pin 1 at +Y, odd column −X. mm. */
export function pinXY(board, phys) {
  const col = Math.floor((phys - 1) / 2);
  const row = (phys - 1) % 2;
  const x = (row - 0.5) * board.pitch;
  const y = ((board.cols - 1) / 2 - col) * board.pitch;
  return { x, y };
}

export function plateSize(board, margin) {
  return {
    w: board.pitch + 2 * margin,
    h: (board.cols - 1) * board.pitch + 2 * margin,
  };
}
