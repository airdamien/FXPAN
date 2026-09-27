// Level 2 and 3: one screen per photographic dimension, all built from the
// same rows, each with the picture or the measurement that choice changes.
import { h, rowList, chips, cards, ruler, toggle, stepIn, ask, toast } from "./ui.js";
import { icon } from "./icons.js";
import { go } from "./nav.js";
import { dim, fact } from "./kit.js";
import { panoView, histView, roleView, overlapCheck } from "./views.js";
import { live, onFrame, drawTo } from "./live.js";
import * as M from "./model.js";
import * as api from "./api.js";
import { LOOKS, FILTERS, GRAINS, STEPS, lookName, tweaks, baseOf, isMono, ensureFilter } from "./look.js";

const L = () => M.photo().light;

function watch(views) {
  return {
    enter() { views.forEach((v) => v.start()); },
    leave() { views.forEach((v) => v.stop()); },
  };
}

// --- FRAME ---------------------------------------------------------------------
const PX = { 1: "13248 × 4912", 1.33: "17620 × 4912", 1.5: "19872 × 4912", 2: "26496 × 4912" };

function stitchDiagram() {
  // Two 3:2 frames, 20% overlap: the 2.71:1 strip the name is about.
  return h("div", { class: "diagram", html: `
    <svg viewBox="0 0 280 72" aria-hidden="true">
      <rect x="6" y="8" width="84" height="56" rx="3" class="d-r"/>
      <rect x="73.2" y="8" width="84" height="56" rx="3" class="d-t"/>
      <rect x="73.2" y="8" width="16.8" height="56" class="d-ol"/>
      <text x="48" y="41" class="d-lab r">R</text><text x="116" y="41" class="d-lab t">T</text>
      <path d="M172 36h22m-6-5 6 5-6 5" class="d-arrow"/>
      <rect x="204" y="21" width="70.4" height="26" rx="2" class="d-p"/>
      <text x="239" y="38" class="d-lab p">2.71:1</text>
    </svg>
    <span>Two D800 frames, 20% overlap, one 65:24 strip</span>` });
}

export function frameScreen() {
  const s = dim({ id: "frame", title: "Frame", ic: "frame" });
  const view = panoView({ look: true, guide: true });
  const px = fact("Output");
  const how = fact("Guide");
  const rows = rowList([
    { id: "format", label: "Format", value: () => M.formatOf(M.photo().frame.squeeze).label,
      control: () => cards({
        options: M.FORMATS.map((f) => ({ v: String(f.sq), label: f.label, name: f.name, sub: f.sub })),
        get: () => String(M.formatOf(M.photo().frame.squeeze).sq),
        set: (v) => M.set("frame.squeeze", Number(v)),
      }) },
    { id: "guide", label: "Guide", hint: "Frame lines to compose inside",
      value: () => M.guideOf(M.photo().frame.guide).label,
      control: () => chips({ options: M.GUIDES, get: () => M.photo().frame.guide, set: (v) => M.set("frame.guide", v) }) },
    { id: "clip", label: "Edges", more: true, hint: "After alignment",
      value: () => (M.photo().frame.clip ? "Clip to aligned" : "Full canvas"),
      control: () => chips({ options: [{ v: "1", label: "Clip to aligned" }, { v: "0", label: "Full canvas" }],
        get: () => (M.photo().frame.clip ? "1" : "0"), set: (v) => M.set("frame.clip", v === "1") }) },
  ], { open: "format" });
  s.list.append(rows);
  s.panel.append(h("div", { class: "panel-view" }, view), h("div", { class: "facts" }, px, how), stitchDiagram());
  const paint = () => {
    const ph = M.photo();
    const f = M.formatOf(ph.frame.squeeze);
    px.set(`${PX[f.sq] || ""} px${ph.frame.clip ? " (less the aligned edges)" : ""}`);
    const g = M.guideOf(ph.frame.guide);
    how.set(g.r ? `${g.label} lines on the preview — the file keeps the full ${f.label}` : "None");
    rows.refresh();
    view.update();
  };
  const w = watch([view]);
  return { el: s.el, enter() { w.enter(); paint(); }, leave: w.leave, refresh: paint, dial: (d) => rows.dial(d) };
}

// --- LIGHT ---------------------------------------------------------------------
function bodyLine(role) {
  const b = M.store.link?.status?.[role];
  if (!b) return M.store.link?.roles?.[role]?.online ? "on USB" : "off USB";
  return [b.expprogram, M.fmtIso(b.iso), M.fmtShut(b.shutterspeed), b["f-number"], b.batterylevel]
    .filter(Boolean).join(" · ");
}

export function lightScreen() {
  const s = dim({ id: "light", title: "Light", ic: "light" });
  const hist = histView();
  const bal = fact("T / R balance");
  const clip = fact("Clipped");
  const tLine = fact("T");
  const rLine = fact("R");
  tLine.classList.add("t");
  rLine.classList.add("r");
  const decides = () => L().follow_cam;
  const rows = rowList([
    { id: "program", label: "Mode", value: () => { const p = M.PROGRAMS.find((x) => x.v === L().program); return p ? `${p.label} · ${p.sub}` : L().program; },
      control: () => chips({ options: M.PROGRAMS, get: () => L().program, set: (v) => M.set("light.program", v) }),
      dial: (d) => M.set("light.program", stepIn(M.PROGRAMS.map((p) => p.v), L().program, d)) },
    { id: "iso", label: "ISO", hint: () => (decides() ? "Camera decides" : "Both bodies"),
      value: () => (M.isAuto(L().iso) ? "Auto" : L().iso),
      control: () => ruler({ values: M.ISO, get: () => L().iso, set: (v) => M.set("light.iso", v) }) },
    { id: "shutter", label: "Shutter",
      hint: () => (/^(A|P)$/.test(L().program) ? "Camera sets it in " + L().program : "Both bodies"),
      value: () => M.fmtShut(L().shutter),
      control: () => ruler({ values: M.SHUT, get: () => L().shutter, set: (v) => M.set("light.shutter", v), format: M.fmtShut }) },
    { id: "fstop", label: "Aperture", hint: "Taking-lens iris",
      value: () => M.fmtF(L().fstop),
      control: () => ruler({ values: M.FSTOP, get: () => L().fstop, set: (v) => M.set("light.fstop", v),
        format: (v) => (M.isAuto(v) ? "Auto" : v) }) },
    { id: "dual", label: "Dual body", icon: "sync",
      value: () => (L().follow_cam ? "Camera decides" : `Meter ${L().master}${L().lock_t ? " · lock at fire" : ""}`),
      go: () => go("light-dual") },
  ], { open: "iso" });
  s.list.append(rows);
  s.panel.append(
    h("div", { class: "panel-title", html: `<span>Histogram</span><span class="legend"><i class="t"></i>T <i class="r"></i>R</span>` }),
    hist,
    h("div", { class: "facts" }, bal, clip, tLine, rLine));
  const paint = () => {
    rows.refresh();
    tLine.set(bodyLine("T"));
    rLine.set(bodyLine("R"));
  };
  let tick = 0;
  const onStats = () => {
    if (tick++ % 3) return;
    const st = live.stats;
    if (st.dEv == null) bal.set("—", "");
    else if (Math.abs(st.dEv) < 0.15) bal.set("Matched across the overlap", "ok");
    else bal.set(`${st.dEv > 0 ? "T" : "R"} ${Math.abs(st.dEv).toFixed(1)} EV brighter`, "warn");
    const c = st.clip;
    const hi = Math.max(c.T[1], c.R[1]) * 100;
    const lo = Math.max(c.T[0], c.R[0]) * 100;
    clip.set(`Highlights ${hi.toFixed(1)}% · Shadows ${lo.toFixed(1)}%`, hi > 2 ? "warn" : "");
  };
  let off = null;
  return {
    el: s.el,
    enter() { hist.start(); off = onFrame(onStats); onStats(); paint(); },
    leave() { hist.stop(); if (off) off(); },
    refresh: paint,
    dial: (d) => rows.dial(d),
  };
}

export function bodyCard(role) {
  const el = h("div", { class: "body-card " + role.toLowerCase() });
  el.paint = () => {
    const b = M.store.link?.status?.[role];
    const on = !!M.store.link?.roles?.[role]?.online;
    el.classList.toggle("off", !on);
    const other = M.store.link?.status?.[role === "T" ? "R" : "T"];
    const cell = (k, label, v) => {
      const differs = b && other && String(other[k] ?? "") !== String(b[k] ?? "");
      return `<div class="bc-cell${differs ? " differs" : ""}"><span>${label}</span><b>${v ?? "—"}</b></div>`;
    };
    el.innerHTML = `<div class="bc-head"><b>${role}</b><span>${role === "T" ? "Transmit" : "Reflect"}</span>`
      + `<em>${on ? (b?.batterylevel || "") : "off USB"}</em></div>`
      + (b ? cell("expprogram", "Mode", b.expprogram) + cell("iso", "ISO", b.iso)
        + cell("shutterspeed", "Shutter", b.shutterspeed) + cell("f-number", "f", b["f-number"])
        + cell("whitebalance", "WB", M.wbOf(b.whitebalance).label) + cell("imagequality", "File", M.qualityOf(b.imagequality).label)
        : `<p class="bc-none">${on ? "No status yet" : "Plug in and wake the body"}</p>`);
  };
  return el;
}

export function lightDualScreen() {
  const s = dim({ id: "light-dual", title: "Dual body", ic: "sync", crumb: "Light" });
  const tCard = bodyCard("T");
  const rCard = bodyCard("R");
  const rows = rowList([
    { id: "master", label: "Meter from", hint: "The body whose exposure leads",
      value: () => L().master,
      control: () => chips({ options: [{ v: "T", label: "T", sub: "Transmit" }, { v: "R", label: "R", sub: "Reflect" }],
        get: () => L().master, set: (v) => M.set("light.master", v) }) },
    { id: "lock", label: "Lock at fire", hint: "Freeze the leader's numbers on both",
      value: () => (L().lock_t ? "On" : "Off"),
      control: () => toggle({ get: () => L().lock_t, set: (v) => M.set("light.lock_t", v) }) },
    { id: "sync", label: "Copy to other body", hint: "Mirror settings, not flash",
      value: () => (L().sync ? "On" : "Off"),
      control: () => toggle({ get: () => L().sync, set: (v) => M.set("light.sync", v) }) },
    { id: "follow", label: "Camera decides", hint: "Live AE: the bodies choose, this watches",
      value: () => (L().follow_cam ? "On" : "Off"),
      control: () => toggle({ get: () => L().follow_cam, set: (v) => M.set("light.follow_cam", v) }) },
  ], { open: "master" });
  s.list.append(rows);
  s.panel.append(h("div", { class: "panel-title", html: "<span>What each body reports</span>" }),
    h("div", { class: "body-cards" }, rCard, tCard),
    h("p", { class: "panel-note", text: "Cells that disagree between the bodies are marked. Lock at fire copies the leader's metered numbers to both before the release, so the halves always match." }));
  const paint = () => { rows.refresh(); tCard.paint(); rCard.paint(); };
  return { el: s.el, enter: paint, refresh: paint, dial: (d) => rows.dial(d) };
}

// --- FOCUS ---------------------------------------------------------------------
export function focusScreen() {
  const s = dim({ id: "focus", title: "Focus", ic: "focus" });
  const rv = roleView("R");
  const tv = roleView("T");
  const ol = overlapCheck();
  const match = fact("Match in the overlap");
  const F = () => M.photo().focus;
  const rows = rowList([
    { id: "aid", label: "Aid", value: () => (M.AIDS.find((a) => a.v === F().aid) || M.AIDS[0]).label,
      control: () => chips({ options: M.AIDS, get: () => F().aid, set: (v) => M.set("focus.aid", v) }) },
    { id: "color", label: "Peaking colour", value: () => (M.PEAK_COLORS.find((c) => c.v === F().color) || {}).label,
      show: () => F().aid !== "off",
      control: () => {
        const el = chips({ options: M.PEAK_COLORS, get: () => F().color, set: (v) => M.set("focus.color", v), cls: "swatches" });
        [...el.children].forEach((b) => b.style.setProperty("--sw", (M.PEAK_COLORS.find((c) => c.v === b.dataset.v) || {}).c));
        return el;
      } },
    { id: "level", label: "Peaking level", value: () => (M.PEAK_LEVELS.find((c) => c.v === F().level) || {}).label,
      show: () => F().aid !== "off",
      control: () => chips({ options: M.PEAK_LEVELS, get: () => F().level, set: (v) => M.set("focus.level", v) }) },
  ], { open: "aid" });
  s.list.append(rows, h("p", { class: "list-note", text: "Focus on the taking lens. Then trim each body's helicoid until both bars peak — the halves only stitch sharp if both are." }));
  s.panel.append(h("div", { class: "role-pair" }, rv, tv),
    h("div", { class: "panel-title", html: "<span>Overlap · the same subject through both bodies</span>" }), ol,
    h("div", { class: "facts" }, match));
  let tick = 0;
  const onStats = () => {
    if (tick++ % 4) return;
    const st = live.stats.sharp;
    if (!live.frames.T || !live.frames.R) { match.set("—", ""); return; }
    const a = Math.round(st.T);
    const b = Math.round(st.R);
    const gap = Math.abs(a - b) / Math.max(a, b, 1);
    if (gap < 0.06) match.set(`T ${a} · R ${b} — matched`, "ok");
    else match.set(`T ${a} · R ${b} — ${a > b ? "R" : "T"} is softer`, "warn");
  };
  let off = null;
  return {
    el: s.el,
    enter() { rv.start(); tv.start(); ol.start(); off = onFrame(onStats); rows.refresh(); },
    leave() { rv.stop(); tv.stop(); ol.stop(); if (off) off(); },
    refresh() { rows.refresh(); rv.update(); tv.update(); ol.update(); },
    dial: (d) => rows.dial(d),
  };
}

// --- LOOK ------------------------------------------------------------------------
const plainLook = (id) => ({ id, base: id, color: 0, highlight: 0, shadow: 0, grain: "off", filter: "none" });

function lookStrip() {
  const el = h("div", { class: "looks" });
  let cells = [];
  let tick = 0;
  const build = () => {
    const custom = M.store.fx.looks || [];
    const all = [...LOOKS.map((l) => ({ ...plainLook(l.id), name: l.name, note: l.note })),
      ...custom.map((c) => ({ ...c, note: "Yours · " + baseOf(c).name }))];
    el.innerHTML = "";
    cells = all.map((look) => {
      const cv = h("canvas", { class: "look-cv" });
      cv.style.filter = ensureFilter("fx-lk-" + look.id, look);
      const b = h("button", { class: "look-cell", type: "button", dataset: { id: look.id },
        on: { click: () => { M.set("look", { ...plainLook(look.base), ...look, name: undefined, note: undefined }); } } },
      h("span", { class: "look-img" }, cv), h("b", { text: look.name }), h("small", { text: look.note }));
      el.append(b);
      return { look, b, cv };
    });
    el.dataset.key = JSON.stringify(custom.map((c) => c.id));
  };
  el.paint = () => {
    const key = JSON.stringify((M.store.fx.looks || []).map((c) => c.id));
    if (el.dataset.key !== key || !cells.length) build();
    const cur = M.photo().look;
    cells.forEach((c) => c.b.classList.toggle("on", c.look.id === cur.id));
  };
  el.frame = () => {
    if (tick++ % 3 && !live.stills) return;
    cells.forEach((c) => drawTo(c.cv, 1));
  };
  el.dial = (dir) => {
    const ids = cells.map((c) => c.look.id);
    const next = stepIn(ids, M.photo().look.id, dir);
    const c = cells.find((x) => x.look.id === next);
    if (c) c.b.click();
  };
  return el;
}

function compareToggle(view) {
  let on = false;
  const b = h("button", { class: "pill-btn", type: "button", html: icon("compare") + "<span>Compare</span>",
    on: { click: () => { on = !on; b.classList.toggle("on", on); view.classList.toggle("split", on); } } });
  return b;
}

export function lookScreen() {
  const s = dim({ id: "look", title: "Look", ic: "look" });
  const strip = lookStrip();
  const view = panoView({ look: true, guide: false });
  const plain = panoView({ look: false, guide: false });
  plain.classList.add("pano-under");
  const stack = h("div", { class: "panel-view compare" }, plain, view);
  const name = h("b");
  const note = h("span");
  const rows = rowList([
    { id: "fine", label: "Fine-tune", icon: "pencil",
      value: () => { const t = tweaks(M.photo().look); return t.length ? t.length + " change" + (t.length > 1 ? "s" : "") : "As defined"; },
      hint: () => tweaks(M.photo().look).join(" · ") || "Color, highlight, shadow, grain",
      go: () => go("look-fine") },
  ]);
  s.list.append(h("div", { class: "group", text: "Looks" }), strip, rows);
  s.panel.append(h("div", { class: "panel-title" }, h("span", { class: "look-name" }, name, note), compareToggle(stack)), stack,
    h("p", { class: "panel-note", text: "Graded after the stitch, so both halves always match. Change it later from Playback and re-stitch." }));
  const paint = () => {
    const look = M.photo().look;
    name.textContent = lookName(look, M.store.fx.looks);
    note.textContent = tweaks(look).join(" · ") || baseOf(look).note;
    strip.paint();
    rows.refresh();
    view.update();
  };
  let off = null;
  return {
    el: s.el,
    enter() { view.start(); plain.start(); off = onFrame(strip.frame); paint(); strip.frame(); },
    leave() { view.stop(); plain.stop(); if (off) off(); },
    refresh: paint,
    dial: (d) => { strip.dial(d); return true; },
  };
}

export function lookFineScreen() {
  const s = dim({ id: "look-fine", title: "Fine-tune", ic: "pencil", crumb: "Look" });
  const view = panoView({ look: true, guide: false });
  const plain = panoView({ look: false, guide: false });
  plain.classList.add("pano-under");
  const stack = h("div", { class: "panel-view compare" }, plain, view);
  const cur = () => M.photo().look;
  const put = (k, v) => M.set("look", { ...cur(), [k]: v });
  const step = (k) => ({
    control: () => ruler({ values: STEPS, get: () => M.signed(Number(cur()[k]) || 0).replace("−", "-"),
      set: (v) => put(k, Number(v)), format: (v) => v.replace("-", "−"), step: 52 }),
    value: () => M.signed(Number(cur()[k]) || 0),
  });
  const rows = rowList([
    { id: "color", label: "Color", show: () => !isMono(cur()), ...step("color") },
    { id: "highlight", label: "Highlight", hint: "+ harder, − softer", ...step("highlight") },
    { id: "shadow", label: "Shadow", hint: "+ deeper, − lifted", ...step("shadow") },
    { id: "filter", label: "Filter", show: () => isMono(cur()), hint: "Colour filter for black and white",
      value: () => (FILTERS.find((f) => f.v === (cur().filter || "none")) || FILTERS[0]).label,
      control: () => chips({ options: FILTERS, get: () => cur().filter || "none", set: (v) => put("filter", v) }) },
    { id: "grain", label: "Grain", value: () => (GRAINS.find((g) => g.v === (cur().grain || "off")) || GRAINS[0]).label,
      control: () => chips({ options: GRAINS, get: () => cur().grain || "off", set: (v) => put("grain", v) }) },
  ], { open: "highlight" });
  const custom = () => (M.store.fx.looks || []).find((c) => c.id === cur().id);
  const saveLooks = async (looks) => M.ingestFx(await api.post("/fxos/api/state", { looks }));
  const acts = h("div", { class: "acts" },
    h("button", { class: "btn", type: "button", html: icon("reset") + "<span>Reset</span>",
      on: { click: () => M.set("look", { ...cur(), color: 0, highlight: 0, shadow: 0, grain: "off", filter: "none" }) } }),
    h("button", { class: "btn primary", type: "button", html: icon("plus") + "<span>Save as new look</span>",
      on: { click: async () => {
        const name = await ask({ title: "Name this look", input: { value: `My ${baseOf(cur()).name}`, max: 24 }, ok: "Save" });
        if (!name) return;
        const look = { ...cur(), id: "u_" + Math.random().toString(16).slice(2, 8), name };
        try {
          await saveLooks([...(M.store.fx.looks || []), look]);
          M.set("look", look);
          toast(`Saved “${name}”`, "ok");
        } catch (e) { toast(e.message, "err"); }
      } } }),
    h("button", { class: "btn danger", type: "button", dataset: { custom: "1" }, html: icon("trash") + "<span>Delete look</span>",
      on: { click: async () => {
        const mine = custom();
        if (!mine || !(await ask({ title: `Delete “${mine.name}”?`, ok: "Delete", danger: true }))) return;
        try {
          await saveLooks((M.store.fx.looks || []).filter((c) => c.id !== mine.id));
          M.set("look", plainLook(mine.base));
        } catch (e) { toast(e.message, "err"); }
      } } }));
  s.list.append(rows, acts);
  s.panel.append(h("div", { class: "panel-title" }, h("span", { class: "look-name" }), compareToggle(stack)), stack);
  const paint = () => {
    const look = cur();
    s.el.querySelector(".bar h1 span:last-child").textContent = lookName(look, M.store.fx.looks);
    s.panel.querySelector(".look-name").textContent = tweaks(look).join(" · ") || "As defined";
    acts.querySelector("[data-custom]").hidden = !custom();
    rows.refresh();
    view.update();
  };
  return {
    el: s.el,
    enter() { view.start(); plain.start(); paint(); },
    leave() { view.stop(); plain.stop(); },
    refresh: paint,
    dial: (d) => rows.dial(d),
  };
}

// --- DRIVE ---------------------------------------------------------------------------
const D = () => M.photo().drive;

function pipeline() {
  const el = h("ol", { class: "pipe" });
  el.paint = () => {
    const d = D();
    const pi = d.save === "pi";
    const steps = [
      { ic: "timer", k: "Timer", v: d.timer ? `${d.timer} s, then release` : "Off", on: !!d.timer },
      { ic: "sync", k: "Release", v: d.release === "sync" ? "T and R together · 10-pin" : "Over USB · T, then R, ~50 ms apart", on: true },
      { ic: "card", k: "Save", v: pi ? `Pi and both cards · ${M.qualityOf(d.quality).label}` : "Stays on the cards", on: true },
      { ic: "stitch", k: "Stitch", v: pi && d.auto_stitch ? `${M.engineOf(d.engine).label}, straight after` : pi ? "When you ask, in Playback" : "Not until downloaded", on: pi && d.auto_stitch },
      { ic: "play", k: "Review", v: d.review ? `${d.review} s` : "Off", on: !!d.review && pi },
    ];
    el.innerHTML = steps.map((s2, i) => `<li class="${s2.on ? "on" : ""}"><span class="pipe-n">${i + 1}</span>`
      + `${icon(s2.ic)}<div><b>${s2.k}</b><span>${s2.v}</span></div></li>`).join("");
  };
  return el;
}

export function driveScreen() {
  const s = dim({ id: "drive", title: "Drive", ic: "drive" });
  const pipe = pipeline();
  const per = fact("Per set");
  const left = fact("Room for");
  const rows = rowList([
    { id: "release", label: "Release", value: () => (D().release === "sync" ? "Sync" : "USB"),
      control: () => cards({ options: [
        { v: "sync", label: "Sync", name: "10-pin, both at once", sub: "For anything that moves" },
        { v: "usb", label: "USB", name: "One body, then the other", sub: "Static scenes, no cable" },
      ], get: () => D().release, set: (v) => M.set("drive.release", v) }) },
    { id: "save", label: "Save to", value: () => (D().save === "pi" ? "Pi + cards" : "Cards only"),
      control: () => chips({ options: [{ v: "pi", label: "Pi + cards" }, { v: "cards", label: "Cards only" }],
        get: () => D().save, set: (v) => M.set("drive.save", v) }) },
    { id: "timer", label: "Self-timer", value: () => (D().timer ? D().timer + " s" : "Off"),
      control: () => chips({ options: M.TIMERS.map((t) => ({ v: t, label: t ? t + " s" : "Off" })),
        get: () => D().timer, set: (v) => M.set("drive.timer", Number(v)) }) },
    { id: "review", label: "Review", value: () => (D().review ? D().review + " s" : "Off"),
      control: () => chips({ options: M.REVIEWS.map((t) => ({ v: t, label: t ? t + " s" : "Off" })),
        get: () => D().review, set: (v) => M.set("drive.review", Number(v)) }) },
    { id: "auto", label: "Auto-stitch", show: () => D().save === "pi", value: () => (D().auto_stitch ? "On" : "Off"),
      control: () => toggle({ get: () => D().auto_stitch, set: (v) => M.set("drive.auto_stitch", v) }) },
    { id: "quality", label: "File", more: true, value: () => M.qualityOf(D().quality).label,
      control: () => cards({ options: M.QUALITY.map((q) => ({ v: q.v, label: q.label, sub: q.sub })),
        get: () => D().quality, set: (v) => M.set("drive.quality", v) }) },
    { id: "engine", label: "Stitch engine", more: true, value: () => M.engineOf(D().engine).label,
      control: () => cards({ options: M.ENGINES.map((e) => ({ v: e.v, label: e.label, sub: e.sub })),
        get: () => D().engine, set: (v) => M.set("drive.engine", v) }) },
  ], { open: "release" });
  s.list.append(rows);
  s.panel.append(h("div", { class: "panel-title", html: "<span>When you press the shutter</span>" }), pipe,
    h("div", { class: "facts" }, per, left));
  const paint = () => {
    rows.refresh();
    pipe.paint();
    per.set(`≈ ${M.setMB()} MB · two bodies`);
    const n = M.setsLeft();
    left.set(n == null ? "—" : `≈ ${n.toLocaleString()} sets on the Pi`);
  };
  return { el: s.el, enter: paint, refresh: paint, dial: (d) => rows.dial(d) };
}

// --- WB ---------------------------------------------------------------------------------
export function wbScreen() {
  const s = dim({ id: "wb", title: "White balance", ic: "wb" });
  const view = panoView({ look: false, guide: false });
  const mark = h("i", { class: "kelvin-mark" });
  const kLabel = h("span", { class: "kelvin-label" });
  const bar = h("div", { class: "kelvin" }, h("div", { class: "kelvin-bar" }, mark),
    h("div", { class: "kelvin-scale", html: "<span>2500 K</span><span>5000 K</span><span>7500 K</span><span>10000 K</span>" }), kLabel);
  const rows = rowList([
    { id: "wb", label: "Preset", value: () => M.wbOf(M.photo().wb).label,
      control: () => cards({ options: M.WB.map((w) => ({ v: w.v, label: w.label, sub: w.k ? w.k + " K" : "Each body decides" })),
        get: () => M.photo().wb, set: (v) => M.set("wb", v), cls: "compact" }) },
  ], { open: "wb" });
  s.list.append(rows);
  s.panel.append(h("div", { class: "panel-view" }, view), bar,
    h("p", { class: "panel-note", text: "Set in both bodies. The preview is what they send, so a preset shows here as soon as they have it." }));
  const paint = () => {
    rows.refresh();
    const w = M.wbOf(M.photo().wb);
    mark.hidden = !w.k;
    if (w.k) mark.style.left = `${((w.k - 2500) / 7500) * 100}%`;
    kLabel.textContent = w.k ? `${w.label} · ${w.k} K` : "Auto · each body measures its own";
    view.update();
  };
  return { el: s.el, enter() { view.start(); paint(); }, leave: () => view.stop(), refresh: paint, dial: (d) => rows.dial(d) };
}
