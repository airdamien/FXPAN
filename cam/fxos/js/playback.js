// Playback: panoramas first, the two frames behind them. A look is only
// a grade on top of the stitch, so it can still be changed here.
import { h, toast, ask, chips } from "./ui.js";
import { icon } from "./icons.js";
import { go, back } from "./nav.js";
import { page, fact } from "./kit.js";
import * as M from "./model.js";
import * as api from "./api.js";
import { LOOKS, lookName, tweaks } from "./look.js";
import { stitchBody } from "./capture.js";
import { refreshCaptures } from "./app.js";

const when = (stamp) => {
  const m = String(stamp).match(/^(\d{4})(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)/);
  if (!m) return { day: "", time: stamp, date: null };
  const date = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  return { date, time: `${m[4]}:${m[5]}:${m[6]}` };
};

function dayLabel(date) {
  if (!date) return "Undated";
  const d0 = new Date();
  d0.setHours(0, 0, 0, 0);
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  const days = Math.round((d0 - d) / 864e5);
  if (days === 0) return "Today";
  if (days === 1) return "Yesterday";
  return d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric", year: "numeric" });
}

const stitchState = (p) => {
  const s = p.stitch || {};
  if (s.phase === "queued") return ["queued", "Queued"];
  if (s.running) return ["run", "Stitching"];
  if (s.phase === "error" || s.error) return ["err", "Stitch failed"];
  if (p.pano) return ["ok", ""];
  return p.ready ? ["todo", "Not stitched"] : ["half", p.t ? "R missing" : "T missing"];
};

const fmtBytes = (n) => (n >= 1e12 ? (n / 1e12).toFixed(1) + " TB" : n >= 1e9 ? (n / 1e9).toFixed(0) + " GB" : Math.round(n / 1e6) + " MB");

export function playbackScreen() {
  const s = page({ id: "playback", title: "Playback", ic: "play" });
  const grid = h("div", { class: "shots" });
  s.body.append(grid);
  const paint = () => {
    const d = M.store.disk;
    s.noteEl.textContent = d ? `${fmtBytes(d.free)} free · ${(M.store.pairs || []).length} sets` : "";
    grid.innerHTML = "";
    let day = "";
    for (const p of M.store.pairs || []) {
      const w = when(p.stamp);
      const label = dayLabel(w.date);
      if (label !== day) { day = label; grid.append(h("div", { class: "day", text: label })); }
      const note = M.store.fx.shots[p.stamp] || {};
      const [kind, text] = stitchState(p);
      const art = p.pano
        ? h("span", { class: "shot-art", html: `<img alt="" loading="lazy" src="${api.file(p.pano, 640)}&t=${p.pano_mtime || 0}">` })
        : h("span", { class: "shot-art pair", html: [p.r, p.t].filter(Boolean).map((n) => `<img alt="" loading="lazy" src="${api.file(n, 320)}">`).join("") });
      grid.append(h("button", { class: "shot " + kind, type: "button", on: { click: () => go("shot", { stamp: p.stamp }) } },
        art,
        h("span", { class: "shot-meta" },
          h("b", { text: w.time }),
          h("span", { text: [note.mode_name, note.look ? lookName(note.look, M.store.fx.looks) : ""].filter(Boolean).join(" · ") })),
        p.protected ? h("i", { class: "shot-lock", html: icon("lock") }) : null,
        text ? h("em", { class: "shot-state " + kind, text }) : null));
    }
    if (!(M.store.pairs || []).length) grid.append(h("p", { class: "list-note", text: "Nothing yet. Every release lands here as a set: T, R and the stitched pano." }));
  };
  return { el: s.el, enter() { paint(); refreshCaptures(); }, refresh(what) { if (what !== "link") paint(); } };
}

export function shotScreen() {
  const s = page({ id: "shot", title: "", ic: "play", crumb: "Playback" });
  const prev = h("button", { class: "icon-btn", type: "button", "aria-label": "Previous", html: icon("back"), on: { click: () => step(-1) } });
  const next = h("button", { class: "icon-btn", type: "button", "aria-label": "Next", html: icon("chev"), on: { click: () => step(1) } });
  s.bar.querySelector(".grow").after(prev, next);
  const img = h("img", { class: "big", alt: "" });
  const stage = h("div", { class: "shot-stage" }, img);
  const views = h("div", { class: "chips small" });
  const info = h("div", { class: "facts" });
  const stat = h("div", { class: "rv-stat" });
  const lookRow = h("div");
  const engineRow = h("div");
  const acts = h("div", { class: "acts" });
  const dl = h("div", { class: "acts quiet" });
  const pickBox = h("div", { class: "restitch", hidden: true }, lookRow, engineRow);
  let showMore = false;
  const moreBtn = h("button", { class: "more", type: "button",
    on: { click: () => { showMore = !showMore; paint(); } } });
  s.body.classList.add("shot-body");
  s.body.append(stage, h("div", { class: "shot-foot" },
    h("div", { class: "shot-info" }, views, info),
    h("div", { class: "shot-side" }, h("div", { class: "group", text: "Stitch" }), stat, acts, moreBtn, pickBox, dl)));
  let stamp = "";
  let view = "pano";
  let pick = { look: null, engine: null };
  let poll = 0;
  const pair = () => (M.store.pairs || []).find((p) => p.stamp === stamp);

  function step(dir) {
    const list = M.store.pairs || [];
    const i = list.findIndex((p) => p.stamp === stamp);
    const p = list[i + dir];
    if (p) { stamp = p.stamp; view = "pano"; pick = { look: null, engine: null }; paint(); }
  }

  let x0 = null;
  stage.addEventListener("pointerdown", (e) => { x0 = e.clientX; });
  stage.addEventListener("pointerup", (e) => {
    if (x0 == null) return;
    const dx = e.clientX - x0;
    x0 = null;
    if (Math.abs(dx) > 60) step(dx < 0 ? 1 : -1);
  });

  const exifLine = (e) => (e ? [e.program, e.iso ? `ISO ${e.iso}` : "", e.shutter, e.f ? `f/${e.f}` : "", e.wb].filter(Boolean).join(" · ") : "—");

  async function restitch() {
    const p = pair();
    if (!p || !p.ready) { toast("Need T and R", "err"); return; }
    const note = M.store.fx.shots[stamp] || {};
    const look = pick.look || note.look || M.photo().look;
    const engine = pick.engine || p.stitch?.mode || M.photo().drive.engine;
    try {
      const shot = { ...note, stamp, look };
      M.store.fx.shots[stamp] = shot;
      api.post("/fxos/api/shot", shot).catch(() => {});
      const j = await api.post("/api/pano", { ...stitchBody(stamp, look, engine), squeeze: note.squeeze || M.photo().frame.squeeze });
      toast(j.message || "Stitching", "info");
      watch();
    } catch (e) { toast(e.message, "err"); }
  }

  function stopWatch() {
    clearInterval(poll);
    poll = 0;
  }

  function watch() {
    stopWatch();
    poll = setInterval(async () => {
      try {
        const j = await api.get("/api/pano/job?stamp=" + encodeURIComponent(stamp));
        M.store.pairs = j.pairs || M.store.pairs;
        M.store.disk = j.disk || M.store.disk;
        const job = j.job || {};
        if (!job.running) { stopWatch(); M.emit("captures"); }
        paint();
      } catch { stopWatch(); }
    }, 800);
  }

  function paint() {
    const p = pair();
    if (!p) { stage.classList.add("none"); return; }
    stage.classList.remove("none");
    const note = M.store.fx.shots[stamp] || {};
    const w = when(stamp);
    s.el.querySelector(".bar h1 span:last-child").textContent = `${dayLabel(w.date)} · ${w.time}`;
    const list = M.store.pairs || [];
    const i = list.findIndex((x) => x.stamp === stamp);
    s.noteEl.textContent = `${i + 1} / ${list.length}`;
    prev.disabled = i <= 0;
    next.disabled = i >= list.length - 1;
    const have = [["pano", "Pano", p.pano], ["ana", "Ana", p.pano_ana], ["r", "R", p.r], ["t", "T", p.t]].filter((x) => x[2]);
    if (!have.some((x) => x[0] === view)) view = have[0]?.[0] || "pano";
    views.innerHTML = "";
    have.forEach(([k, label]) => views.append(h("button", { class: "chip" + (k === view ? " on" : ""), type: "button", text: label,
      on: { click: () => { view = k; paint(); } } })));
    const name = { pano: p.pano, ana: p.pano_ana, r: p.r, t: p.t }[view];
    const mtime = view === "pano" ? p.pano_mtime : view === "ana" ? p.pano_ana_mtime : 0;
    const src = name ? api.file(name, 2000) + "&t=" + (mtime || 0) : "";
    if (img.dataset.src !== src) { img.dataset.src = src; img.src = src; }
    img.classList.toggle("flop", view === "r" && !!M.store.prefs.flip_r);
    const e = p.exif || {};
    const st = p.stitch || {};
    info.innerHTML = "";
    info.append(
      fact("Mode", note.mode_name || "—"),
      fact("Look", note.look ? [lookName(note.look, M.store.fx.looks), ...tweaks(note.look)].join(" · ") : "Standard"),
      fact("T", exifLine(e.T), "t"),
      fact("R", exifLine(e.R), "r"),
      fact("Stitch", p.pano ? (st.message || p.pano) : "—"));
    const [kind, text] = stitchState(p);
    stat.className = "rv-stat " + kind;
    stat.textContent = kind === "run" || kind === "queued" ? `${text} · ${st.message || ""}` : kind === "err" ? st.error || text : "";
    const cur = pick.look || note.look || { base: "standard", id: "standard" };
    lookRow.innerHTML = "";
    lookRow.append(h("div", { class: "mini-label", text: "Look" }), chips({
      options: [...LOOKS.map((l) => ({ v: l.id, label: l.name })), ...(M.store.fx.looks || []).map((c) => ({ v: c.id, label: c.name }))],
      get: () => (pick.look || cur).id || "standard",
      set: (v) => {
        const mine = (M.store.fx.looks || []).find((c) => c.id === v);
        pick.look = mine ? { ...mine } : { id: v, base: v, color: 0, highlight: 0, shadow: 0, grain: "off", filter: "none" };
        paint();
      },
      cls: "small",
    }));
    const eng = pick.engine || st.mode || M.photo().drive.engine;
    engineRow.innerHTML = "";
    engineRow.append(h("div", { class: "mini-label", text: "Engine" }), chips({
      options: M.ENGINES.map((x) => ({ v: x.v, label: x.label })), get: () => eng,
      set: (v) => { pick.engine = v; paint(); }, cls: "small" }));
    const busyNow = kind === "run" || kind === "queued";
    const changed = (pick.look && pick.look.id !== (note.look?.id || "standard")) || (pick.engine && pick.engine !== st.mode);
    pickBox.hidden = !showMore;
    moreBtn.innerHTML = (showMore ? "Hide look and engine" : "Change look or engine") + icon("chev", showMore ? "up" : "down");
    acts.innerHTML = "";
    acts.append(
      h("button", { class: "btn primary", type: "button", disabled: busyNow || !p.ready,
        html: icon("stitch") + `<span>${p.pano ? (changed ? "Re-stitch with these" : "Re-stitch") : "Stitch"}</span>`, on: { click: restitch } }),
      h("button", { class: "btn" + (p.protected ? " on" : ""), type: "button",
        html: icon(p.protected ? "lock" : "unlock") + `<span>${p.protected ? "Locked" : "Lock"}</span>`,
        on: { click: async () => {
          try {
            const j = await api.post("/api/captures/protect", { stamp, protected: !p.protected });
            M.store.pairs = j.pairs || M.store.pairs;
            paint();
          } catch (err) { toast(err.message, "err"); }
        } } }),
      h("button", { class: "btn danger", type: "button", disabled: !!p.protected, html: icon("trash") + "<span>Delete</span>",
        on: { click: async () => {
          if (!(await ask({ title: "Delete this set?", text: "T, R and the panorama.", ok: "Delete", danger: true }))) return;
          try {
            const j = await api.post("/api/captures/delete", { stamp });
            M.store.pairs = j.pairs || [];
            M.store.disk = j.disk || M.store.disk;
            M.emit("captures");
            const rest = M.store.pairs;
            if (!rest.length) { back(); return; }
            stamp = (rest[Math.min(i, rest.length - 1)] || rest[0]).stamp;
            paint();
          } catch (err) { toast(err.message, "err"); }
        } } }));
    dl.innerHTML = "";
    if (!M.store.kiosk) {
      [["T", p.t_nef || p.t], ["R", p.r_nef || p.r], ["Pano", p.pano], ["Ana", p.pano_ana]].forEach(([label, n]) => {
        if (n) dl.append(h("a", { class: "btn small", href: api.file(n) + "?dl=1", download: n,
          html: icon("download") + `<span>${label}</span>` }));
      });
    }
    if (busyNow && !poll) watch();
  }

  return {
    el: s.el,
    enter(params) {
      if (params?.stamp) { stamp = params.stamp; view = "pano"; pick = { look: null, engine: null }; showMore = false; }
      if (!stamp) stamp = (M.store.pairs || [])[0]?.stamp || "";
      paint();
    },
    leave: stopWatch,
    refresh(what) { if (what !== "link") paint(); },
    dial(dir) { step(dir); return true; },
  };
}
