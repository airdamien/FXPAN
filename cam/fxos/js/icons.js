// One stroke family on a 24 px grid: the symbol for recognition, the word
// beside it for explanation.
const PATHS = {
  frame: '<rect x="2.5" y="7" width="19" height="10" rx="1.5"/><path d="M6 7v10M18 7v10" opacity=".35"/>',
  light: '<circle cx="12" cy="12" r="3.6"/><path d="M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"/>',
  focus: '<path d="M4 8.5V5.2c0-.7.5-1.2 1.2-1.2h3.3M15.5 4h3.3c.7 0 1.2.5 1.2 1.2v3.3M20 15.5v3.3c0 .7-.5 1.2-1.2 1.2h-3.3M8.5 20H5.2c-.7 0-1.2-.5-1.2-1.2v-3.3"/><circle cx="12" cy="12" r="2.6"/>',
  look: '<path d="M12 3.2a8.8 8.8 0 1 0 0 17.6c1.1 0 1.8-.8 1.8-1.7 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-.9.8-1.7 1.8-1.7h2.2a4 4 0 0 0 4-4c0-4.4-4-7.8-8.8-7.8z"/><circle cx="7.6" cy="11.2" r="1.1"/><circle cx="10.4" cy="7.4" r="1.1"/><circle cx="15" cy="7.6" r="1.1"/>',
  drive: '<rect x="4" y="3.8" width="16" height="4.6" rx="1.4"/><rect x="4" y="9.7" width="16" height="4.6" rx="1.4"/><rect x="4" y="15.6" width="16" height="4.6" rx="1.4"/>',
  wb: '<path d="M10 14.4V5a2 2 0 1 1 4 0v9.4a3.6 3.6 0 1 1-4 0z"/><path d="M12 9.5v6.3"/>',
  aperture: '<circle cx="12" cy="12" r="8.8"/><path d="M14.4 3.5 9.2 12.4M20.4 9.4H10M18.3 18.2 13.2 9.3M9.6 20.5l5.1-8.9M3.6 14.6H14M5.7 5.8l5.1 8.9"/>',
  play: '<rect x="3" y="4.5" width="18" height="15" rx="2"/><path d="m10.2 9 5 3-5 3z"/>',
  card: '<path d="M7.2 3h8l3.8 3.8V20a1 1 0 0 1-1 1H7.2a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M10 6.5v2.4M12.8 6.5v2.4M15.6 7.6v1.3"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 13.5a7.7 7.7 0 0 0 0-3l2-1.6-2-3.4-2.4.9a7.6 7.6 0 0 0-2.6-1.5L14 2.5h-4l-.4 2.4A7.6 7.6 0 0 0 7 6.4l-2.4-.9-2 3.4 2 1.6a7.7 7.7 0 0 0 0 3l-2 1.6 2 3.4 2.4-.9a7.6 7.6 0 0 0 2.6 1.5l.4 2.4h4l.4-2.4a7.6 7.6 0 0 0 2.6-1.5l2.4.9 2-3.4z"/>',
  wifi: '<path d="M2.6 9a13.6 13.6 0 0 1 18.8 0M5.6 12.4a9.4 9.4 0 0 1 12.8 0M8.6 15.8a5 5 0 0 1 6.8 0"/><circle cx="12" cy="19.1" r=".8"/>',
  user: '<circle cx="12" cy="8" r="3.6"/><path d="M4.8 20c.8-3.6 3.6-5.6 7.2-5.6s6.4 2 7.2 5.6"/>',
  chev: '<path d="m9.5 5.5 6.5 6.5-6.5 6.5"/>',
  back: '<path d="m14.5 5.5-6.5 6.5 6.5 6.5"/>',
  check: '<path d="m5 12.6 4.4 4.4L19 7.4"/>',
  close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8.2 10.5V8a3.8 3.8 0 0 1 7.6 0v2.5"/>',
  unlock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8.2 10.5V8a3.8 3.8 0 0 1 7.3-1.5"/>',
  trash: '<path d="M4 6.8h16M9.2 6.8V4.4h5.6v2.4M6.4 6.8l1 13.2h9.2l1-13.2M10.2 10.5v6M13.8 10.5v6"/>',
  download: '<path d="M12 3.8v11M7.2 10.4 12 15.2l4.8-4.8M4.8 20h14.4"/>',
  stitch: '<rect x="2.5" y="7" width="11" height="10" rx="1.4"/><rect x="10.5" y="7" width="11" height="10" rx="1.4"/><path d="M10.5 9.5v5M13.5 9.5v5" opacity=".45"/>',
  camera: '<path d="M4 8h3l1.6-2.2h6.8L17 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/><circle cx="12" cy="13.2" r="3.4"/>',
  usb: '<path d="M12 3v13.4M9.4 5.6 12 3l2.6 2.6M12 13l-4.6-2.6V8.2M12 11.2l4.6-2.6V6.8"/><circle cx="12" cy="18.6" r="1.8"/><rect x="6.4" y="6.6" width="2" height="2" rx=".4"/><circle cx="16.6" cy="6" r="1"/>',
  display: '<rect x="2.8" y="4" width="18.4" height="12" rx="1.6"/><path d="M8.6 20h6.8M12 16v4"/>',
  power: '<path d="M12 3.2v8.2"/><path d="M6.4 6.8a7.8 7.8 0 1 0 11.2 0"/>',
  info: '<circle cx="12" cy="12" r="8.8"/><path d="M12 11v5.6M12 7.6v.1"/>',
  rig: '<rect x="2.5" y="8" width="7" height="8" rx="1.3"/><rect x="14.5" y="8" width="7" height="8" rx="1.3"/><path d="M9.5 12h5M12 5v2M12 17v2"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  copy: '<rect x="8.4" y="8.4" width="11.6" height="11.6" rx="2"/><path d="M15.6 8.4V5.2c0-.7-.5-1.2-1.2-1.2H5.2C4.5 4 4 4.5 4 5.2v9.2c0 .7.5 1.2 1.2 1.2h3.2"/>',
  pencil: '<path d="M4 20h4.2L19.6 8.6a2 2 0 0 0 0-2.8l-1.4-1.4a2 2 0 0 0-2.8 0L4 15.8z"/><path d="m13.8 6 4.2 4.2"/>',
  reset: '<path d="M4.4 12a7.6 7.6 0 1 0 2.2-5.4"/><path d="M4 4.2v4h4"/>',
  save: '<path d="M5 4h11.2L20 7.8V19a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z"/><path d="M8 4v4.6h7.2V4M7.8 20v-6h8.4v6"/>',
  eye: '<path d="M2.4 12S5.8 5.6 12 5.6 21.6 12 21.6 12 18.2 18.4 12 18.4 2.4 12 2.4 12z"/><circle cx="12" cy="12" r="3"/>',
  eyeoff: '<path d="M2.4 12S5.8 5.6 12 5.6 21.6 12 21.6 12 18.2 18.4 12 18.4 2.4 12 2.4 12z" opacity=".5"/><path d="M4 4l16 16"/>',
  timer: '<circle cx="12" cy="13.2" r="7.8"/><path d="M12 9.2v4.2l2.6 2.4M9.4 2.6h5.2M12 2.6v2.8"/>',
  sync: '<rect x="2.4" y="7.6" width="6.4" height="8.8" rx="1.4"/><rect x="15.2" y="7.6" width="6.4" height="8.8" rx="1.4"/><path d="M8.8 12h6.4"/><path d="m12.6 9.8 2.6 2.2-2.6 2.2"/>',
  flip: '<path d="M12 3v18" stroke-dasharray="2 2.4"/><path d="M8.6 7 3.6 12l5 5zM15.4 7l5 5-5 5z"/>',
  bolt: '<path d="M13 2.8 5.2 13.4h6L10.8 21l8-10.6h-6z"/>',
  keys: '<rect x="2.6" y="6" width="18.8" height="12" rx="2"/><path d="M6.4 9.8h.1M9.6 9.8h.1M12.8 9.8h.1M16 9.8h.1M7.8 14.2h8.4"/>',
  flask: '<path d="M9.4 3h5.2M10.4 3v6.2L4.8 18.8a1.6 1.6 0 0 0 1.4 2.4h11.6a1.6 1.6 0 0 0 1.4-2.4L13.6 9.2V3"/><path d="M7.6 14.6h8.8" opacity=".5"/>',
  compare: '<rect x="3" y="5" width="18" height="14" rx="1.6"/><path d="M12 3v18"/><path d="M5.6 15.6l3-3.6 2.4 2.4" opacity=".6"/>',
  grid: '<rect x="3.6" y="3.6" width="7" height="7" rx="1.2"/><rect x="13.4" y="3.6" width="7" height="7" rx="1.2"/><rect x="3.6" y="13.4" width="7" height="7" rx="1.2"/><rect x="13.4" y="13.4" width="7" height="7" rx="1.2"/>',
  battery: '<rect x="2.6" y="7.4" width="16.4" height="9.2" rx="2"/><path d="M21.4 10.6v2.8"/>',
};

export function mountIcons() {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("aria-hidden", "true");
  svg.style.cssText = "position:absolute;width:0;height:0;overflow:hidden";
  svg.innerHTML = Object.entries(PATHS)
    .map(([name, d]) => `<symbol id="i-${name}" viewBox="0 0 24 24">${d}</symbol>`)
    .join("");
  document.body.prepend(svg);
}

export function icon(name, cls = "") {
  return `<svg class="ic${cls ? " " + cls : ""}" aria-hidden="true"><use href="#i-${name}"/></svg>`;
}
