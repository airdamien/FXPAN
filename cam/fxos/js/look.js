// Looks are graded after the stitch, so both halves of a panorama always
// get the identical rendering. The preview uses an SVG filter with the
// same curve, saturation and channel mix as the stitcher's (sim.py).
import { signed } from "./model.js";

export const LOOKS = [
  { id: "standard", name: "Standard", note: "As shot" },
  { id: "neutral", name: "Neutral", note: "Flat, to grade" },
  { id: "vivid", name: "Vivid", note: "Saturated" },
  { id: "landscape", name: "Landscape", note: "Greens and blues" },
  { id: "chrome", name: "Chrome", note: "Muted, hard tone" },
  { id: "mono", name: "Mono", note: "Black and white" },
];
const BASE = {
  standard: { sat: 1, curve: 0 },
  neutral: { sat: 0.86, curve: -1.5 },
  vivid: { sat: 1.35, curve: 1.5 },
  landscape: { sat: 1.18, curve: 1, gain: [1, 1.05, 1.06] },
  chrome: { sat: 0.78, curve: 2.2 },
  mono: { sat: 0, curve: 1.2, mono: true },
};
export const FILTERS = [
  { v: "none", label: "None" },
  { v: "yellow", label: "Yellow" },
  { v: "orange", label: "Orange" },
  { v: "red", label: "Red" },
  { v: "green", label: "Green" },
];
const MIX = {
  none: [0.30, 0.59, 0.11],
  yellow: [0.40, 0.50, 0.10],
  orange: [0.50, 0.40, 0.10],
  red: [0.66, 0.30, 0.04],
  green: [0.22, 0.66, 0.12],
};
export const GRAINS = [
  { v: "off", label: "Off" },
  { v: "weak", label: "Weak" },
  { v: "strong", label: "Strong" },
];
const GRAIN = { off: 0, weak: 0.18, strong: 0.34 };
export const STEPS = ["-4", "-3", "-2", "-1", "0", "+1", "+2", "+3", "+4"];

const clamp = (v) => Math.max(-5, Math.min(5, v));
const int = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);

export function amounts(look) {
  const base = BASE[look?.base] || BASE.standard;
  return [clamp(base.curve + int(look?.shadow)), clamp(base.curve + int(look?.highlight))];
}

export function curve(x, shadow, high) {
  const k = x < 0.5 ? shadow : high;
  return Math.min(1, Math.max(0, x - k * 0.03 * Math.sin(2 * Math.PI * x)));
}

export const baseOf = (look) => LOOKS.find((l) => l.id === look?.base) || LOOKS[0];
export const isMono = (look) => !!(BASE[look?.base] || {}).mono;

export function lookName(look, custom = []) {
  const mine = custom.find((c) => c.id === look?.id);
  return mine ? mine.name : baseOf(look).name;
}

export function tweaks(look) {
  const bits = [];
  if (!isMono(look) && int(look?.color)) bits.push("Color " + signed(int(look.color)));
  if (int(look?.highlight)) bits.push("Highlight " + signed(int(look.highlight)));
  if (int(look?.shadow)) bits.push("Shadow " + signed(int(look.shadow)));
  if (isMono(look) && look?.filter && look.filter !== "none") bits.push(look.filter[0].toUpperCase() + look.filter.slice(1) + " filter");
  if (look?.grain && look.grain !== "off") bits.push("Grain " + look.grain);
  return bits;
}

function markup(look) {
  const base = BASE[look?.base] || BASE.standard;
  const parts = [];
  if (base.mono) {
    const [r, g, b] = MIX[look?.filter] || MIX.none;
    const row = `${r} ${g} ${b} 0 0`;
    parts.push(`<feColorMatrix type="matrix" values="${row} ${row} ${row} 0 0 0 1 0"/>`);
  } else {
    const sat = Math.max(0, base.sat * (1 + 0.12 * int(look?.color)));
    if (Math.abs(sat - 1) > 0.01) parts.push(`<feColorMatrix type="saturate" values="${sat.toFixed(3)}"/>`);
    if (base.gain) {
      const [a, b, c] = base.gain;
      parts.push(`<feColorMatrix type="matrix" values="${a} 0 0 0 0 0 ${b} 0 0 0 0 0 ${c} 0 0 0 0 0 1 0"/>`);
    }
  }
  const [s, h] = amounts(look);
  if (s || h) {
    const table = Array.from({ length: 33 }, (_, i) => curve(i / 32, s, h).toFixed(4)).join(" ");
    parts.push(`<feComponentTransfer><feFuncR type="table" tableValues="${table}"/>`
      + `<feFuncG type="table" tableValues="${table}"/><feFuncB type="table" tableValues="${table}"/></feComponentTransfer>`);
  }
  const grain = GRAIN[look?.grain] || 0;
  if (grain) {
    const a = (grain * 2.6).toFixed(3);
    const off = ((1 - grain * 2.6) / 2).toFixed(3);
    parts.push(
      `<feComponentTransfer result="g"><feFuncA type="identity"/></feComponentTransfer>`
      + `<feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="4" stitchTiles="stitch"/>`
      + `<feColorMatrix type="saturate" values="0"/>`
      + `<feComponentTransfer result="n"><feFuncR type="linear" slope="${a}" intercept="${off}"/>`
      + `<feFuncG type="linear" slope="${a}" intercept="${off}"/><feFuncB type="linear" slope="${a}" intercept="${off}"/>`
      + `<feFuncA type="linear" slope="0" intercept="1"/></feComponentTransfer>`
      + `<feBlend in="n" in2="g" mode="overlay"/>`);
  }
  return parts.join("");
}

let defs = null;

// An SVG filter with this id, re-rendered to the given look. Elements
// preview it with `filter: url(#id)`.
export function ensureFilter(id, look) {
  if (!defs) {
    const ns = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("aria-hidden", "true");
    svg.style.cssText = "position:absolute;width:0;height:0;overflow:hidden";
    defs = document.createElementNS(ns, "defs");
    svg.appendChild(defs);
    document.body.appendChild(svg);
  }
  const inner = markup(look);
  let el = defs.querySelector(`#${id}`);
  if (!el) {
    el = document.createElementNS("http://www.w3.org/2000/svg", "filter");
    el.id = id;
    el.setAttribute("color-interpolation-filters", "sRGB");
    el.setAttribute("x", "0"); el.setAttribute("y", "0");
    el.setAttribute("width", "1"); el.setAttribute("height", "1");
    el.setAttribute("primitiveUnits", "userSpaceOnUse");
    defs.appendChild(el);
  }
  if (el.dataset.key !== inner) {
    el.innerHTML = inner || `<feOffset dx="0" dy="0"/>`;
    el.dataset.key = inner;
  }
  return `url(#${id})`;
}
