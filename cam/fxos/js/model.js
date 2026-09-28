// The photographic state: one object for Frame, Light, Focus, Look, Drive
// and WB. Pieces web.py already persists (exposure, trigger, stitch) stay
// in its settings; the rest lives in the fxos store. A mode is a saved
// copy of the whole object.
import * as api from "./api.js";

export const ISO = ["Auto", "100", "125", "160", "200", "250", "320", "400", "500", "640",
  "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000", "6400", "12800", "25600"];
export const SHUT = ["Auto", "30", "20", "15", "10", "8", "6", "4", "3", "2", "1.6", "1.3", "1",
  "0.8", "0.6", "0.5", "1/3", "1/4", "1/5", "1/6", "1/8", "1/10", "1/13", "1/15", "1/20", "1/25",
  "1/30", "1/40", "1/50", "1/60", "1/80", "1/100", "1/125", "1/160", "1/200", "1/250", "1/320",
  "1/400", "1/500", "1/640", "1/800", "1/1000", "1/1250", "1/1600", "1/2000", "1/2500", "1/3200",
  "1/4000", "1/5000", "1/6400", "1/8000"];
export const FSTOP = ["Auto", "1.4", "1.8", "2", "2.2", "2.5", "2.8", "3.2", "3.5", "4", "4.5",
  "5", "5.6", "6.3", "7.1", "8", "9", "10", "11", "13", "14", "16", "18", "20", "22"];
export const PROGRAMS = [
  { v: "M", label: "M", sub: "Manual" },
  { v: "A", label: "A", sub: "Aperture" },
  { v: "S", label: "S", sub: "Shutter" },
  { v: "P", label: "P", sub: "Program" },
];
export const WB = [
  { v: "Auto", label: "Auto", k: 0 },
  { v: "Sunny", label: "Daylight", k: 5200 },
  { v: "Cloudy", label: "Cloudy", k: 6000 },
  { v: "Shade", label: "Shade", k: 8000 },
  { v: "Tungsten", label: "Incandescent", k: 3000 },
  { v: "Fluorescent", label: "Fluorescent", k: 4200 },
  { v: "Flash", label: "Flash", k: 5400 },
];
export const QUALITY = [
  { v: "NEF+Fine", label: "NEF + JPEG", sub: "14-bit raw kept" },
  { v: "JPEG Fine", label: "JPEG Fine", sub: "Smallest sets" },
  { v: "JPEG Normal", label: "JPEG Normal", sub: "" },
  { v: "NEF (Raw)", label: "NEF only", sub: "Stitch uses the preview" },
];
// 13248 × 4912 native. The adapter squeezes, the stitch desqueezes.
export const FORMATS = [
  { sq: 1, label: "65:24", name: "Native", sub: "2.71:1 · 65 MP" },
  { sq: 1.33, label: "3.6:1", name: "Anamorphic 1.33×", sub: "86 MP" },
  { sq: 1.5, label: "4.07:1", name: "Anamorphic 1.5×", sub: "98 MP" },
  { sq: 2, label: "5.42:1", name: "Anamorphic 2×", sub: "130 MP" },
];
export const NATIVE = 2.712;
export const GUIDES = [
  { v: "none", label: "None" },
  { v: "3:1", r: 3, label: "3:1", sub: "6×17" },
  { v: "2.39", r: 2.39, label: "2.39:1", sub: "Scope" },
  { v: "2:1", r: 2, label: "2:1" },
  { v: "16:9", r: 16 / 9, label: "16:9" },
  { v: "4:3", r: 4 / 3, label: "4:3" },
];
export const ENGINES = [
  { v: "hugin", label: "Hugin", sub: "Profile from the checker pairs" },
  { v: "open", label: "OpenCV", sub: "Feature match, affine" },
  { v: "match", label: "Match", sub: "Search overlap and dy" },
  { v: "blend", label: "Blend", sub: "Fixed overlap, feathered" },
  { v: "cut", label: "Cut", sub: "Fixed overlap, hard seam" },
];
export const TIMERS = [0, 2, 5, 10];
export const REVIEWS = [0, 3, 5, 10, 15];
export const AIDS = [
  { v: "off", label: "Off" },
  { v: "peaking", label: "Peaking" },
  { v: "loupe", label: "Loupe" },
];
export const PEAK_COLORS = [
  { v: "red", label: "Red", c: "#ff3b30" },
  { v: "yellow", label: "Yellow", c: "#ffd60a" },
  { v: "white", label: "White", c: "#ffffff" },
  { v: "blue", label: "Blue", c: "#40a0ff" },
];
export const PEAK_LEVELS = [
  { v: "low", label: "Low" },
  { v: "std", label: "Std" },
  { v: "high", label: "High" },
];

export const store = {
  prefs: {},
  fx: { current: {}, modes: [], looks: [], shots: {}, active: "", server: {} },
  link: null,
  pairs: [],
  disk: null,
  queue: null,
  wifi: null,
  gpio: null,
  bright: null,
  sim: null,
  kiosk: new URLSearchParams(location.search).has("kiosk"),
};

const subs = new Set();
export const on = (fn) => { subs.add(fn); return () => subs.delete(fn); };
export const emit = (what, data) => subs.forEach((fn) => { try { fn(what, data); } catch (e) { console.error(e); } });

const num = (v, d) => { const n = Number(v); return Number.isFinite(n) ? n : d; };

export function photo() {
  const p = store.prefs || {};
  const c = store.fx.current || {};
  return {
    frame: {
      squeeze: num(p.ana_squeeze, 1),
      guide: c.frame?.guide || "none",
      clip: p.crop_inner !== false,
    },
    light: {
      program: p.program || "M",
      iso: String(p.iso || "400"),
      shutter: String(p.shutter || "1/250"),
      fstop: String(p.fstop || "8").replace(/^f\/?/i, ""),
      master: p.master === "R" ? "R" : "T",
      lock_t: p.lock_t !== false,
      sync: p.sync !== false,
      follow_cam: !!p.follow_cam,
    },
    focus: {
      aid: c.focus?.aid || "peaking",
      color: c.focus?.color || "red",
      level: c.focus?.level || "std",
    },
    look: {
      id: "standard", base: "standard", color: 0, highlight: 0, shadow: 0,
      grain: "off", filter: "none", ...(c.look || {}),
    },
    drive: {
      release: p.gpio ? "sync" : "usb",
      save: p.download ? "pi" : "cards",
      quality: p.quality || "NEF+Fine",
      timer: num(c.drive?.timer, 0),
      review: num(p.preview_s, 10),
      auto_stitch: c.drive?.auto_stitch !== false,
      engine: p.stitch_mode || "hugin",
    },
    wb: p.wb || "Auto",
  };
}

// Where each photographic key is persisted.
const TO_PREFS = {
  "frame.squeeze": (v) => ({ ana_squeeze: v }),
  "frame.clip": (v) => ({ crop_inner: !!v }),
  "light.program": (v) => ({ program: v }),
  "light.iso": (v) => ({ iso: v }),
  "light.shutter": (v) => ({ shutter: v }),
  "light.fstop": (v) => ({ fstop: v }),
  "light.master": (v) => ({ master: v }),
  "light.lock_t": (v) => ({ lock_t: !!v }),
  "light.sync": (v) => ({ sync: !!v }),
  "light.follow_cam": (v) => ({ follow_cam: !!v }),
  "drive.release": (v) => ({ gpio: v === "sync" }),
  "drive.save": (v) => ({ download: v === "pi" }),
  "drive.quality": (v) => ({ quality: v }),
  "drive.review": (v) => ({ preview_s: v }),
  "drive.engine": (v) => ({ stitch_mode: v }),
  "wb": (v) => ({ wb: v }),
};
const EXPOSURE = new Set(["light.program", "light.iso", "light.shutter", "light.fstop", "drive.quality", "wb"]);

let prefsPatch = {};
let prefsTimer = 0;
let fxPatch = {};
let fxTimer = 0;
let applyTimer = 0;
const errs = new Set();
export const onError = (fn) => errs.add(fn);
const fail = (e) => errs.forEach((fn) => fn(e));

export function set(key, value) {
  const toPrefs = TO_PREFS[key];
  if (toPrefs) {
    const patch = toPrefs(value);
    Object.assign(store.prefs, patch);
    Object.assign(prefsPatch, patch);
    clearTimeout(prefsTimer);
    prefsTimer = setTimeout(flushPrefs, 250);
    if (EXPOSURE.has(key)) scheduleApply();
  } else {
    const [sec, sub] = key.split(".");
    const cur = store.fx.current;
    if (sec === "look") {
      cur.look = { ...value };
      fxPatch.look = cur.look;
    } else {
      cur[sec] = { ...(cur[sec] || {}), [sub]: value };
      fxPatch[sec] = { ...(fxPatch[sec] || {}), [sub]: value };
    }
    clearTimeout(fxTimer);
    fxTimer = setTimeout(flushFx, 250);
  }
  emit("photo");
}

export function setPrefs(patch) {
  Object.assign(store.prefs, patch);
  Object.assign(prefsPatch, patch);
  clearTimeout(prefsTimer);
  prefsTimer = setTimeout(flushPrefs, 250);
  emit("prefs");
}

async function flushPrefs() {
  const patch = prefsPatch;
  prefsPatch = {};
  if (!Object.keys(patch).length) return;
  try {
    const got = await api.post("/api/settings", patch);
    delete got.message;
    store.prefs = { ...got, ...prefsPatch };
    emit("prefs");
  } catch (e) { fail(e); }
}

async function flushFx() {
  const patch = fxPatch;
  fxPatch = {};
  if (!Object.keys(patch).length) return;
  try {
    ingestFx(await api.post("/fxos/api/state", { current: patch }));
  } catch (e) { fail(e); }
}

export function exposureBody() {
  const L = photo().light;
  const body = { iso: L.iso, shutter: L.shutter, program: L.program, wb: store.prefs.wb || "Auto",
    quality: store.prefs.quality || "NEF+Fine" };
  if (!/^auto$/i.test(L.fstop) && /^(M|A)$/.test(L.program)) body.fstop = L.fstop;
  return body;
}

export const onlineRoles = () =>
  ["T", "R"].filter((r) => store.link?.roles?.[r]?.online);

function scheduleApply() {
  clearTimeout(applyTimer);
  applyTimer = setTimeout(applyExposure, 700);
}

// Push exposure to the bodies. With both off USB it is only saved; the
// link thread pushes saved settings when they come back.
export async function applyExposure() {
  clearTimeout(applyTimer);
  if (!onlineRoles().length || photo().light.follow_cam) return null;
  try {
    const j = await api.post("/api/set", exposureBody());
    if (j.link) ingestLink(j.link);
    emit("applied", j);
    return j;
  } catch (e) { fail(e); return null; }
}

export async function flushNow() {
  clearTimeout(prefsTimer);
  clearTimeout(fxTimer);
  await Promise.all([flushPrefs(), flushFx()]);
}

export function ingestFx(j) {
  if (!j) return;
  const keep = ["current", "modes", "looks", "shots", "active", "server"];
  keep.forEach((k) => { if (k in j) store.fx[k] = j[k]; });
  emit("fx");
}

export function ingestLink(j) {
  if (!j || !j.roles) return;
  store.link = j;
  emit("link");
}

export const activeMode = () => store.fx.modes.find((m) => m.id === store.fx.active) || null;

// --- labels -------------------------------------------------------------
export const isAuto = (v) => /^auto$/i.test(String(v || "").trim());
export const fmtF = (v) => (isAuto(v) ? "Auto" : "f/" + String(v).replace(/^f\/?/i, ""));
export const fmtIso = (v) => (isAuto(v) ? "ISO Auto" : "ISO " + v);
export const fmtShut = (v) => (isAuto(v) ? "Auto" : /^\d+(\.\d+)?$/.test(String(v)) ? v + "″" : v);
export const formatOf = (sq) =>
  FORMATS.reduce((a, b) => (Math.abs(b.sq - sq) < Math.abs(a.sq - sq) ? b : a), FORMATS[0]);
export const wbOf = (v) => WB.find((w) => w.v === v) || { v, label: v, k: 0 };
export const qualityOf = (v) => QUALITY.find((q) => q.v === v) || { v, label: v };
export const engineOf = (v) => ENGINES.find((e) => e.v === v) || { v, label: v };
export const guideOf = (v) => GUIDES.find((g) => g.v === v) || GUIDES[0];
export const signed = (n) => (n > 0 ? "+" + n : n < 0 ? "−" + Math.abs(n) : "0");

// D800 file sizes per body, so the room left follows the chosen format.
export const SET_MB = { "NEF+Fine": 58, "JPEG Fine": 18, "JPEG Normal": 9, "NEF (Raw)": 41 };
export const setMB = () => 2 * (SET_MB[store.prefs.quality] || 40);
export const setsLeft = () => (store.disk ? Math.floor(store.disk.free / (setMB() * 1e6)) : null);

export const driveLabel = (d) => (d.release === "sync" ? "GPIO" : "USB");
export function driveSub(d) {
  const bits = [d.save === "pi" ? "Pi + cards" : "Cards only"];
  if (d.timer) bits.push(d.timer + " s timer");
  if (d.auto_stitch && d.save === "pi") bits.push("auto-stitch");
  return bits.join(" · ");
}

export function lightLine(L) {
  if (L.follow_cam) return "Camera decides";
  return [fmtShut(L.shutter), fmtF(L.fstop), L.program].join(" · ");
}

// --- modes ---------------------------------------------------------------
export function modeFromPhoto(ph = photo()) {
  return {
    frame: { ...ph.frame },
    light: { ...ph.light },
    focus: { ...ph.focus },
    look: { ...ph.look },
    drive: { ...ph.drive },
    wb: ph.wb,
  };
}

const LABELS = {
  "frame.squeeze": "Format", "frame.guide": "Guide", "frame.clip": "Edges",
  "light.program": "Mode", "light.iso": "ISO", "light.shutter": "Shutter", "light.fstop": "Aperture",
  "light.master": "Metering body", "light.lock_t": "Lock at fire", "light.sync": "Copy to slave",
  "light.follow_cam": "Camera decides",
  "focus.aid": "Focus aid", "focus.color": "Peaking colour", "focus.level": "Peaking level",
  "look.base": "Look", "look.color": "Color", "look.highlight": "Highlight", "look.shadow": "Shadow",
  "look.grain": "Grain", "look.filter": "Filter",
  "drive.release": "Release", "drive.save": "Save", "drive.quality": "File", "drive.timer": "Timer",
  "drive.review": "Review", "drive.auto_stitch": "Auto-stitch", "drive.engine": "Stitch engine",
  "wb": "White balance",
};

const same = (a, b) => {
  if (typeof a === "number" || typeof b === "number") return Math.abs(num(a, 0) - num(b, 0)) < 0.01;
  return String(a ?? "") === String(b ?? "");
};

export function describe(key, v) {
  if (key === "frame.squeeze") return formatOf(num(v, 1)).label;
  if (key === "frame.guide") return guideOf(v).label;
  if (key === "light.iso") return isAuto(v) ? "Auto" : v;
  if (key === "light.fstop") return fmtF(v);
  if (key === "light.shutter") return fmtShut(v);
  if (key === "wb") return wbOf(v).label;
  if (key === "drive.release") return v === "sync" ? "GPIO" : "USB";
  if (key === "drive.quality") return qualityOf(v).label;
  if (key === "drive.engine") return engineOf(v).label;
  if (key === "drive.timer" || key === "drive.review") return num(v, 0) ? v + " s" : "Off";
  if (key === "look.base") return v ? v[0].toUpperCase() + v.slice(1) : "";
  if (["look.color", "look.highlight", "look.shadow"].includes(key)) return signed(num(v, 0));
  if (typeof v === "boolean") return v ? "On" : "Off";
  return String(v ?? "");
}

// What differs between the live state and a saved mode.
export function diff(mode, ph = photo()) {
  if (!mode) return [];
  const out = [];
  const now = modeFromPhoto(ph);
  for (const sec of ["frame", "light", "focus", "look", "drive"]) {
    const a = mode[sec] || {};
    const b = now[sec] || {};
    for (const k of Object.keys(LABELS).filter((x) => x.startsWith(sec + ".")).map((x) => x.split(".")[1])) {
      if (!(k in a)) continue;
      if (!same(a[k], b[k])) {
        const key = sec + "." + k;
        out.push({ key, label: LABELS[key], from: describe(key, a[k]), to: describe(key, b[k]) });
      }
    }
  }
  if ("wb" in mode && !same(mode.wb, now.wb))
    out.push({ key: "wb", label: LABELS.wb, from: describe("wb", mode.wb), to: describe("wb", now.wb) });
  return out;
}

// Write a whole mode back to the rig and the fxos store.
export async function recall(mode) {
  const f = mode.frame || {};
  const L = mode.light || {};
  const d = mode.drive || {};
  const patch = {};
  if ("squeeze" in f) patch.ana_squeeze = f.squeeze;
  if ("clip" in f) patch.crop_inner = !!f.clip;
  for (const k of ["program", "iso", "shutter", "fstop", "master"]) if (k in L) patch[k] = L[k];
  for (const k of ["lock_t", "sync", "follow_cam"]) if (k in L) patch[k] = !!L[k];
  if ("release" in d) patch.gpio = d.release === "sync";
  if ("save" in d) patch.download = d.save === "pi";
  if ("quality" in d) patch.quality = d.quality;
  if ("review" in d) patch.preview_s = d.review;
  if ("engine" in d) patch.stitch_mode = d.engine;
  if ("wb" in mode) patch.wb = mode.wb;
  clearTimeout(prefsTimer);
  prefsPatch = {};
  const got = await api.post("/api/settings", patch);
  delete got.message;
  store.prefs = got;
  const current = {};
  if ("guide" in f) current.frame = { guide: f.guide };
  if (mode.focus) current.focus = { ...mode.focus };
  if (mode.look) current.look = { ...mode.look };
  current.drive = {};
  if ("timer" in d) current.drive.timer = d.timer;
  if ("auto_stitch" in d) current.drive.auto_stitch = !!d.auto_stitch;
  clearTimeout(fxTimer);
  fxPatch = {};
  ingestFx(await api.post("/fxos/api/state", { current, active: mode.id }));
  emit("photo");
  return applyExposure();
}
