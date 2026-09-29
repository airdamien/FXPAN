// Panels shared by the screens: the stitched preview, the T/R histogram,
// and a single body for focus.
import { live, onFrame, drawTo, drawRole, peaking, flipR, overlapFrac } from "./live.js";
import { photo, guideOf, store } from "./model.js";
import { ensureFilter } from "./look.js";
import { h } from "./ui.js";
import * as api from "./api.js";

// The picture being made: T and R stitched, desqueezed to the chosen
// format, the frame guide over it, optionally graded and peaked.
export function panoView({ look = false, guide = true, peak = false, filterId = "fx-look", files = false } = {}) {
  const el = h("div", { class: "pano" });
  const stage = h("div", { class: "pano-stage" });
  const cv = h("canvas", { class: "pano-cv" });
  const img = h("img", { class: "pano-img", alt: "", hidden: true });
  const peakCv = h("canvas", { class: "pano-peak", hidden: true });
  const guideEl = h("div", { class: "guide", hidden: true }, h("span"));
  const badge = h("div", { class: "pano-badge" });
  const empty = h("div", { class: "pano-empty", hidden: true });
  stage.append(cv, img, peakCv, guideEl);
  el.append(stage, badge, empty);
  let off = null;
  let aspect = 2.7;
  let fileName = "";
  let peakTick = 0;
  const opts = { look, guide, peak };

  const layout = () => {
    const W = el.clientWidth;
    const H = el.clientHeight;
    if (!W || !H) return;
    let w = W;
    let h2 = W / aspect;
    if (h2 > H) { h2 = H; w = H * aspect; }
    stage.style.width = Math.round(w) + "px";
    stage.style.height = Math.round(h2) + "px";
    const g = guideOf(photo().frame.guide);
    guideEl.hidden = live.capturing || !opts.guide || !g.r;
    if (g.r) {
      let gw = w;
      let gh = w / g.r;
      if (gh > h2) { gh = h2; gw = h2 * g.r; }
      Object.assign(guideEl.style, {
        width: gw + "px", height: gh + "px",
        left: (w - gw) / 2 + "px", top: (h2 - gh) / 2 + "px",
      });
      guideEl.firstChild.textContent = g.label;
    }
  };
  new ResizeObserver(layout).observe(el);

  const showFile = (name) => {
    fileName = name;
    img.hidden = false;
    cv.hidden = true;
    peakCv.hidden = true;
    cv.style.filter = "none";
    img.onload = () => {
      aspect = img.naturalWidth / img.naturalHeight;
      layout();
    };
    img.src = api.file(name, 1600);
  };

  const draw = () => {
    const ph = photo();
    const sq = ph.frame.squeeze;
    if (live.capturing) {
      img.hidden = true;
      cv.hidden = true;
      peakCv.hidden = true;
      guideEl.hidden = true;
      fileName = "";
      badge.textContent = "Downloading";
      badge.className = "pano-badge";
      empty.hidden = false;
      empty.textContent = "Downloading";
      return;
    }
    const fromLive = live.pulling;
    const lastPano = files && !fromLive ? latestPano() : "";
    if (lastPano) {
      if (fileName !== lastPano || img.hidden) showFile(lastPano);
      badge.textContent = "Last shot";
      badge.className = "pano-badge";
      empty.hidden = true;
      return;
    }
    img.hidden = true;
    fileName = "";
    cv.hidden = false;
    const ok = drawTo(cv, sq);
    empty.hidden = ok;
    if (!ok) {
      empty.textContent = store.link && !store.link.roles?.T?.online && !store.link.roles?.R?.online
        ? "No bodies on USB" : "Live view off";
      badge.textContent = "";
      return;
    }
    const a = cv.width / cv.height;
    if (Math.abs(a - aspect) > 0.01) { aspect = a; layout(); }
    cv.style.filter = opts.look ? ensureFilter(filterId, ph.look) : "none";
    if (live.stills) {
      badge.textContent = "Last shot · preview";
      badge.className = "pano-badge";
    } else {
      badge.textContent = "Live";
      badge.className = "pano-badge live";
    }
    const wantPeak = opts.peak && ph.focus.aid === "peaking";
    peakCv.hidden = !wantPeak;
    if (wantPeak && (peakTick++ % 2 === 0 || live.stills)) {
      peaking(live.comp, peakCv, { color: ph.focus.color, level: ph.focus.level, width: 760 });
    }
  };

  el.start = () => { if (!off) off = onFrame(draw); draw(); layout(); };
  el.stop = () => { if (off) off(); off = null; };
  el.update = () => { draw(); layout(); };
  el.set = (patch) => { Object.assign(opts, patch); el.update(); };
  return el;
}

export function latestPano() {
  const p = (store.pairs || []).find((x) => x.pano || x.ready);
  return p && p.pano ? p.pano : "";
}

// Both bodies' histograms on one axis. Where they differ, the bodies
// disagree about exposure.
export function histView() {
  const el = h("div", { class: "hist" });
  const cv = h("canvas", { class: "hist-cv", width: 512, height: 160 });
  el.append(cv);
  let off = null;
  const draw = () => {
    const ctx = cv.getContext("2d");
    const W = cv.width;
    const H = cv.height;
    ctx.clearRect(0, 0, W, H);
    ctx.strokeStyle = "rgba(255,255,255,0.08)";
    ctx.lineWidth = 1;
    for (let i = 1; i < 4; i += 1) {
      ctx.beginPath();
      ctx.moveTo((W * i) / 4 + 0.5, 0);
      ctx.lineTo((W * i) / 4 + 0.5, H);
      ctx.stroke();
    }
    const hs = live.stats.hist;
    let peak = 1;
    for (const role of ["T", "R"]) {
      const hist = hs[role];
      if (hist) for (let i = 1; i < hist.length - 1; i += 1) peak = Math.max(peak, hist[i]);
    }
    ctx.globalCompositeOperation = "screen";
    for (const [role, color] of [["R", "208,105,44"], ["T", "154,92,255"]]) {
      const hist = hs[role];
      if (!hist) continue;
      ctx.beginPath();
      ctx.moveTo(0, H);
      for (let i = 0; i < hist.length; i += 1) {
        const x = (i / (hist.length - 1)) * W;
        const y = H - Math.min(1, hist[i] / peak) * (H - 6);
        ctx.lineTo(x, y);
      }
      ctx.lineTo(W, H);
      ctx.closePath();
      ctx.fillStyle = `rgba(${color},0.55)`;
      ctx.fill();
      ctx.strokeStyle = `rgba(${color},0.95)`;
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }
    ctx.globalCompositeOperation = "source-over";
  };
  el.start = () => { if (!off) off = onFrame(draw); draw(); };
  el.stop = () => { if (off) off(); off = null; };
  el.update = draw;
  return el;
}

// The overlap strip from both bodies, side by side and enlarged: the only
// subject they share, so focus can be compared like for like.
export function overlapCheck() {
  const cv = h("canvas", { class: "olcheck-cv" });
  const peakCv = h("canvas", { class: "olcheck-peak" });
  const el = h("div", { class: "olcheck" },
    h("div", { class: "olcheck-stage" }, cv, peakCv,
      h("b", { class: "olcheck-tag r", text: "R" }), h("b", { class: "olcheck-tag t", text: "T" })));
  let off = null;
  let tick = 0;
  const draw = () => {
    const { T: t, R: r } = live.frames;
    el.classList.toggle("none", !t || !r);
    if (!t || !r) return;
    const ol = overlapFrac();
    const rw = r.width * ol;
    const tw = t.width * ol;
    const rh = r.height * 0.34;
    const th = t.height * 0.34;
    const W = 480;
    const H = Math.round((W / 2) * (rh / rw));
    if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; }
    const ctx = cv.getContext("2d");
    const rx = flipR() ? 0 : r.width - rw;
    ctx.save();
    if (flipR()) { ctx.translate(W / 2, 0); ctx.scale(-1, 1); }
    ctx.drawImage(r, rx, r.height * 0.33, rw, rh, 0, 0, W / 2, H);
    ctx.restore();
    ctx.drawImage(t, 0, t.height * 0.33, tw, th, W / 2, 0, W / 2, H);
    const ph = photo();
    peakCv.hidden = ph.focus.aid === "off";
    if (!peakCv.hidden && tick++ % 2 === 0) peaking(cv, peakCv, { color: ph.focus.color, level: ph.focus.level, width: W });
  };
  el.start = () => { if (!off) off = onFrame(draw); draw(); };
  el.stop = () => { if (off) off(); off = null; };
  el.update = draw;
  return el;
}

// One body, the way it reads through its own leg, with peaking and a
// sharpness bar so the two helicoids can be matched.
export function roleView(role) {
  const el = h("div", { class: "rolev " + role.toLowerCase() });
  const stage = h("div", { class: "rolev-stage" });
  const cv = h("canvas", { class: "rolev-cv" });
  const peakCv = h("canvas", { class: "rolev-peak" });
  stage.append(cv, peakCv);
  const tag = h("b", { class: "rolev-tag", text: role });
  const bar = h("div", { class: "meter" }, h("i"));
  const score = h("span", { class: "meter-n", text: "—" });
  el.append(stage, tag, h("div", { class: "rolev-foot" }, h("span", { text: role === "T" ? "Transmit" : "Reflect" }), bar, score));
  let off = null;
  let tick = 0;
  const draw = () => {
    const ph = photo();
    const zoom = ph.focus.aid === "loupe" ? 2 : 1;
    const ok = drawRole(cv, role, { flop: role === "R" && flipR(), zoom });
    stage.classList.toggle("none", !ok);
    const s = Math.round(live.stats.sharp[role] || 0);
    const other = Math.round(live.stats.sharp[role === "T" ? "R" : "T"] || 0);
    const top = Math.max(s, other, 1);
    bar.firstChild.style.width = (ok ? Math.round((100 * s) / top) : 0) + "%";
    bar.classList.toggle("best", ok && s >= other);
    score.textContent = ok ? String(s) : "—";
    const wantPeak = ph.focus.aid !== "off";
    peakCv.hidden = !wantPeak || !ok;
    if (wantPeak && ok && (tick++ % 2 === 0 || live.stills)) {
      peaking(cv, peakCv, { color: ph.focus.color, level: ph.focus.level, width: 420 });
    }
  };
  el.start = () => { if (!off) off = onFrame(draw); draw(); };
  el.stop = () => { if (off) off(); off = null; };
  el.update = draw;
  return el;
}
