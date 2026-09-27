// Live view: pull T and R, stitch them the way LIVE PREVIEW always has
// (R flopped on the left, T feathered in across the overlap), and measure
// what the photographer needs to see: exposure, T/R balance, sharpness.
import { store } from "./model.js";

const PULL_MS = 125;

export const live = {
  pulling: false,
  stills: false,
  frames: { T: null, R: null },
  comp: document.createElement("canvas"),
  seq: 0,
  lastAt: 0,
  stats: {
    hist: { T: null, R: null },
    clip: { T: [0, 0], R: [0, 0] },
    dEv: null,
    sharp: { T: 0, R: 0 },
  },
};

const subs = new Set();
export const onFrame = (fn) => { subs.add(fn); return () => subs.delete(fn); };
const notify = () => subs.forEach((fn) => { try { fn(live); } catch (e) { console.error(e); } });

const canvas = (w = 1, h = 1) => Object.assign(document.createElement("canvas"), { width: w, height: h });
const tmpT = canvas();
const work = canvas(128, 86);
const workCtx = work.getContext("2d", { willReadFrequently: true });
const sharpC = canvas(192, 128);
const sharpCtx = sharpC.getContext("2d", { willReadFrequently: true });
const peakSrc = canvas();
const peakSrcCtx = peakSrc.getContext("2d", { willReadFrequently: true });

let timer = 0;
let inflight = false;

async function grab(role) {
  const r = await fetch(`/api/live/${role}.jpg?n=${Date.now()}`, { cache: "no-store" });
  if (r.status !== 200) return null;
  return createImageBitmap(await r.blob());
}

async function tick() {
  if (!live.pulling) return;
  if (!inflight) {
    inflight = true;
    try {
      const [t, r] = await Promise.all([grab("T").catch(() => null), grab("R").catch(() => null)]);
      if (live.pulling && (t || r)) {
        setFrames(t, r, false);
        live.lastAt = performance.now();
      }
    } finally {
      inflight = false;
    }
  }
  timer = setTimeout(tick, PULL_MS);
}

export function startPull() {
  if (live.pulling) return;
  live.pulling = true;
  live.stills = false;
  tick();
}

export function stopPull() {
  live.pulling = false;
  clearTimeout(timer);
}

export const fresh = () => live.pulling && performance.now() - live.lastAt < 1500;

function swap(role, next) {
  const old = live.frames[role];
  if (old && old !== next && old.close) old.close();
  live.frames[role] = next;
}

export function setFrames(t, r, stills) {
  swap("T", t);
  swap("R", r);
  live.stills = !!stills;
  composite();
  live.seq += 1;
  if (live.seq % 2 === 0 || stills) analyze();
  notify();
}

export function clearFrames() {
  swap("T", null);
  swap("R", null);
  live.comp.width = 1;
  live.comp.height = 1;
  live.seq += 1;
  notify();
}

export const overlapFrac = () => Math.min(0.5, Math.max(0.05, Number(store.prefs.overlap) || 0.2));
export const flipR = () => !!store.prefs.flip_r;

export function composite() {
  compose(live.comp, live.frames.T, live.frames.R);
}

// R flopped on the left, T feathered in across the overlap, into `c`.
export function compose(c, t, r, flip = flipR(), ol = overlapFrac()) {
  const ctx = c.getContext("2d");
  if (!t && !r) { c.width = 1; c.height = 1; return; }
  if (!t || !r) {
    const one = t || r;
    c.width = one.width;
    c.height = one.height;
    ctx.save();
    if (one === r && flip) { ctx.translate(one.width, 0); ctx.scale(-1, 1); }
    ctx.drawImage(one, 0, 0);
    ctx.restore();
    return;
  }
  const h = Math.min(t.height, r.height);
  const tw = Math.round(t.width * h / t.height);
  const rw = Math.round(r.width * h / r.height);
  const olPx = Math.max(8, Math.round(rw * ol));
  const seam = rw - olPx;
  if (c.width !== seam + tw || c.height !== h) { c.width = seam + tw; c.height = h; }
  ctx.clearRect(0, 0, c.width, h);
  ctx.save();
  if (flip) { ctx.translate(rw, 0); ctx.scale(-1, 1); }
  ctx.drawImage(r, 0, 0, rw, h);
  ctx.restore();
  if (tmpT.width !== tw || tmpT.height !== h) { tmpT.width = tw; tmpT.height = h; }
  const tx = tmpT.getContext("2d");
  tx.globalCompositeOperation = "source-over";
  tx.clearRect(0, 0, tw, h);
  tx.drawImage(t, 0, 0, tw, h);
  const fade = tx.createLinearGradient(0, 0, olPx, 0);
  fade.addColorStop(0, "rgba(0,0,0,0)");
  fade.addColorStop(0.55, "rgba(0,0,0,1)");
  fade.addColorStop(1, "rgba(0,0,0,1)");
  tx.globalCompositeOperation = "destination-in";
  tx.fillStyle = fade;
  tx.fillRect(0, 0, tw, h);
  ctx.drawImage(tmpT, seam, 0);
}

// Copy the stitched preview into a view, desqueezed.
export function drawTo(target, squeeze = 1) {
  const src = live.comp;
  if (src.width < 2) return false;
  const w = Math.round(src.width * squeeze);
  if (target.width !== w || target.height !== src.height) { target.width = w; target.height = src.height; }
  target.getContext("2d").drawImage(src, 0, 0, w, src.height);
  return true;
}

// One body's raw frame, optionally flopped so R reads the right way round.
export function drawRole(target, role, { flop = false, zoom = 1 } = {}) {
  const f = live.frames[role];
  if (!f) return false;
  if (target.width !== f.width || target.height !== f.height) { target.width = f.width; target.height = f.height; }
  const ctx = target.getContext("2d");
  ctx.save();
  if (flop) { ctx.translate(f.width, 0); ctx.scale(-1, 1); }
  if (zoom > 1) {
    const sw = f.width / zoom;
    const sh = f.height / zoom;
    ctx.drawImage(f, (f.width - sw) / 2, (f.height - sh) / 2, sw, sh, 0, 0, f.width, f.height);
  } else {
    ctx.drawImage(f, 0, 0);
  }
  ctx.restore();
  return true;
}

const lin = new Float32Array(256).map((_, i) => Math.pow(i / 255, 2.2));

function analyze() {
  const s = live.stats;
  const ol = overlapFrac();
  const strip = {};
  for (const role of ["T", "R"]) {
    const f = live.frames[role];
    if (!f) { s.hist[role] = null; s.sharp[role] = 0; continue; }
    workCtx.drawImage(f, 0, 0, work.width, work.height);
    const px = workCtx.getImageData(0, 0, work.width, work.height).data;
    const hist = new Uint32Array(64);
    let lo = 0, hi = 0, sum = 0, n = 0;
    const band = Math.max(2, Math.round(work.width * ol));
    // Overlap strip in raw pixels: T's left edge; R's inner edge, which is
    // its left edge when the leg is mirrored and its right edge when not.
    const sx0 = role === "T" ? 0 : flipR() ? 0 : work.width - band;
    const sx1 = sx0 + band;
    for (let i = 0, p = 0; i < px.length; i += 4, p += 1) {
      const y = (px[i] * 54 + px[i + 1] * 183 + px[i + 2] * 19) >> 8;
      hist[y >> 2] += 1;
      if (y <= 2) lo += 1;
      if (y >= 253) hi += 1;
      const x = p % work.width;
      if (x >= sx0 && x < sx1) { sum += lin[y]; n += 1; }
    }
    const total = px.length / 4;
    s.hist[role] = hist;
    s.clip[role] = [lo / total, hi / total];
    strip[role] = n ? sum / n : 0;
    s.sharp[role] = s.sharp[role] * 0.6 + sharpness(f, sx0 / work.width, sx1 / work.width) * 0.4;
  }
  s.dEv = strip.T > 0.002 && strip.R > 0.002 ? Math.log2(strip.T / strip.R) : null;
}

function sobel(px, w, h, out) {
  const g = new Float32Array(w * h);
  for (let i = 0, p = 0; i < px.length; i += 4, p += 1) g[p] = px[i] * 0.3 + px[i + 1] * 0.59 + px[i + 2] * 0.11;
  for (let y = 1; y < h - 1; y += 1) {
    for (let x = 1; x < w - 1; x += 1) {
      const i = y * w + x;
      const gx = -g[i - w - 1] - 2 * g[i - 1] - g[i + w - 1] + g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1];
      const gy = -g[i - w - 1] - 2 * g[i - w] - g[i - w + 1] + g[i + w - 1] + 2 * g[i + w] + g[i + w + 1];
      out[i] = Math.abs(gx) + Math.abs(gy);
    }
  }
  return out;
}

// Measured in the overlap, the one strip both bodies see, so T and R are
// compared on the same subject.
function sharpness(f, fx0, fx1) {
  const w = sharpC.width;
  const h = sharpC.height;
  sharpCtx.drawImage(f, 0, 0, w, h);
  const mag = sobel(sharpCtx.getImageData(0, 0, w, h).data, w, h, new Float32Array(w * h));
  const x0 = Math.max(1, Math.round(fx0 * w));
  const x1 = Math.min(w - 1, Math.round(fx1 * w));
  let sum = 0, n = 0;
  for (let y = Math.round(h * 0.1); y < h * 0.9; y += 1) {
    for (let x = x0; x < x1; x += 1) { sum += mag[y * w + x]; n += 1; }
  }
  return Math.min(100, (sum / Math.max(1, n)) * 1.1);
}

const RGB = { red: [255, 59, 48], yellow: [255, 214, 10], white: [255, 255, 255], blue: [64, 160, 255] };
const KEEP = { low: 0.015, std: 0.03, high: 0.06 };

// Focus peaking: the strongest edges of `src`, painted into `out` at
// `width` px, transparent elsewhere. Stretch `out` over the view.
export function peaking(src, out, { color = "red", level = "std", width = 480 } = {}) {
  if (!src || !src.width || src.width < 2) return false;
  const w = Math.min(width, src.width);
  const h = Math.max(2, Math.round(src.height * w / src.width));
  if (peakSrc.width !== w || peakSrc.height !== h) { peakSrc.width = w; peakSrc.height = h; }
  peakSrcCtx.drawImage(src, 0, 0, w, h);
  const mag = sobel(peakSrcCtx.getImageData(0, 0, w, h).data, w, h, new Float32Array(w * h));
  const bins = new Uint32Array(256);
  for (let i = 0; i < mag.length; i += 1) bins[Math.min(255, mag[i] >> 2)] += 1;
  let want = mag.length * (KEEP[level] || KEEP.std);
  let cut = 255;
  for (; cut > 0 && want > 0; cut -= 1) want -= bins[cut];
  const thr = Math.max(24, cut << 2);
  if (out.width !== w || out.height !== h) { out.width = w; out.height = h; }
  const octx = out.getContext("2d");
  const img = octx.createImageData(w, h);
  const [r, g, b] = RGB[color] || RGB.red;
  // Only ridge pixels, so edges read as contour lines, not blobs.
  for (let y = 1; y < h - 1; y += 1) {
    for (let x = 1; x < w - 1; x += 1) {
      const i = y * w + x;
      const m = mag[i];
      if (m < thr) continue;
      const ridgeX = m >= mag[i - 1] && m >= mag[i + 1];
      const ridgeY = m >= mag[i - w] && m >= mag[i + w];
      if (!ridgeX && !ridgeY) continue;
      const k = i * 4;
      img.data[k] = r; img.data[k + 1] = g; img.data[k + 2] = b; img.data[k + 3] = 235;
    }
  }
  octx.putImageData(img, 0, 0);
  return true;
}

// Stills stand in for live view when it is off: the last pair, stitched
// the same way, so the home screen always shows a picture.
export async function bitmap(name, width) {
  const r = await fetch("/api/file/" + encodeURIComponent(name) + (width ? "?w=" + width : ""));
  if (!r.ok) throw new Error("missing " + name);
  return createImageBitmap(await r.blob());
}

export async function loadStills(pair, width = 960) {
  if (!pair || !pair.t || !pair.r) return false;
  try {
    const [t, r] = await Promise.all([bitmap(pair.t, width), bitmap(pair.r, width)]);
    if (live.pulling) { t.close(); r.close(); return false; }
    setFrames(t, r, true);
    return true;
  } catch {
    return false;
  }
}
