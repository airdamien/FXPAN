// System stays separate: rig plumbing that does not compete with
// photographic decisions. Hidden, but there when it is needed.
import { h, rowList, chips, ruler, toggle, toast, ask } from "./ui.js";
import { icon } from "./icons.js";
import { go } from "./nav.js";
import { dim, fact } from "./kit.js";
import { bodyCard } from "./dims.js";
import { panoView } from "./views.js";
import * as M from "./model.js";
import * as api from "./api.js";
import { refreshCaptures, loadSim } from "./app.js";

const P = () => M.store.prefs;
const fmtBytes = (n) => (n >= 1e12 ? (n / 1e12).toFixed(1) + " TB" : n >= 1e9 ? (n / 1e9).toFixed(1) + " GB" : Math.round(n / 1e6) + " MB");
const roleOk = (r) => !!M.store.link?.roles?.[r]?.online;

async function run(fn, ok) {
  try {
    const j = await fn();
    if (ok !== false) toast(ok || j?.message, "ok");
    return j;
  } catch (e) {
    toast(e.message, "err");
    return null;
  }
}

export function systemScreen() {
  const s = dim({ id: "system", title: "System", ic: "gear" });
  const defs = [
    { id: "cams", icon: "camera", label: "Cameras", hint: "Pair T and R, USB, batteries",
      value: () => ["T", "R"].map((r) => r + (roleOk(r) ? " ✓" : " out")).join("  "), go: () => go("sys-cameras") },
    { id: "rig", icon: "rig", label: "Rig calibration", hint: "Overlap, flop R, balance",
      value: () => `${Math.round((Number(P().overlap) || 0.2) * 100)}%${P().flip_r ? " · flop R" : ""}`, go: () => go("sys-rig") },
    { id: "display", icon: "display", label: "Display", hint: "Brightness, sleep",
      value: () => (M.store.bright?.available ? `${M.store.bright.value}%` : "") + (P().idle_min ? ` · ${P().idle_min} min` : " · no sleep"),
      go: () => go("sys-display") },
    { id: "storage", icon: "card", label: "Storage", hint: "Space on the Pi, cleanup",
      value: () => (M.store.disk ? fmtBytes(M.store.disk.free) + " free" : ""), go: () => go("sys-storage") },
    { id: "wifi", icon: "wifi", label: "Wi-Fi", hint: "Network or the rig's own hotspot",
      value: () => (M.store.wifi?.mode === "ap" ? "Hotspot " + (M.store.wifi.ap_ssid || "") : M.store.wifi?.ssid || (M.store.wifi?.available ? "Idle" : "—")),
      go: () => go("sys-wifi") },
    { id: "pi", icon: "power", label: "Pi & kiosk", hint: "GPIO, desktop, classic UI",
      value: () => (M.store.gpio?.pi ? "Pi" : M.store.gpio?.sim ? "GPIO sim" : "Laptop"), go: () => go("sys-pi") },
    { id: "about", icon: "info", label: "About", hint: "Version, keys", value: () => M.store.fx.server?.version || "", go: () => go("sys-about") },
    { id: "sim", icon: "flask", label: "Simulator", hint: "Scenes and failures to review against",
      show: () => M.store.fx.server?.mode === "sim",
      value: () => (M.store.sim?.scenes?.[M.store.sim.scene] || "").replace(/^P_/, ""), go: () => go("sys-sim") },
  ];
  const rows = rowList(defs);
  const tCard = bodyCard("T");
  const rCard = bodyCard("R");
  const linkMsg = fact("USB");
  s.list.append(rows);
  s.panel.append(h("div", { class: "panel-title", html: "<span>The rig at a glance</span>" }),
    h("div", { class: "body-cards" }, rCard, tCard), h("div", { class: "facts" }, linkMsg));
  const paint = () => { rows.refresh(); tCard.paint(); rCard.paint(); linkMsg.set(M.store.link?.message || "—"); };
  return { el: s.el, enter: paint, refresh: paint, dial: (d) => rows.dial(d) };
}

export function camerasScreen() {
  const s = dim({ id: "sys-cameras", title: "Cameras", ic: "camera", crumb: "System" });
  const tCard = bodyCard("T");
  const rCard = bodyCard("R");
  const extras = h("div", { class: "extras" });
  const acts = h("div", { class: "acts" },
    h("button", { class: "btn primary", type: "button", html: icon("usb") + "<span>Detect</span>", on: { click: async (e) => {
      e.currentTarget.disabled = true;
      const j = await run(() => api.get("/api/detect"));
      if (j?.link) M.ingestLink(j.link);
      e.currentTarget.disabled = false;
    } } }),
    h("button", { class: "btn", type: "button", html: icon("flip") + "<span>Swap T and R</span>", on: { click: async () => {
      const j = await run(() => api.post("/api/pair", { swap: true }));
      if (j?.link) M.ingestLink(j.link);
    } } }));
  s.list.append(h("div", { class: "group", text: "Bodies" }),
    h("p", { class: "list-note", text: "T sees through the plate, R off its face. Pairing is by serial, so it survives a USB shuffle." }),
    acts, h("div", { class: "group", text: "Other Nikons on USB" }), extras);
  s.panel.append(h("div", { class: "body-cards tall" }, rCard, tCard));
  const paint = () => {
    tCard.paint();
    rCard.paint();
    const rows = M.store.link?.extras || [];
    extras.innerHTML = "";
    if (!rows.length) extras.append(h("p", { class: "list-note", text: "None." }));
    rows.forEach((row) => extras.append(h("div", { class: "extra" },
      h("span", {}, h("b", { text: (row.model || "Nikon").replace(/^Nikon DSC /, "") }), h("small", { text: `#${String(row.serial).slice(-4)} · ${row.port}` })),
      ...["T", "R"].map((role) => h("button", { class: "btn small", type: "button", text: "Make " + role, on: { click: async () => {
        const j = await run(() => api.post("/api/pair", role === "T" ? { t: row.serial } : { r: row.serial }));
        if (j?.link) M.ingestLink(j.link);
      } } })))));
  };
  return { el: s.el, enter: paint, refresh: paint };
}

export function rigScreen() {
  const s = dim({ id: "sys-rig", title: "Rig calibration", ic: "rig", crumb: "System" });
  const view = panoView({ look: false, guide: false });
  const band = h("div", { class: "seam" });
  view.querySelector(".pano-stage").append(band);
  const OL = Array.from({ length: 46 }, (_, i) => String(i + 5));
  const rows = rowList([
    { id: "flip", label: "Flop R", hint: "R sees a mirror image off the plate", value: () => (P().flip_r ? "On" : "Off"),
      control: () => toggle({ get: () => !!P().flip_r, set: (v) => M.setPrefs({ flip_r: v }) }) },
    { id: "overlap", label: "Overlap", hint: "Designed 20%; checker pairs say 22%",
      value: () => `${Math.round((Number(P().overlap) || 0.2) * 100)}%`,
      control: () => ruler({ values: OL, get: () => String(Math.round((Number(P().overlap) || 0.2) * 100)),
        set: (v) => M.setPrefs({ overlap: Number(v) / 100 }), format: (v) => v + "%", step: 48 }) },
    { id: "balance", label: "Match brightness", hint: "Even T and R before the seam", value: () => (P().balance !== false ? "On" : "Off"),
      control: () => toggle({ get: () => P().balance !== false, set: (v) => M.setPrefs({ balance: v }) }) },
    { id: "deghost", label: "Deghost", hint: "Subtract the plate's second reflection", value: () => (P().deghost ? "On" : "Off"),
      control: () => toggle({ get: () => !!P().deghost, set: (v) => M.setPrefs({ deghost: v }) }) },
  ], { open: "overlap" });
  s.list.append(rows);
  s.panel.append(h("div", { class: "panel-view" }, view),
    h("p", { class: "panel-note", text: "The lit band is the overlap the preview blends. Line up a vertical edge across it; the stitcher refines from there." }));
  const paint = () => {
    rows.refresh();
    const ol = Math.min(0.5, Math.max(0.05, Number(P().overlap) || 0.2));
    const frameW = 1 / (2 - ol);
    band.style.left = `${(1 - ol) * frameW * 100}%`;
    band.style.width = `${ol * frameW * 100}%`;
    view.update();
  };
  return { el: s.el, enter() { view.start(); paint(); }, leave: () => view.stop(), refresh: paint, dial: (d) => rows.dial(d) };
}

export function displayScreen() {
  const s = dim({ id: "sys-display", title: "Display", ic: "display", crumb: "System" });
  const B = Array.from({ length: 20 }, (_, i) => String((i + 1) * 5));
  let brightTimer = 0;
  const rows = rowList([
    { id: "bright", label: "Brightness", show: () => !!M.store.bright?.available,
      value: () => `${M.store.bright?.value ?? "—"}%`,
      control: () => ruler({ values: B, get: () => String(Math.round((M.store.bright?.value || 50) / 5) * 5),
        set: (v) => {
          M.store.bright = { ...M.store.bright, value: Number(v) };
          clearTimeout(brightTimer);
          brightTimer = setTimeout(() => api.post("/api/brightness", { value: Number(v) })
            .then((j) => { M.store.bright = j; }).catch((e) => toast(e.message, "err")), 120);
        }, format: (v) => v + "%", step: 52 }) },
    { id: "idle", label: "Sleep after", hint: "Live view off, slow polling",
      value: () => (P().idle_min ? `${P().idle_min} min` : "Never"),
      control: () => chips({ options: [0, 5, 10, 20, 30, 60].map((m) => ({ v: m, label: m ? m + " min" : "Never" })),
        get: () => Number(P().idle_min) || 0, set: (v) => M.setPrefs({ idle_min: Number(v) }) }) },
  ], { open: "bright" });
  s.list.append(rows);
  s.panel.append(h("p", { class: "panel-note", text: "Brightness drives the HDMI panel over DDC. On a laptop there is no panel to drive." }));
  return { el: s.el, enter: () => rows.refresh(), refresh: () => rows.refresh(), dial: (d) => rows.dial(d) };
}

export function storageScreen() {
  const s = dim({ id: "sys-storage", title: "Storage", ic: "card", crumb: "System" });
  const bar = h("div", { class: "space" }, h("i"));
  const free = fact("Free");
  const sets = fact("Sets");
  const avg = fact("Typical set");
  const post = (path, body, warn) => async () => {
    if (!(await ask({ title: warn, ok: "Delete", danger: true }))) return;
    const j = await run(() => api.post(path, body));
    if (j) { M.store.pairs = j.pairs || M.store.pairs; M.store.disk = j.disk || M.store.disk; M.emit("captures"); }
  };
  s.list.append(h("div", { class: "group", text: "Clean up" }),
    h("div", { class: "acts column" },
      h("button", { class: "btn", type: "button", html: icon("trash") + "<span>Delete everything before today</span>",
        on: { click: post("/api/captures/before-today", {}, "Delete every set from before today?") } }),
      h("button", { class: "btn", type: "button", html: icon("trash") + "<span>Keep the last 5</span>",
        on: { click: post("/api/captures/keep-last", { n: 5 }, "Keep only the 5 newest unlocked sets?") } }),
      h("button", { class: "btn danger", type: "button", html: icon("trash") + "<span>Delete all unlocked</span>",
        on: { click: post("/api/captures/delete-unprotected", {}, "Delete every unlocked set? Locked sets stay.") } })),
    h("p", { class: "list-note", text: "Locked sets are never deleted by these. Lock from Playback or the review." }));
  s.panel.append(h("div", { class: "panel-title", html: "<span>captures/ on the Pi</span>" }), bar, h("div", { class: "facts" }, free, sets, avg));
  const paint = () => {
    const d = M.store.disk;
    if (!d) return;
    const pct = d.total ? Math.round((100 * d.used) / d.total) : 0;
    bar.firstChild.style.width = pct + "%";
    bar.classList.toggle("low", pct > 90);
    free.set(`${fmtBytes(d.free)} of ${fmtBytes(d.total)}`);
    sets.set(`${(M.store.pairs || []).length} here · room for ≈ ${(M.setsLeft() || 0).toLocaleString()} at ${M.qualityOf(P().quality).label}`);
    avg.set(fmtBytes(d.avg_set || 0));
  };
  return { el: s.el, enter() { paint(); refreshCaptures(); }, refresh: paint };
}

export function wifiScreen() {
  const s = dim({ id: "sys-wifi", title: "Wi-Fi", ic: "wifi", crumb: "System" });
  const stat = fact("Now");
  const nets = h("div", { class: "nets" });
  const apBtn = h("button", { class: "btn", type: "button" });
  const scanBtn = h("button", { class: "btn", type: "button", html: icon("wifi") + "<span>Scan</span>" });
  const paint = () => {
    const w = M.store.wifi || {};
    stat.set(w.message || "—");
    apBtn.innerHTML = icon("bolt") + `<span>${w.mode === "ap" ? "Stop hotspot" : "Start hotspot"}</span>`;
    apBtn.classList.toggle("on", w.mode === "ap");
    apBtn.disabled = !w.available;
    scanBtn.disabled = !w.available;
    nets.innerHTML = "";
    (w.networks || []).forEach((n) => nets.append(h("button", { class: "net" + (n.in_use ? " on" : ""), type: "button",
      on: { click: () => join(n) } },
    h("b", { text: n.ssid }), h("span", { text: `${n.signal ? n.signal + "% · " : ""}${n.security || "open"}${n.in_use ? " · connected" : ""}` }))));
  };
  const take = (j) => { if (j) { M.store.wifi = j; paint(); } };
  async function join(n) {
    let psk = "";
    if (n.security) {
      psk = await ask({ title: `Join ${n.ssid}`, input: { type: "password", placeholder: "Password", max: 63 }, ok: "Join" });
      if (psk === null) return;
    }
    take(await run(() => api.post("/api/wifi/join", { ssid: n.ssid, psk })));
  }
  scanBtn.addEventListener("click", async () => { toast("Scanning…"); take(await run(() => api.post("/api/wifi/scan"), false)); });
  apBtn.addEventListener("click", async () => take(await run(() => api.post("/api/wifi/ap", { on: M.store.wifi?.mode !== "ap" }))));
  s.list.append(h("div", { class: "facts" }, stat), h("div", { class: "acts" }, scanBtn, apBtn), nets);
  s.panel.append(h("p", { class: "panel-note", text: "The hotspot lets a phone reach the rig in the field. Its password shows here while it is on." }),
    h("div", { class: "facts" }, fact("Phone", "")));
  const paintPhone = () => {
    const w = M.store.wifi || {};
    s.panel.querySelector(".facts .fact b").textContent = w.mode === "ap" ? `${w.ap_ssid} · ${w.ap_psk || ""} · ${w.url || ""}` : w.url || "—";
  };
  return { el: s.el, enter() { paint(); paintPhone(); }, refresh() { paint(); paintPhone(); } };
}

export function piScreen() {
  const s = dim({ id: "sys-pi", title: "Pi & kiosk", ic: "power", crumb: "System" });
  const rows = rowList([
    { id: "gpio", label: "GPIO shutter", hint: "Off a Pi, simulate the 10-pin release",
      value: () => (M.store.gpio?.pi ? "Pi GPIO " + M.store.gpio.pin : M.store.gpio?.sim ? "Simulated" : "Off"),
      control: () => toggle({ get: () => !!M.store.gpio?.sim, on: "Simulate", off: "Off",
        set: async (v) => { const j = await run(() => api.post("/api/gpio", { sim: v })); if (j) { M.store.gpio = j; rows.refresh(); } } }) },
  ], { open: "gpio" });
  const classic = h("a", { class: "btn", href: M.store.fx.server?.classic || "/", target: "_blank", html: icon("grid") + "<span>Open the classic UI</span>" });
  s.list.append(rows, h("div", { class: "acts column" },
    classic,
    h("button", { class: "btn danger", type: "button", html: icon("power") + "<span>Leave kiosk for the desktop</span>",
      on: { click: async () => {
        if (!(await ask({ title: "Leave the kiosk?", text: "Chromium closes and the Pi desktop comes back.", ok: "Leave" }))) return;
        run(() => api.post("/api/kiosk/exit"));
      } } })));
  s.panel.append(h("p", { class: "panel-note", text: "The classic field page stays on web.py at :8787 and is untouched by this UI." }));
  return { el: s.el, enter() { classic.href = M.store.fx.server?.classic || "/"; rows.refresh(); }, refresh: () => rows.refresh() };
}

const KEYS = [
  ["← ↑ → ↓", "Move between controls (the joystick)"],
  ["Enter", "Open, choose"],
  ["Esc", "Back"],
  ["[ ]  or wheel", "Turn the dial on the selected row"],
  ["Q", "Home"],
  ["F", "Release"],
  ["L", "Live view on / off"],
  ["P", "Playback"],
  ["M", "Modes"],
];

export function aboutScreen() {
  const s = dim({ id: "sys-about", title: "About", ic: "info", crumb: "System" });
  const facts = h("div", { class: "facts" });
  s.list.append(h("div", { class: "group", text: "This build" }), facts,
    h("p", { class: "list-note", text: "Built on five photographic dimensions (Frame, Light, Focus, Look, Drive) with system settings kept apart, after the “GFX Photography OS” proposal. Purpose before decoration; complexity re-organised, not removed." }));
  s.panel.append(h("div", { class: "panel-title", html: "<span>Keys · dials, joystick and touch drive the same UI</span>" }),
    h("div", { class: "keys" }, ...KEYS.map(([k, v]) => h("div", { class: "fact" }, h("span", { class: "kbd", text: k }), h("b", { text: v })))));
  const paint = () => {
    const srv = M.store.fx.server || {};
    facts.innerHTML = "";
    facts.append(fact("Version", srv.version || "dev"),
      fact("Rig", srv.mode === "sim" ? "Simulated D800s" : srv.mode === "proxy" ? "web.py at " + srv.proxy : "—"),
      fact("Display", `${innerWidth} × ${innerHeight}`));
  };
  return { el: s.el, enter: paint, refresh: paint };
}

export function simScreen() {
  const s = dim({ id: "sys-sim", title: "Simulator", ic: "flask", crumb: "System" });
  const view = panoView({ look: false, guide: false });
  const send = async (body) => {
    try {
      M.store.sim = await api.post("/sim/api/control", body);
      await loadSim();
      rows.refresh();
    } catch (e) { toast(e.message, "err"); }
  };
  const sim = () => M.store.sim || {};
  const rows = rowList([
    { id: "scene", label: "Scene", hint: "Cut from your captures/ panoramas",
      value: () => (sim().scenes?.[sim().scene] || "—").replace(/^P_/, ""),
      control: () => chips({ options: (sim().scenes || []).map((n, i) => ({ v: i, label: n.replace(/^P_/, "") })),
        get: () => sim().scene, set: (v) => send({ scene: Number(v) }) }) },
    { id: "t", label: "T on USB", value: () => (sim().online?.T ? "Yes" : "Pulled"),
      control: () => toggle({ get: () => !!sim().online?.T, on: "Plugged", off: "Pulled", set: (v) => send({ online: { T: v } }) }) },
    { id: "r", label: "R on USB", value: () => (sim().online?.R ? "Yes" : "Pulled"),
      control: () => toggle({ get: () => !!sim().online?.R, on: "Plugged", off: "Pulled", set: (v) => send({ online: { R: v } }) }) },
    { id: "desync", label: "Bodies disagree", hint: "R reports a different ISO",
      value: () => (sim().desync ? "Yes" : "No"),
      control: () => toggle({ get: () => !!sim().desync, on: "Disagree", off: "Agree", set: (v) => send({ desync: v }) }) },
    { id: "bat", label: "Batteries", value: () => `T ${sim().battery?.T ?? "—"}% · R ${sim().battery?.R ?? "—"}%`,
      control: () => chips({ options: [{ v: "full", label: "Full" }, { v: "low", label: "R low" }, { v: "dead", label: "Both low" }],
        get: () => "", set: (v) => send({ battery: v === "full" ? { T: 96, R: 94 } : v === "low" ? { R: 12 } : { T: 9, R: 7 } }) }) },
  ], { open: "scene" });
  s.list.append(rows);
  s.panel.append(h("div", { class: "panel-view" }, view),
    h("p", { class: "panel-note", text: "Simulation only: no USB, no gphoto2. Captures and settings live in cam/fxos/.sim/, never in captures/." }));
  return {
    el: s.el,
    async enter() { view.start(); await loadSim(); rows.refresh(); },
    leave: () => view.stop(),
    refresh: () => rows.refresh(),
    dial: (d) => rows.dial(d),
  };
}
