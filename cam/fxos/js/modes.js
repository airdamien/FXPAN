// Named modes instead of C1/C2/C3: each is a complete photographic state.
// Recall one and the rig returns to the whole working setup.
import { h, ask, toast } from "./ui.js";
import { icon } from "./icons.js";
import { home } from "./nav.js";
import { dim } from "./kit.js";
import { live, drawTo } from "./live.js";
import * as M from "./model.js";
import * as api from "./api.js";
import { lookName, tweaks, ensureFilter } from "./look.js";

export function includes(mode) {
  const f = mode.frame || {};
  const L = mode.light || {};
  const fo = mode.focus || {};
  const d = mode.drive || {};
  const g = M.guideOf(f.guide);
  const aid = M.AIDS.find((a) => a.v === fo.aid) || M.AIDS[0];
  return [
    ["Frame", M.formatOf(Number(f.squeeze) || 1).label + (g.r ? ` · ${g.label} guide` : "")],
    ["Light", L.follow_cam ? "Camera decides" : `${M.fmtIso(L.iso)} · ${M.fmtShut(L.shutter)} · ${M.fmtF(L.fstop)} · ${L.program}`],
    ["Focus", aid.v === "off" ? "Off" : `${aid.label} · ${fo.color || "red"}`],
    ["Look", [lookName(mode.look, M.store.fx.looks), ...tweaks(mode.look)].join(" · ")],
    ["Drive", [d.release === "sync" ? "GPIO" : "USB", d.save === "pi" ? "Pi" : "cards",
      d.timer ? `${d.timer} s timer` : "", d.auto_stitch && d.save === "pi" ? `auto ${M.engineOf(d.engine).label}` : ""]
      .filter(Boolean).join(" · ")],
    ["WB", M.wbOf(mode.wb).label],
    ["File", M.qualityOf(d.quality).label],
  ];
}

function thumbFor(mode) {
  const shots = M.store.fx.shots || {};
  const stamps = Object.keys(shots).filter((s) => shots[s].mode === mode.id).sort().reverse();
  for (const stamp of stamps) {
    const p = (M.store.pairs || []).find((x) => x.stamp === stamp);
    if (p && (p.pano || p.t)) return api.file(p.pano || p.t, 480);
  }
  return "";
}

export function modesScreen() {
  const s = dim({ id: "modes", title: "Modes", ic: "user" });
  const addBtn = h("button", { class: "done ghost", type: "button", html: icon("plus") + "<span>New from current</span>",
    on: { click: () => create() } });
  s.el.querySelector(".bar .grow").after(addBtn);
  const list = h("div", { class: "modes" });
  const detail = h("div", { class: "mode-detail" });
  s.list.append(list);
  s.panel.append(detail);
  let sel = "";

  const run = async (fn, okMsg) => {
    try {
      const out = await fn();
      if (okMsg) toast(okMsg, "ok");
      return out;
    } catch (e) {
      toast(e.message, "err");
      return null;
    }
  };
  const post = async (body) => M.ingestFx(await api.post("/fxos/api/modes", body));

  async function create() {
    const name = await ask({ title: "Name this mode", text: "Saves everything as it is set now.",
      input: { value: "", placeholder: "Morning light", max: 40 }, ok: "Create" });
    if (!name) return;
    await run(async () => {
      await post({ action: "create", name, mode: M.modeFromPhoto(), activate: true });
      sel = M.store.fx.active;
    }, `Created “${name}”`);
    paint();
  }

  const act = {
    recall: async (m) => {
      const res = await run(() => M.recall(m));
      if (res !== null) { toast(`${m.name} recalled`, "ok"); home(); }
    },
    update: async (m) => {
      if (!(await ask({ title: `Update “${m.name}”?`, text: "Saves the current settings into this mode.", ok: "Update" }))) return;
      await run(() => post({ action: "update", id: m.id, mode: M.modeFromPhoto() }), `${m.name} updated`);
    },
    rename: async (m) => {
      const name = await ask({ title: "Rename mode", input: { value: m.name, max: 40 }, ok: "Rename" });
      if (!name) return;
      await run(() => post({ action: "rename", id: m.id, name }));
    },
    duplicate: async (m) => { await run(() => post({ action: "duplicate", id: m.id })); },
    remove: async (m) => {
      if (!(await ask({ title: `Delete “${m.name}”?`, ok: "Delete", danger: true }))) return;
      await run(() => post({ action: "delete", id: m.id }));
      sel = "";
    },
  };

  const card = (m) => {
    const active = m.id === M.store.fx.active;
    const edited = active && M.diff(m).length > 0;
    const src = thumbFor(m);
    const art = src ? h("span", { class: "mode-art", style: `background-image:url("${src}")` })
      : h("span", { class: "mode-art live" }, h("canvas", { dataset: { look: m.id } }));
    const b = h("button", { class: "mode-card" + (m.id === sel ? " on" : ""), type: "button", dataset: { id: m.id },
      on: { click: () => { sel = m.id; paint(); }, dblclick: () => act.recall(m) } },
    art,
    h("span", { class: "mode-txt" }, h("b", { text: m.name }), h("small", { text: m.note || "" })),
    active ? h("em", { class: "badge " + (edited ? "edited" : "active"), text: edited ? "Edited" : "Active" }) : null);
    return b;
  };

  const paintArt = () => {
    list.querySelectorAll("canvas[data-look]").forEach((cv) => {
      const m = M.store.fx.modes.find((x) => x.id === cv.dataset.look);
      if (!m) return;
      if (drawTo(cv, 1)) cv.style.filter = ensureFilter("fx-md-" + m.id, m.look);
    });
  };

  function paintDetail() {
    const m = M.store.fx.modes.find((x) => x.id === sel);
    detail.innerHTML = "";
    if (!m) {
      detail.append(h("p", { class: "panel-note", text: "Pick a mode to see everything it includes." }));
      return;
    }
    const active = m.id === M.store.fx.active;
    const changes = active ? M.diff(m) : [];
    detail.append(...[
      h("div", { class: "md-head" }, h("h2", { text: m.name }),
        active ? h("em", { class: "badge " + (changes.length ? "edited" : "active"), html: changes.length ? "Edited" : icon("check") + "Active" }) : null),
      m.note ? h("p", { class: "md-note", text: m.note }) : null,
      h("div", { class: "md-inc" }, h("div", { class: "group", text: "Includes" }),
        ...includes(m).map(([k, v]) => h("div", { class: "fact" }, h("span", { text: k }), h("b", { text: v })))),
    ].filter(Boolean));
    if (changes.length) {
      detail.append(h("div", { class: "md-diff" }, h("div", { class: "group", text: "Changed since recall" }),
        ...changes.map((c) => h("div", { class: "fact warn" }, h("span", { text: c.label }),
          h("b", { html: `${c.from} <span class="arrow">→</span> ${c.to}` })))));
    }
    const btn = (label, ic, fn, cls = "") => h("button", { class: "btn " + cls, type: "button",
      html: icon(ic) + `<span>${label}</span>`, on: { click: () => fn(m) } });
    const primary = !active
      ? [btn("Recall", "check", act.recall, "primary")]
      : changes.length ? [btn("Reset changes", "reset", act.recall), btn("Update mode", "save", act.update, "primary")] : [];
    detail.append(h("div", { class: "acts" }, ...primary),
      h("div", { class: "acts quiet" }, btn("Rename", "pencil", act.rename), btn("Duplicate", "copy", act.duplicate),
        btn("Delete", "trash", act.remove, "danger")));
  }

  function paint() {
    const modes = M.store.fx.modes || [];
    if (!sel || !modes.some((m) => m.id === sel)) sel = M.store.fx.active || modes[0]?.id || "";
    list.innerHTML = "";
    modes.forEach((m) => list.append(card(m)));
    if (!modes.length) list.append(h("p", { class: "list-note", text: "No modes yet. Set the rig up, then New from current." }));
    paintArt();
    paintDetail();
  }

  return {
    el: s.el,
    enter() { paint(); if (!live.frames.T) setTimeout(paintArt, 800); },
    refresh(what) { if (what !== "link") paint(); },
    dial(dir) {
      const modes = M.store.fx.modes || [];
      const i = modes.findIndex((m) => m.id === sel);
      const j = Math.max(0, Math.min(modes.length - 1, i + dir));
      if (modes[j]) { sel = modes[j].id; paint(); }
      return true;
    },
  };
}
