import { icon } from "./icons.js";
import { store } from "./model.js";

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export function h(tag, props = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k === "text") el.textContent = v;
    else if (k === "html") el.innerHTML = v;
    else if (k === "on") for (const [ev, fn] of Object.entries(v)) el.addEventListener(ev, fn);
    else if (k === "dataset") Object.assign(el.dataset, v);
    else if (k === "style") el.style.cssText = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

export const touchy = () => store.kiosk || matchMedia("(pointer: coarse)").matches;

// --- toast ------------------------------------------------------------------
const POPUP_MAX = 120;
const POPUP_KEY = "fxos-popup-log";
let popupLog = [];
try {
  const saved = JSON.parse(localStorage.getItem(POPUP_KEY) || "[]");
  if (Array.isArray(saved)) popupLog = saved.slice(0, POPUP_MAX);
} catch { /* ignore a bad store */ }

export function messages() { return popupLog.slice(); }

export function clearMessages() {
  popupLog = [];
  try { localStorage.removeItem(POPUP_KEY); } catch { /* private mode */ }
}

function rememberPopup(msg, kind) {
  popupLog.unshift({ t: Date.now(), kind: kind || "info", msg: String(msg) });
  if (popupLog.length > POPUP_MAX) popupLog.length = POPUP_MAX;
  try { localStorage.setItem(POPUP_KEY, JSON.stringify(popupLog)); } catch { /* quota */ }
}

let toastBox = null;
export function toast(msg, kind = "info", ms = 2800) {
  if (!msg) return;
  rememberPopup(msg, kind);
  if (!toastBox) toastBox = document.body.appendChild(h("div", { class: "toasts", "aria-live": "polite" }));
  const el = h("div", { class: "toast " + kind, text: String(msg) });
  toastBox.append(el);
  while (toastBox.children.length > 3) toastBox.firstChild.remove();
  setTimeout(() => { el.classList.add("out"); setTimeout(() => el.remove(), 260); }, ms);
}

// --- on-screen keyboard ---------------------------------------------------------
const osk = (() => {
  let panel = null;
  let target = null;
  let shift = false;
  let sym = false;
  const rows = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"];
  const symbols = "-_.@#!$%&*()+=:?/'";
  const key = (label, fn, cls = "") => {
    const b = h("button", { class: "key " + cls, type: "button", text: label });
    b.addEventListener("pointerdown", (e) => { e.preventDefault(); fn(); });
    return b;
  };
  const insert = (t) => {
    if (!target) return;
    const a = target.selectionStart ?? target.value.length;
    const b = target.selectionEnd ?? a;
    target.value = target.value.slice(0, a) + t + target.value.slice(b);
    target.setSelectionRange(a + t.length, a + t.length);
    target.dispatchEvent(new Event("input", { bubbles: true }));
  };
  const erase = () => {
    if (!target) return;
    const a = target.selectionStart ?? target.value.length;
    const b = target.selectionEnd ?? a;
    const from = a === b ? Math.max(0, a - 1) : a;
    target.value = target.value.slice(0, from) + target.value.slice(b);
    target.setSelectionRange(from, from);
    target.dispatchEvent(new Event("input", { bubbles: true }));
  };
  const paint = () => {
    panel.innerHTML = "";
    const ch = (c) => (shift ? c.toUpperCase() : c);
    const lines = sym ? [symbols.slice(0, 9), symbols.slice(9)] : rows;
    lines.forEach((line, i) => {
      const row = h("div", { class: "keyrow" });
      if (!sym && i === 3) row.append(key("⇧", () => { shift = !shift; paint(); }, "wide" + (shift ? " on" : "")));
      [...line].forEach((c) => row.append(key(ch(c), () => insert(ch(c)))));
      if (i === lines.length - 1) row.append(key("⌫", erase, "wide"));
      panel.append(row);
    });
    panel.append(h("div", { class: "keyrow" },
      key(sym ? "ABC" : "#+=", () => { sym = !sym; paint(); }, "wide"),
      key("space", () => insert(" "), "space"),
      key("Done", () => hide(true), "wide go")));
  };
  const show = (input) => {
    if (!touchy()) return;
    if (!panel) panel = document.body.appendChild(h("div", { class: "osk" }));
    target = input;
    input.readOnly = true;
    shift = false;
    sym = false;
    paint();
    panel.hidden = false;
    document.body.classList.add("osk-open");
  };
  const hide = (submit) => {
    if (panel) panel.hidden = true;
    document.body.classList.remove("osk-open");
    if (target) {
      target.readOnly = false;
      const t = target;
      target = null;
      if (submit) t.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    }
  };
  return { show, hide };
})();
export { osk };

// --- dialog ------------------------------------------------------------------------
export function ask({ title, text = "", input = null, ok = "OK", cancel = "Cancel", danger = false } = {}) {
  return new Promise((resolve) => {
    const field = input ? h("input", {
      class: "ask-input", type: input.type || "text", value: input.value || "",
      placeholder: input.placeholder || "", maxlength: input.max || 40,
      autocomplete: "off", spellcheck: "false",
    }) : null;
    const done = (val) => {
      osk.hide();
      wrap.remove();
      document.removeEventListener("keydown", onKey, true);
      resolve(val);
    };
    const okBtn = h("button", { class: "btn " + (danger ? "danger" : "primary"), type: "button", text: ok,
      on: { click: () => done(field ? field.value.trim() : true) } });
    const box = h("div", { class: "ask", role: "dialog", "aria-modal": "true" },
      h("h2", { text: title }),
      text ? h("p", { text }) : null,
      field,
      h("div", { class: "ask-acts" },
        cancel ? h("button", { class: "btn", type: "button", text: cancel, on: { click: () => done(null) } }) : null,
        okBtn));
    const wrap = h("div", { class: "veil ask-veil" }, box);
    const onKey = (e) => {
      if (e.key === "Escape") { e.stopPropagation(); e.preventDefault(); done(null); }
      if (e.key === "Enter" && (!field || document.activeElement === field || e.target === field)) {
        e.stopPropagation(); e.preventDefault(); okBtn.click();
      }
    };
    document.addEventListener("keydown", onKey, true);
    document.body.append(wrap);
    if (field) {
      field.focus();
      field.select();
      osk.show(field);
    } else {
      okBtn.focus();
    }
  });
}

// --- controls ------------------------------------------------------------------------
// Every control has refresh() (re-read the model) and dial(dir) (one step),
// so a wheel, a key or a future encoder drives it the same as a finger.
export function chips({ options, get, set, cls = "" }) {
  const el = h("div", { class: "chips " + cls, role: "radiogroup" });
  const btns = options.map((o) => h("button", {
    class: "chip", type: "button", role: "radio", dataset: { v: String(o.v) },
    on: { click: () => { set(o.v); el.refresh(); } },
  }, h("span", { text: o.label }), o.sub ? h("small", { text: o.sub }) : null));
  el.append(...btns);
  el.refresh = () => {
    const cur = String(get());
    btns.forEach((b) => {
      const on = b.dataset.v === cur;
      b.classList.toggle("on", on);
      b.setAttribute("aria-checked", on ? "true" : "false");
    });
  };
  el.dial = (dir) => {
    const i = options.findIndex((o) => String(o.v) === String(get()));
    const j = Math.max(0, Math.min(options.length - 1, (i < 0 ? 0 : i) + dir));
    if (j !== i) { set(options[j].v); el.refresh(); }
  };
  el.refresh();
  return el;
}

export function cards({ options, get, set, cls = "" }) {
  const el = chips({ options: [], get, set });
  el.className = "cards " + cls;
  const btns = options.map((o) => h("button", {
    class: "card", type: "button", role: "radio", dataset: { v: String(o.v) },
    on: { click: () => { set(o.v); el.refresh(); } },
  },
  h("b", { text: o.label }),
  o.name ? h("span", { text: o.name }) : null,
  o.sub ? h("small", { text: o.sub }) : null,
  h("i", { class: "card-check", html: icon("check") })));
  el.append(...btns);
  el.refresh = () => {
    const cur = String(get());
    btns.forEach((b) => b.classList.toggle("on", b.dataset.v === cur));
  };
  el.dial = (dir) => {
    const i = options.findIndex((o) => String(o.v) === String(get()));
    const j = Math.max(0, Math.min(options.length - 1, (i < 0 ? 0 : i) + dir));
    if (j !== i) { set(options[j].v); el.refresh(); }
  };
  el.refresh();
  return el;
}

export function toggle({ get, set, on = "On", off = "Off" }) {
  return chips({ options: [{ v: "0", label: off }, { v: "1", label: on }],
    get: () => (get() ? "1" : "0"), set: (v) => set(v === "1") });
}

export function ruler({ values, get, set, format = (v) => v, step = 64 }) {
  const el = h("div", { class: "ruler", tabindex: "0", role: "slider" });
  const track = h("div", { class: "ruler-track" });
  const ticks = values.map((v, i) => h("span", { class: "tick", dataset: { i }, style: `width:${step}px` },
    h("i"), h("b", { text: format(v) })));
  track.append(...ticks);
  el.append(track, h("span", { class: "ruler-mark" }));
  let idx = Math.max(0, values.indexOf(get()));
  let drag = null;
  let wheel = 0;
  const posOf = (i) => el.clientWidth / 2 - step / 2 - i * step;
  const paint = (anim) => {
    track.classList.toggle("anim", !!anim);
    track.style.transform = `translateX(${posOf(idx)}px)`;
    ticks.forEach((t, i) => t.classList.toggle("on", i === idx));
    el.setAttribute("aria-valuetext", String(format(values[idx])));
  };
  const commit = (i) => {
    const j = Math.max(0, Math.min(values.length - 1, i));
    if (j !== idx) { idx = j; set(values[j]); }
    paint(true);
  };
  el.addEventListener("pointerdown", (e) => {
    if (e.button) return;
    drag = { x: e.clientX, base: posOf(idx), moved: 0, id: e.pointerId, tick: e.target.closest(".tick") };
    el.setPointerCapture(e.pointerId);
    track.classList.remove("anim");
  });
  el.addEventListener("pointermove", (e) => {
    if (!drag) return;
    const dx = e.clientX - drag.x;
    drag.moved = Math.max(drag.moved, Math.abs(dx));
    if (drag.moved < 4) return;
    track.style.transform = `translateX(${drag.base + dx}px)`;
    const live = Math.round((el.clientWidth / 2 - step / 2 - (drag.base + dx)) / step);
    ticks.forEach((t, i) => t.classList.toggle("on", i === Math.max(0, Math.min(values.length - 1, live))));
  });
  const end = (e) => {
    if (!drag) return;
    const d = drag;
    drag = null;
    if (d.moved < 4) {
      if (d.tick) commit(Number(d.tick.dataset.i));
      else paint(true);
      return;
    }
    const dx = e.clientX - d.x;
    commit(Math.round((el.clientWidth / 2 - step / 2 - (d.base + dx)) / step));
  };
  el.addEventListener("pointerup", end);
  el.addEventListener("pointercancel", end);
  el.addEventListener("wheel", (e) => {
    e.preventDefault();
    e.stopPropagation();
    wheel += Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    if (Math.abs(wheel) >= 30) {
      commit(idx + Math.sign(wheel));
      wheel = 0;
    }
  }, { passive: false });
  el.addEventListener("keydown", (e) => {
    if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
      e.preventDefault();
      e.stopPropagation();
      commit(idx + (e.key === "ArrowRight" ? 1 : -1));
    }
  });
  el.refresh = () => {
    if (drag) return;
    const j = values.indexOf(get());
    if (j >= 0) idx = j;
    paint(false);
  };
  el.dial = (dir) => commit(idx + dir);
  new ResizeObserver(() => paint(false)).observe(el);
  requestAnimationFrame(() => paint(false));
  return el;
}

// --- rows --------------------------------------------------------------------------------
// The one list every dimension uses: label, current value, and the control
// that changes it, opened in place. Rows marked `more` sit behind a
// disclosure until they are needed.
export function rowList(defs, { open = null } = {}) {
  const el = h("div", { class: "rows" });
  const items = [];
  let openId = open;
  let selId = open;
  let moreShown = false;
  const moreBtn = h("button", { class: "more", type: "button",
    on: { click: () => { moreShown = !moreShown; paint(); } } });

  for (const def of defs) {
    if (def.heading) {
      const head = h("div", { class: "group", text: def.heading });
      items.push({ def, el: head, heading: true });
      el.append(head);
      continue;
    }
    const head = h("button", { class: "row-head" + (def.icon ? " has-ic" : ""), type: "button", dataset: { id: def.id } },
      def.icon ? h("span", { class: "row-ic", html: icon(def.icon) }) : null,
      h("span", { class: "l" }, h("span", { class: "row-label", text: def.label }),
        def.hint ? h("small", { class: "row-hint" }) : null),
      h("span", { class: "v" }),
      h("span", { class: "chev", html: icon("chev") }));
    const body = h("div", { class: "row-body" });
    const row = h("div", { class: "row" + (def.go ? " link" : ""), dataset: { id: def.id } }, head, body);
    const item = { def, el: row, head, body, ctl: null };
    head.addEventListener("click", () => {
      selId = def.id;
      if (def.go) { def.go(); return; }
      if (def.control) openId = openId === def.id ? null : def.id;
      paint();
    });
    head.addEventListener("focus", () => { selId = def.id; paintSel(); });
    items.push(item);
    el.append(row);
  }
  if (defs.some((d) => d.more)) el.append(moreBtn);

  const paintSel = () => items.forEach((it) => !it.heading && it.el.classList.toggle("sel", it.def.id === selId));
  const paint = () => {
    for (const it of items) {
      const d = it.def;
      const hidden = (d.more && !moreShown) || (d.show && !d.show());
      it.el.hidden = !!hidden;
      if (it.heading) continue;
      it.head.querySelector(".v").textContent = d.value ? d.value() : "";
      const hint = it.head.querySelector(".row-hint");
      if (hint) hint.textContent = typeof d.hint === "function" ? d.hint() : d.hint;
      const isOpen = !hidden && openId === d.id && !!d.control;
      it.el.classList.toggle("open", isOpen);
      if (isOpen && !it.ctl) {
        it.ctl = d.control();
        it.body.append(it.ctl);
      }
      if (isOpen && it.ctl && it.ctl.refresh) it.ctl.refresh();
    }
    items.filter((it) => it.heading).forEach((it) => {
      const next = items.slice(items.indexOf(it) + 1);
      const end = next.findIndex((x) => x.heading);
      const group = end < 0 ? next : next.slice(0, end);
      it.el.hidden = group.every((x) => x.el.hidden);
    });
    moreBtn.innerHTML = moreShown ? `Fewer settings ${icon("chev", "up")}` : `More settings ${icon("chev", "down")}`;
    paintSel();
  };
  el.refresh = paint;
  el.dial = (dir) => {
    const it = items.find((x) => !x.heading && x.def.id === (selId || openId));
    if (!it) return false;
    if (it.def.dial) { it.def.dial(dir); paint(); return true; }
    if (it.ctl && it.ctl.dial) { it.ctl.dial(dir); paint(); return true; }
    return false;
  };
  el.openRow = (id) => { openId = id; selId = id; paint(); };
  paint();
  return el;
}

// Step through a value list for dial handlers on rows without a control open.
export function stepIn(list, cur, dir) {
  const i = list.indexOf(cur);
  return list[Math.max(0, Math.min(list.length - 1, (i < 0 ? 0 : i) + dir))];
}
