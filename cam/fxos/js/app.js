import { mountIcons, icon } from "./icons.js";
import * as M from "./model.js";
import * as api from "./api.js";
import * as nav from "./nav.js";
import { h, toast, $ } from "./ui.js";
import { live, startPull, stopPull, loadStills } from "./live.js";
import { homeScreen } from "./home.js";
import { frameScreen, lightScreen, lightDualScreen, focusScreen, lookScreen, lookFineScreen, driveScreen, wbScreen } from "./dims.js";
import { modesScreen } from "./modes.js";
import { playbackScreen, shotScreen } from "./playback.js";
import { systemScreen, camerasScreen, rigScreen, displayScreen, storageScreen, wifiScreen, piScreen, aboutScreen, simScreen } from "./system.js";
import { fire, cancelOverlay } from "./capture.js";

// --- top bar ------------------------------------------------------------------------
function batPct(raw) {
  const m = String(raw || "").match(/(\d+)/);
  return m ? Math.min(100, Number(m[1])) : null;
}

function topBar() {
  const name = h("span", { class: "mode-name" });
  const dot = h("i", { class: "mode-dot", title: "Changed since recall" });
  const modeBtn = h("button", { class: "mode-btn", type: "button", on: { click: () => nav.go("modes") } },
    h("span", { class: "mode-ic", html: icon("user") }), name, dot, h("span", { class: "mode-chev", html: icon("chev") }));
  const pill = (role) => {
    const pct = h("span", { class: "pct" });
    const fill = h("i");
    const b = h("button", { class: "cam-pill " + role.toLowerCase(), type: "button", on: { click: () => nav.go("sys-cameras") } },
      h("b", { text: role }), h("span", { class: "bat" }, fill), pct);
    b.paint = () => {
      const r = M.store.link?.roles?.[role];
      const st = M.store.link?.status?.[role];
      const on = !!r?.online;
      const p = batPct(st?.batterylevel);
      b.classList.toggle("off", !on);
      b.classList.toggle("low", on && p != null && p <= 20);
      fill.style.width = (on && p != null ? p : 0) + "%";
      pct.textContent = !on ? "out" : p != null ? p + "%" : "USB";
    };
    return b;
  };
  const T = pill("T");
  const R = pill("R");
  const stitch = h("button", { class: "top-stitch", type: "button", hidden: true, on: { click: () => nav.go("playback") } });
  const storage = h("button", { class: "top-store", type: "button", on: { click: () => nav.go("sys-storage") } });
  const sim = h("button", { class: "top-sim", type: "button", text: "SIM", hidden: true, on: { click: () => nav.go("sys-sim") } });
  const gear = h("button", { class: "top-gear", type: "button", "aria-label": "System", html: icon("gear"), on: { click: () => nav.go("system") } });
  const el = h("header", { class: "top" },
    h("button", { class: "brand", type: "button", "aria-label": "Home", on: { click: () => nav.home() } },
      h("img", { src: "/fxpan.svg", alt: "FXPAN" })),
    modeBtn, h("div", { class: "cams" }, R, T), h("span", { class: "grow" }), stitch, storage, sim, gear);
  el.paint = () => {
    const mode = M.activeMode();
    name.textContent = mode ? mode.name : "Modes";
    dot.hidden = !mode || !M.diff(mode).length;
    T.paint();
    R.paint();
    const q = M.store.queue || {};
    stitch.hidden = !(q.running || q.queued);
    stitch.innerHTML = `<i class="spin"></i><span>${q.running ? "Stitching" : "Queued"}${q.queued ? ` · ${q.queued} waiting` : ""}</span>`;
    const n = M.setsLeft();
    storage.innerHTML = icon("card") + `<span>${n == null ? "—" : n >= 10000 ? Math.round(n / 1000) + "k" : n.toLocaleString()}</span>`;
    storage.title = "Sets left on the Pi at this file format";
    sim.hidden = M.store.fx.server?.mode !== "sim";
  };
  return el;
}

// --- live / captures ------------------------------------------------------------
let stillKey = "";

function showStill() {
  if (live.pulling) return;
  const p = (M.store.pairs || []).find((x) => x.ready);
  const key = p ? p.stamp + ":" + (p.pano_mtime || 0) : "";
  if (!p || key === stillKey) return;
  stillKey = key;
  loadStills(p);
}

let liveGen = 0;

export async function toggleLive(want) {
  const on = want === undefined ? !live.pulling : !!want;
  if (on === live.pulling) return;
  const gen = ++liveGen;
  if (on && M.photo().drive.release === "sync") {
    M.set("drive.release", "usb");
    toast("Live view uses USB release", "info");
  }
  if (on) {
    // Flip the button before the cameras answer. The stream starts when
    // the first JPEG arrives; a failure puts the button back.
    startPull();
    M.emit("live");
    try {
      const j = await api.post("/api/live/start");
      if (gen !== liveGen) return;
      M.ingestLink(j);
      if (!j.ok) {
        stopPull();
        M.emit("live");
        toast(j.message || "Live view did not start", "err");
      }
    } catch (e) {
      if (gen !== liveGen) return;
      stopPull();
      M.emit("live");
      toast(e.message, "err");
    }
  } else {
    stopPull();
    live.stills = true;
    M.emit("live");
    stillKey = "";
    showStill();
    api.post("/api/live/stop").then((j) => {
      if (gen === liveGen && j.link) M.ingestLink(j.link);
    }).catch(() => {});
  }
}

export async function refreshCaptures() {
  try {
    const j = await api.get("/api/captures");
    M.store.pairs = j.pairs || [];
    M.store.disk = j.disk || null;
    M.store.queue = j.queue || null;
    M.emit("captures");
    showStill();
  } catch { /* next poll */ }
}

export async function loadSim() {
  if (M.store.fx.server?.mode !== "sim") return;
  try { M.store.sim = await api.get("/sim/api/state"); } catch { /* not a sim */ }
}

let linkTimer = 0;
let linkMs = 1500;

async function pollLink() {
  try {
    const j = await api.get("/api/link");
    const prev = M.store.link;
    M.ingestLink(j);
    if (prev && j.want_live !== prev.want_live) {
      if (j.want_live && !live.pulling) startPull();
      if (!j.want_live && live.pulling) { stopPull(); live.stills = true; stillKey = ""; showStill(); }
      M.emit("live");
    }
  } catch { /* server restarting */ }
}

function startLinkPoll(ms) {
  if (ms) linkMs = ms;
  clearInterval(linkTimer);
  linkTimer = setInterval(pollLink, linkMs);
}

let capTimer = 0;
function capturesLoop() {
  clearTimeout(capTimer);
  const busy = M.store.queue && (M.store.queue.running || M.store.queue.queued);
  capTimer = setTimeout(async () => { await refreshCaptures(); capturesLoop(); }, busy ? 900 : 8000);
}

// --- sleep ------------------------------------------------------------------------------
let idleTimer = 0;
let sleeping = null;

function armIdle() {
  clearTimeout(idleTimer);
  const min = Number(M.store.prefs.idle_min) || 0;
  if (min && !sleeping) idleTimer = setTimeout(sleep, min * 60000);
}

async function sleep() {
  if (sleeping) return;
  sleeping = h("div", { class: "veil sleep" }, h("div", { class: "sleep-box", html: `${icon("power")}<b>Sleeping</b><span>Touch to wake</span>` }));
  document.body.append(sleeping);
  if (live.pulling) await toggleLive(false);
  api.post("/api/idle", { idle: true }).catch(() => {});
  startLinkPoll(15000);
}

function wake(e) {
  if (!sleeping) { armIdle(); return; }
  e.preventDefault();
  e.stopPropagation();
  sleeping.remove();
  sleeping = null;
  api.post("/api/idle", { idle: false }).catch(() => {});
  startLinkPoll(1500);
  armIdle();
}

// --- input: the joystick, the dial, back ------------------------------------------------
function focusables(root) {
  return [...root.querySelectorAll("button, a[href], [tabindex='0'], input")]
    .filter((el) => !el.disabled && el.offsetParent !== null && !el.closest("[hidden]"));
}

function layer() {
  return document.querySelector(".veil.review, .veil.ask-veil") || $("#app");
}

function moveFocus(key) {
  const els = focusables(layer());
  const cur = document.activeElement;
  if (!els.includes(cur)) {
    const first = layer() === $("#app") ? els.find((el) => nav.current()?.el.contains(el)) || els[0] : els[0];
    if (first) first.focus();
    return;
  }
  const a = cur.getBoundingClientRect();
  const ax = a.left + a.width / 2;
  const ay = a.top + a.height / 2;
  let best = null;
  let score = Infinity;
  for (const el of els) {
    if (el === cur) continue;
    const b = el.getBoundingClientRect();
    const dx = b.left + b.width / 2 - ax;
    const dy = b.top + b.height / 2 - ay;
    let main;
    let side;
    if (key === "ArrowRight") { if (dx <= 2) continue; main = dx; side = Math.abs(dy); }
    else if (key === "ArrowLeft") { if (dx >= -2) continue; main = -dx; side = Math.abs(dy); }
    else if (key === "ArrowDown") { if (dy <= 2) continue; main = dy; side = Math.abs(dx); }
    else { if (dy >= -2) continue; main = -dy; side = Math.abs(dx); }
    const sc = main + side * 2.2;
    if (sc < score) { score = sc; best = el; }
  }
  if (best) { best.focus(); best.scrollIntoView({ block: "nearest", inline: "nearest" }); }
}

function dial(dir) {
  const s = nav.current();
  if (s && s.dial && s.dial(dir)) return;
  const el = document.activeElement;
  if (el && el.dial) el.dial(dir);
}

function goBack() {
  if (cancelOverlay()) return;
  if (!nav.back()) nav.home();
}

function onKey(e) {
  if (e.target.matches && e.target.matches("input, textarea")) return;
  if (document.querySelector(".veil.ask-veil")) return;
  const k = e.key;
  if (k === "Escape" || k === "Backspace") { e.preventDefault(); goBack(); return; }
  if (k.startsWith("Arrow")) { e.preventDefault(); document.body.classList.add("kbd"); moveFocus(k); return; }
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (k === "[" || k === ",") { e.preventDefault(); dial(-1); return; }
  if (k === "]" || k === ".") { e.preventDefault(); dial(1); return; }
  const lower = k.toLowerCase();
  if (document.querySelector(".veil.review")) return;
  if (lower === "q") nav.home();
  else if (lower === "f") fire();
  else if (lower === "l") toggleLive();
  else if (lower === "p") nav.go("playback");
  else if (lower === "m") nav.go("modes");
  else if (k === "?") nav.go("sys-about");
}

let wheelAcc = 0;
function onWheel(e) {
  if (e.target.closest(".ruler, .dim-list, .page-body, .veil")) return;
  wheelAcc += e.deltaY;
  if (Math.abs(wheelAcc) < 40) return;
  dial(wheelAcc > 0 ? 1 : -1);
  wheelAcc = 0;
}

// --- boot ---------------------------------------------------------------------------------
async function boot() {
  mountIcons();
  if (M.store.kiosk) document.documentElement.classList.add("kiosk");
  const app = $("#app");
  const top = topBar();
  const screens = h("main", { class: "screens" });
  app.append(top, screens);
  nav.mount(screens);
  const table = {
    home: homeScreen, frame: frameScreen, light: lightScreen, "light-dual": lightDualScreen,
    focus: focusScreen, look: lookScreen, "look-fine": lookFineScreen, drive: driveScreen, wb: wbScreen,
    modes: modesScreen, playback: playbackScreen, shot: shotScreen,
    system: systemScreen, "sys-cameras": camerasScreen, "sys-rig": rigScreen, "sys-display": displayScreen,
    "sys-storage": storageScreen, "sys-wifi": wifiScreen, "sys-pi": piScreen, "sys-about": aboutScreen,
    "sys-sim": simScreen,
  };
  Object.entries(table).forEach(([id, make]) => nav.screen(id, make));
  M.onError((e) => toast(e.message, "err"));
  M.on((what, data) => {
    top.paint();
    nav.refreshAll(what);
    if ((what === "photo" || what === "prefs") && M.photo().drive.release === "sync" && live.pulling)
      toggleLive(false);
    if (what === "prefs") armIdle();
    if (what === "applied" && data?.message && /\(/.test(data.message)) toast(data.message, "warn", 4200);
  });
  document.addEventListener("keydown", onKey);
  document.addEventListener("pointerdown", () => document.body.classList.remove("kbd"), { capture: true });
  document.addEventListener("pointerdown", wake, { capture: true });
  document.addEventListener("keydown", wake, { capture: true });
  screens.addEventListener("wheel", onWheel, { passive: true });
  if (navigator.wakeLock) {
    const lock = () => navigator.wakeLock.request("screen").catch(() => {});
    lock();
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") lock(); });
  }
  try {
    const [meta, fx] = await Promise.all([api.get("/api/meta"), api.get("/fxos/api/state")]);
    M.store.prefs = meta.settings || {};
    M.store.gpio = meta.gpio || null;
    M.store.wifi = meta.wifi || null;
    M.store.bright = meta.brightness || null;
    M.ingestFx(fx);
    M.ingestLink(meta.link);
    await loadSim();
    nav.home();
    await refreshCaptures();
    if (meta.link?.want_live) startPull();
    else showStill();
    M.emit("live");
  } catch (e) {
    nav.home();
    toast("Rig unreachable: " + e.message, "err", 6000);
  }
  startLinkPoll();
  capturesLoop();
  armIdle();
}

boot();
