// Level 1: a photographic control panel. The frame first, the state at a
// glance, every dimension one tap away — built on the Q menu's idea.
import { h, stepIn } from "./ui.js";
import { icon } from "./icons.js";
import { go } from "./nav.js";
import { panoView } from "./views.js";
import { live, onFrame } from "./live.js";
import * as M from "./model.js";
import { LOOKS, lookName, tweaks, baseOf } from "./look.js";
import { fire, busy as shooting } from "./capture.js";
import { toggleLive } from "./app.js";
import * as api from "./api.js";

const DIMS = [
  { id: "frame", label: "Frame", ic: "frame" },
  { id: "light", label: "Light", ic: "light" },
  { id: "focus", label: "Focus", ic: "focus" },
  { id: "look", label: "Look", ic: "look" },
  { id: "drive", label: "Drive", ic: "drive" },
  { id: "wb", label: "WB", ic: "wb" },
];

export function tileText(id) {
  const ph = M.photo();
  switch (id) {
    case "frame": {
      const f = M.formatOf(ph.frame.squeeze);
      const g = M.guideOf(ph.frame.guide);
      return [f.label, (f.sq === 1 ? "Native · 65 MP" : f.name.replace("Anamorphic", "Ana") + " · " + f.sub)
        + (g.r ? " · " + g.label + " guide" : "")];
    }
    case "light":
      return [M.fmtIso(ph.light.iso), M.lightLine(ph.light)];
    case "focus": {
      const a = M.AIDS.find((x) => x.v === ph.focus.aid) || M.AIDS[0];
      const s = live.stats.sharp;
      const bits = ["T", "R"].filter((r) => live.frames[r]).map((r) => `${r} ${Math.round(s[r])}`);
      return [a.label, bits.length ? bits.join(" · ") : "Lens helicoid"];
    }
    case "look": {
      const t = tweaks(ph.look);
      return [lookName(ph.look, M.store.fx.looks), t.length ? t.join(" · ") : baseOf(ph.look).note];
    }
    case "drive":
      return [M.driveLabel(ph.drive), M.driveSub(ph.drive)];
    case "wb": {
      const w = M.wbOf(ph.wb);
      return [w.label, w.k ? `${w.k} K` : "Bodies decide"];
    }
    default:
      return ["", ""];
  }
}

// The dial on a focused tile turns that dimension's main value.
function dialTile(id, dir) {
  const ph = M.photo();
  if (id === "frame") {
    const sq = M.FORMATS.map((f) => f.sq);
    M.set("frame.squeeze", stepIn(sq, M.formatOf(ph.frame.squeeze).sq, dir));
  } else if (id === "light") {
    M.set("light.iso", stepIn(M.ISO, ph.light.iso, dir));
  } else if (id === "focus") {
    M.set("focus.aid", stepIn(M.AIDS.map((a) => a.v), ph.focus.aid, dir));
  } else if (id === "look") {
    const ids = LOOKS.map((l) => l.id);
    const next = stepIn(ids, ph.look.base, dir);
    M.set("look", { id: next, base: next, color: 0, highlight: 0, shadow: 0, grain: "off", filter: "none" });
  } else if (id === "drive") {
    M.set("drive.release", ph.drive.release === "sync" ? "usb" : "sync");
  } else if (id === "wb") {
    M.set("wb", stepIn(M.WB.map((w) => w.v), ph.wb, dir));
  }
}

export function homeScreen() {
  const view = panoView({ look: true, guide: true, peak: true, files: true });
  const strip = h("div", { class: "strip" });
  const warn = h("button", { class: "strip-warn", type: "button", hidden: true, on: { click: () => go("light") } });
  const tapLive = h("button", { class: "view-tap", type: "button", "aria-label": "Start live view",
    on: { click: () => { if (!live.pulling) toggleLive(true); } } });
  const viewWrap = h("div", { class: "view-wrap" }, view, tapLive, strip, warn);

  const tiles = DIMS.map((d) => {
    const v = h("span", { class: "tile-v" });
    const s = h("span", { class: "tile-s" });
    const b = h("button", { class: "tile", type: "button", dataset: { dim: d.id },
      on: { click: () => go(d.id) } },
    h("span", { class: "tile-k", html: icon(d.ic) + `<span>${d.label}</span>` }), v, s);
    b.dial = (dir) => dialTile(d.id, dir);
    return { d, b, v, s };
  });

  const thumb = h("span", { class: "play-img" });
  const playBtn = h("button", { class: "play", type: "button", "aria-label": "Playback",
    on: { click: () => go("playback") } }, thumb, h("span", { class: "play-k", html: icon("play") + "<span>Play</span>" }));
  const shutNote = h("span", { class: "shutter-note" });
  const shutter = h("button", { class: "shutter", type: "button", "aria-label": "Release",
    on: { click: () => fire() } }, h("i"), shutNote);
  const liveBtn = h("button", { class: "livebtn", type: "button", on: { click: () => toggleLive() } });

  const el = h("section", { class: "screen home", dataset: { screen: "home" } },
    h("div", { class: "home-main" }, viewWrap, h("div", { class: "tiles" }, tiles.map((t) => t.b))),
    h("aside", { class: "rail" }, playBtn, shutter, liveBtn));

  let thumbName = "";
  let driftBusy = "";
  let driftGaveUp = "";
  const normIso = (v) => String(v ?? "").replace(/iso/ig, "").replace(/\s+/g, "").toLowerCase();
  const normShut = (v) => String(v ?? "").replace(/\s+/g, "").toLowerCase();
  const driftBits = (t, r) => {
    if (!t || !r) return [];
    const bits = [];
    if (normIso(t.iso) !== normIso(r.iso)) bits.push(`ISO T ${t.iso} R ${r.iso}`);
    if (normShut(t.shutterspeed) !== normShut(r.shutterspeed)) bits.push(`T ${t.shutterspeed} R ${r.shutterspeed}`);
    return bits;
  };
  function paintStrip() {
    const ph = M.photo();
    const L = ph.light;
    const st = M.store.link?.status || {};
    const cells = L.follow_cam
      ? [["Camera decides", ""]]
      : [[L.program, "mode"], [M.fmtIso(L.iso), "iso"],
        [M.fmtShut(L.shutter) + (L.bulb ? " bulb" : ""), "shut"], [M.fmtF(L.fstop), "f"]];
    strip.innerHTML = "";
    cells.forEach(([text, k]) => strip.append(h("span", { class: "strip-c " + k, text })));
    const f = M.formatOf(ph.frame.squeeze);
    strip.append(h("span", { class: "strip-c fmt", text: f.label }));
    const roles = M.store.link?.roles || {};
    const out = ["T", "R"].filter((r) => roles[r]?.paired && !roles[r]?.online);
    const t = st.T;
    const r = st.R;
    let msg = "";
    let kind = "";
    const bits = driftBits(t, r);
    const drift = bits.join(" · ");
    if (!drift) { driftBusy = ""; driftGaveUp = ""; }
    if (out.length === 2) { msg = "No bodies on USB"; kind = "err"; }
    else if (out.length) { msg = out[0] + " off USB"; kind = "err"; }
    else if (drift && !L.follow_cam && !live.capturing && !shooting()) {
      if (driftGaveUp === drift) {
        msg = "Bodies differ · " + drift;
        kind = "warn";
      } else if (driftBusy !== drift) {
        driftBusy = drift;
        msg = "Setting cameras";
        M.applyExposure().then((j) => {
          if (driftBusy !== drift) return;
          const st = (j && j.link && j.link.status) || {};
          const still = driftBits(st.T, st.R).join(" · ");
          if (!j || still === drift) driftGaveUp = drift;
          else if (!still) { driftGaveUp = ""; driftBusy = ""; }
          else driftBusy = "";
          paintStrip();
        });
      } else {
        msg = "Setting cameras";
      }
    } else if (drift) {
      msg = "Bodies differ · " + drift;
      kind = "warn";
    }
    warn.hidden = !msg;
    warn.textContent = msg;
    warn.className = "strip-warn " + kind;
  };

  const paintTiles = () => tiles.forEach((t) => {
    const [v, s] = tileText(t.d.id);
    t.v.textContent = v;
    t.s.textContent = s;
  });

  const paintRail = () => {
    const ph = M.photo();
    shutNote.textContent = ph.drive.timer ? ph.drive.timer + " s" : "";
    shutter.classList.toggle("busy", shooting());
    shutter.classList.toggle("offline", !M.onlineRoles().length);
    const on = live.pulling;
    liveBtn.innerHTML = icon(on ? "eye" : "eyeoff") + `<span>${on ? "Live" : "Live off"}</span>`;
    liveBtn.classList.toggle("on", on);
    tapLive.hidden = on;
    const pair = (M.store.pairs || [])[0];
    const name = pair ? (pair.pano || pair.t || pair.r || "") : "";
    if (name !== thumbName) {
      thumbName = name;
      thumb.style.backgroundImage = name ? `url("${api.file(name, 320)}")` : "none";
    }
    playBtn.classList.toggle("empty", !name);
  };

  let focusTick = 0;
  const onFrameTiles = () => {
    if (focusTick++ % 8 === 0) {
      const [v, s] = tileText("focus");
      tiles[2].v.textContent = v;
      tiles[2].s.textContent = s;
    }
  };

  let offFrame = null;
  return {
    el,
    enter() {
      view.start();
      paintTiles();
      paintStrip();
      paintRail();
      if (!offFrame) offFrame = onFrame(onFrameTiles);
    },
    leave() {
      view.stop();
      if (offFrame) offFrame();
      offFrame = null;
    },
    refresh() {
      paintTiles();
      paintStrip();
      paintRail();
      view.update();
    },
    dial(dir) {
      const t = tiles.find((x) => x.b === document.activeElement);
      if (t) { t.b.dial(dir); return true; }
      return false;
    },
  };
}
